-- 0002_security_private_helpers_and_publish_rules.sql
-- COPIED FROM THE LIVE DATABASE HISTORY (version 20261004180507). This was applied to project
-- trjrkzkpdilgyfuogfba by a session other than the one that wrote this file; it is recorded here so the repo
-- matches production. Verified by the 64-test suite run after application.

-- 1. private schema for RLS helper functions (not an API-exposed schema)
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

alter function public.has_role(public.app_role) set schema private;
alter function public.is_admin() set schema private;

create or replace function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.has_role('PLATFORM_ADMIN'::public.app_role)
$$;

create function private.is_suspended(_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select is_suspended from public.profiles where id = _uid), false)
$$;

revoke execute on function private.has_role(public.app_role) from public;
revoke execute on function private.is_admin() from public;
revoke execute on function private.is_suspended(uuid) from public;
grant execute on function private.has_role(public.app_role) to anon, authenticated;
grant execute on function private.is_admin() to anon, authenticated;
grant execute on function private.is_suspended(uuid) to anon, authenticated;

-- 2. repoint functions that referenced the old public.* names by text
create or replace function public.guard_profile() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') and not private.is_admin() then
    if new.is_suspended is distinct from old.is_suspended or new.id is distinct from old.id then
      raise exception 'protected column' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create or replace function public.guard_provider_profile() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('anon','authenticated') and not private.is_admin() then
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

-- 3. verified-only publishing
alter table public.provider_profiles
  add constraint provider_published_requires_verified
  check (not is_published or verification_status = 'verified');

create function public.enforce_publish_rules() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.is_published then
    if tg_op = 'INSERT' or not old.is_published then
      if new.verification_status <> 'verified' then
        raise exception 'only verified providers can be published' using errcode = '23514';
      end if;
      if private.is_suspended(new.user_id) then
        raise exception 'suspended accounts cannot be published' using errcode = '42501';
      end if;
    elsif new.verification_status <> 'verified' then
      new.is_published := false;
    end if;
  end if;
  return new;
end $$;
create trigger provider_profiles_publish_rules before insert or update on public.provider_profiles
  for each row execute function public.enforce_publish_rules();

drop policy provider_select on public.provider_profiles;
create policy provider_select on public.provider_profiles for select to anon, authenticated
  using (
    (is_published and verification_status = 'verified' and not private.is_suspended(user_id))
    or user_id = (select auth.uid())
    or (select private.is_admin())
  );

-- 4. review workflow: add verified -> rejected (revocation), audit unpublishing
create or replace function public.admin_review_verification(
  _request_id uuid, _new_status public.verification_status, _note text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := (select auth.uid());
  _r public.verification_requests;
  _was_published boolean;
begin
  if not private.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  select * into _r from public.verification_requests where id = _request_id for update;
  if not found then raise exception 'request not found' using errcode = 'P0002'; end if;
  if not ((_r.status = 'pending' and _new_status in ('under_review','rejected'))
       or (_r.status = 'under_review' and _new_status in ('verified','rejected'))
       or (_r.status = 'verified' and _new_status = 'rejected')) then
    raise exception 'invalid transition % -> %', _r.status, _new_status;
  end if;
  if _new_status = 'under_review' and not exists
     (select 1 from public.verification_documents where request_id = _request_id) then
    raise exception 'no documents attached';
  end if;
  if _new_status = 'rejected' and coalesce(trim(_note), '') = '' then
    raise exception 'a note is required when rejecting';
  end if;
  select is_published into _was_published from public.provider_profiles
   where id = _r.provider_profile_id for update;
  update public.verification_requests
     set status = _new_status, reviewer_id = _uid, review_notes = _note,
         reviewed_at = case when _new_status in ('verified','rejected') then now() end
   where id = _request_id;
  update public.provider_profiles
     set verification_status = _new_status,
         verified_at = case when _new_status = 'verified' then now() end,
         is_published = case when _new_status = 'verified' then is_published else false end
   where id = _r.provider_profile_id;
  insert into public.verification_events(request_id, actor_id, from_status, to_status, note)
  values (_request_id, _uid, _r.status, _new_status, _note);
  perform public.write_audit('verification.' || _new_status::text, 'verification_request', _request_id, '{}');
  if _was_published and _new_status <> 'verified' then
    perform public.write_audit('provider.unpublished', 'provider_profile', _r.provider_profile_id,
      jsonb_build_object('reason', 'verification_' || _new_status::text));
  end if;
end $$;

-- 5. admin suspension (audited); suspended owners are hidden from public listings by the policy above
create function public.admin_set_suspension(_user_id uuid, _suspended boolean, _reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if _user_id = (select auth.uid()) then raise exception 'admins cannot change their own suspension'; end if;
  if _suspended and coalesce(trim(_reason), '') = '' then
    raise exception 'a reason is required when suspending';
  end if;
  update public.profiles set is_suspended = _suspended where id = _user_id;
  if not found then raise exception 'user not found' using errcode = 'P0002'; end if;
  perform public.write_audit(case when _suspended then 'user.suspended' else 'user.unsuspended' end,
    'user', _user_id, jsonb_build_object('reason', _reason));
end $$;
revoke execute on function public.admin_set_suspension(uuid, boolean, text) from public, anon;
grant execute on function public.admin_set_suspension(uuid, boolean, text) to authenticated;
