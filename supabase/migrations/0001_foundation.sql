-- 0001_foundation.sql  [Written, untested: needs a real Supabase/Postgres to run]
-- Geography, profiles, roles, provider profiles, verification workflow, audit log, RLS.

-- gen_random_uuid() is built in (PG13+); no extension required.

-- ---------- enums ----------
create type public.app_role as enum (
  'CUSTOMER','CONTRACTOR','SUPPLIER','ENGINEER','ARCHITECT','DRAFTSMAN',
  'WORKER','MACHINERY_PROVIDER','COMPANY_ADMIN','PLATFORM_ADMIN');

create type public.provider_type as enum (
  'CONTRACTOR','ENGINEER','ARCHITECT','DRAFTSMAN','WORKER','SUPPLIER','MACHINERY_PROVIDER');

create type public.verification_status as enum (
  'unsubmitted','pending','under_review','verified','rejected');

create type public.verification_doc_type as enum (
  'national_id_front','national_id_back','selfie','business_registration','certificate','other');

-- ---------- helpers ----------
create function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;

-- ---------- geography (country-neutral) ----------
create table public.countries (
  id uuid primary key default gen_random_uuid(),
  iso2 char(2) not null unique,
  name text not null,
  name_i18n jsonb not null default '{}',
  default_currency char(3) not null,
  default_locale text not null default 'en',
  default_timezone text not null,
  measurement_system text not null default 'metric' check (measurement_system in ('metric','imperial')),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.regions (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  code text not null,
  name text not null,
  name_i18n jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (country_id, code)
);
create index regions_country_idx on public.regions(country_id);

create table public.cities (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  region_id uuid not null references public.regions(id) on delete restrict,
  slug text not null,
  name text not null,
  name_i18n jsonb not null default '{}',
  latitude numeric(9,6), longitude numeric(9,6),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (country_id, slug),
  unique (id, country_id)               -- target for composite FKs
);
create index cities_region_idx on public.cities(region_id);

create table public.areas (
  id uuid primary key default gen_random_uuid(),
  city_id uuid not null references public.cities(id) on delete restrict,
  slug text not null,
  name text not null,
  name_i18n jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (city_id, slug),
  unique (id, city_id)
);
create index areas_city_idx on public.areas(city_id);

create trigger countries_updated before update on public.countries for each row execute function public.set_updated_at();
create trigger regions_updated   before update on public.regions   for each row execute function public.set_updated_at();
create trigger cities_updated    before update on public.cities    for each row execute function public.set_updated_at();
create trigger areas_updated     before update on public.areas     for each row execute function public.set_updated_at();

-- ---------- users, profiles, roles ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  avatar_path text,
  preferred_locale text not null default 'en',
  city_id uuid references public.cities(id),
  is_suspended boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index profiles_city_idx on public.profiles(city_id);
create trigger profiles_updated before update on public.profiles for each row execute function public.set_updated_at();

create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null,
  granted_by uuid references public.profiles(id),
  granted_at timestamptz not null default now(),
  primary key (user_id, role)
);
create index user_roles_role_idx on public.user_roles(role);

create function public.has_role(_role public.app_role) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.user_roles
                 where user_id = (select auth.uid()) and role = _role)
$$;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select public.has_role('PLATFORM_ADMIN'::public.app_role)
$$;

-- ---------- audit log (append-only) ----------
create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index audit_logs_entity_idx on public.audit_logs(entity_type, entity_id);
create index audit_logs_actor_idx on public.audit_logs(actor_id);

create function public.write_audit(_action text, _entity_type text, _entity_id uuid, _meta jsonb default '{}')
returns void language sql security definer set search_path = '' as $$
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), _action, _entity_type, _entity_id, coalesce(_meta, '{}'::jsonb))
$$;
revoke execute on function public.write_audit(text, text, uuid, jsonb) from public, anon, authenticated;

-- auto-create profile on signup (grants NO role)
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- protect privileged profile columns from end users (security-definer RPCs run as owner and pass)
create function public.guard_profile() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') and not public.is_admin() then
    if new.is_suspended is distinct from old.is_suspended or new.id is distinct from old.id then
      raise exception 'protected column' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger profiles_guard before update on public.profiles for each row execute function public.guard_profile();

-- self-service role selection (cannot grant admin roles)
create function public.choose_role(_role public.app_role) returns void
language plpgsql security definer set search_path = '' as $$
declare _uid uuid := (select auth.uid());
begin
  if _uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if _role in ('PLATFORM_ADMIN','COMPANY_ADMIN') then
    raise exception 'role is not self-assignable' using errcode = '42501';
  end if;
  if exists (select 1 from public.profiles where id = _uid and is_suspended) then
    raise exception 'account suspended' using errcode = '42501';
  end if;
  insert into public.user_roles(user_id, role, granted_by) values (_uid, _role, _uid)
  on conflict do nothing;
  perform public.write_audit('role.chosen', 'user', _uid, jsonb_build_object('role', _role));
end $$;
revoke execute on function public.choose_role(public.app_role) from public, anon;
grant execute on function public.choose_role(public.app_role) to authenticated;

-- ---------- provider profiles ----------
create table public.provider_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider_type public.provider_type not null,
  display_name text not null check (char_length(display_name) between 2 and 120),
  headline text check (char_length(headline) <= 160),
  description text check (char_length(description) <= 4000),
  years_experience int check (years_experience between 0 and 80),
  city_id uuid references public.cities(id),
  area_id uuid references public.areas(id),
  phone text, whatsapp text,
  daily_rate numeric(12,2) check (daily_rate >= 0),
  hourly_rate numeric(12,2) check (hourly_rate >= 0),
  currency char(3),
  availability text not null default 'unknown' check (availability in ('available','busy','unavailable','unknown')),
  attributes jsonb not null default '{}',          -- type-specific fields, validated server-side
  verification_status public.verification_status not null default 'unsubmitted',
  verified_at timestamptz,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider_type),
  check ((daily_rate is null and hourly_rate is null) or currency is not null)
);
create index provider_profiles_user_idx on public.provider_profiles(user_id);
create index provider_profiles_listing_idx on public.provider_profiles(city_id, provider_type) where is_published;
create index provider_profiles_status_idx on public.provider_profiles(verification_status);
create trigger provider_profiles_updated before update on public.provider_profiles for each row execute function public.set_updated_at();

create function public.guard_provider_profile() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.verification_status := 'unsubmitted';
      new.verified_at := null;
    elsif new.verification_status is distinct from old.verification_status
       or new.verified_at is distinct from old.verified_at
       or new.user_id is distinct from old.user_id
       or new.provider_type is distinct from old.provider_type then
      raise exception 'protected column' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
create trigger provider_profiles_guard before insert or update on public.provider_profiles
  for each row execute function public.guard_provider_profile();

-- ---------- verification workflow ----------
create table public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  provider_profile_id uuid not null references public.provider_profiles(id) on delete cascade,
  submitted_by uuid not null references public.profiles(id),
  status public.verification_status not null default 'pending'
    check (status <> 'unsubmitted'),
  reviewer_id uuid references public.profiles(id),
  review_notes text,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create index verification_requests_provider_idx on public.verification_requests(provider_profile_id);
create index verification_requests_queue_idx on public.verification_requests(status, submitted_at);
create unique index verification_one_active_idx on public.verification_requests(provider_profile_id)
  where status in ('pending','under_review');

create table public.verification_documents (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.verification_requests(id) on delete cascade,
  uploader_id uuid not null references public.profiles(id),
  doc_type public.verification_doc_type not null,
  storage_path text not null unique,           -- in private bucket 'verification-docs'
  mime_type text not null check (mime_type in ('image/jpeg','image/png','application/pdf')),
  size_bytes int not null check (size_bytes between 1 and 5242880),
  created_at timestamptz not null default now(),
  check (storage_path like uploader_id::text || '/%')
);
create index verification_documents_request_idx on public.verification_documents(request_id);

create table public.verification_events (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.verification_requests(id) on delete cascade,
  actor_id uuid references public.profiles(id),
  from_status public.verification_status,
  to_status public.verification_status not null,
  note text,
  created_at timestamptz not null default now()
);
create index verification_events_request_idx on public.verification_events(request_id);

create function public.submit_verification(_provider_profile_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := (select auth.uid());
  _p public.provider_profiles;
  _rid uuid;
begin
  if _uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into _p from public.provider_profiles where id = _provider_profile_id and user_id = _uid;
  if not found then raise exception 'provider profile not found' using errcode = 'P0002'; end if;
  if _p.verification_status in ('pending','under_review','verified') then
    raise exception 'verification already %', _p.verification_status;
  end if;
  insert into public.verification_requests(provider_profile_id, submitted_by)
  values (_p.id, _uid) returning id into _rid;
  update public.provider_profiles set verification_status = 'pending' where id = _p.id;
  insert into public.verification_events(request_id, actor_id, from_status, to_status)
  values (_rid, _uid, _p.verification_status, 'pending');
  perform public.write_audit('verification.submitted', 'verification_request', _rid, '{}');
  return _rid;
end $$;
revoke execute on function public.submit_verification(uuid) from public, anon;
grant execute on function public.submit_verification(uuid) to authenticated;

create function public.admin_review_verification(
  _request_id uuid, _new_status public.verification_status, _note text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := (select auth.uid());
  _r public.verification_requests;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into _r from public.verification_requests where id = _request_id for update;
  if not found then raise exception 'request not found' using errcode = 'P0002'; end if;
  if not ((_r.status = 'pending' and _new_status in ('under_review','rejected'))
       or (_r.status = 'under_review' and _new_status in ('verified','rejected'))) then
    raise exception 'invalid transition % -> %', _r.status, _new_status;
  end if;
  if _new_status = 'under_review' and not exists
     (select 1 from public.verification_documents where request_id = _request_id) then
    raise exception 'no documents attached';
  end if;
  if _new_status = 'rejected' and coalesce(trim(_note), '') = '' then
    raise exception 'a note is required when rejecting';
  end if;
  update public.verification_requests
     set status = _new_status, reviewer_id = _uid, review_notes = _note,
         reviewed_at = case when _new_status in ('verified','rejected') then now() end
   where id = _request_id;
  update public.provider_profiles
     set verification_status = _new_status,
         verified_at = case when _new_status = 'verified' then now() end
   where id = _r.provider_profile_id;
  insert into public.verification_events(request_id, actor_id, from_status, to_status, note)
  values (_request_id, _uid, _r.status, _new_status, _note);
  perform public.write_audit('verification.' || _new_status::text, 'verification_request', _request_id, '{}');
end $$;
revoke execute on function public.admin_review_verification(uuid, public.verification_status, text) from public, anon;
grant execute on function public.admin_review_verification(uuid, public.verification_status, text) to authenticated;

-- ---------- RLS ----------
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.provider_profiles enable row level security;
alter table public.verification_requests enable row level security;
alter table public.verification_documents enable row level security;
alter table public.verification_events enable row level security;
alter table public.audit_logs enable row level security;

-- geography: public read, admin write
do $$
declare t text;
begin
  foreach t in array array['countries','regions','cities','areas'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)', t || '_read', t);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))', t || '_admin_write', t);
  end loop;
end $$;

create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy user_roles_select on public.user_roles for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
-- no insert/update/delete policies: roles change only through choose_role() or the owner

create policy provider_select on public.provider_profiles for select to anon, authenticated
  using (is_published or user_id = (select auth.uid()) or (select public.is_admin()));
create policy provider_insert_own on public.provider_profiles for insert to authenticated
  with check (user_id = (select auth.uid())
              and (select public.has_role(provider_type::text::public.app_role)));
create policy provider_update_own on public.provider_profiles for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy provider_admin_update on public.provider_profiles for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

create policy vreq_select on public.verification_requests for select to authenticated
  using (submitted_by = (select auth.uid()) or (select public.is_admin()));

create policy vdoc_select on public.verification_documents for select to authenticated
  using (uploader_id = (select auth.uid()) or (select public.is_admin()));
create policy vdoc_insert_own on public.verification_documents for insert to authenticated
  with check (uploader_id = (select auth.uid())
    and exists (select 1 from public.verification_requests r
                where r.id = request_id and r.submitted_by = (select auth.uid()) and r.status = 'pending'));

create policy vevent_select on public.verification_events for select to authenticated
  using ((select public.is_admin())
         or exists (select 1 from public.verification_requests r
                    where r.id = request_id and r.submitted_by = (select auth.uid())));

create policy audit_admin_select on public.audit_logs for select to authenticated
  using ((select public.is_admin()));

-- tighten table privileges: workflow/audit tables are not directly writable by clients
revoke all on public.audit_logs, public.user_roles, public.verification_requests, public.verification_events from anon, authenticated;
grant select on public.audit_logs, public.user_roles, public.verification_requests, public.verification_events to authenticated;
revoke all on public.verification_documents from anon;
revoke update, delete on public.verification_documents from authenticated;
revoke delete on public.profiles, public.provider_profiles from authenticated;
