-- 0003_audit_coverage_and_helper_hardening
-- Applied to project trjrkzkpdilgyfuogfba as remote migration "audit_coverage_and_helper_hardening".
-- 1) least-privilege for anon / helpers, 2) audit coverage via triggers (single emitter, no duplicates),
-- 3) suspension unpublishes atomically; unsuspension never publishes.

-- ============ 1. privileges ============
-- Anonymous-applicable policy must not call has_role/is_admin (anon will lose EXECUTE on them).
drop policy provider_select on public.provider_profiles;
create policy provider_select_public on public.provider_profiles for select to anon, authenticated
  using (is_published and verification_status = 'verified' and not private.is_suspended(user_id));
create policy provider_select_own on public.provider_profiles for select to authenticated
  using (user_id = (select auth.uid()));
create policy provider_select_admin on public.provider_profiles for select to authenticated
  using ((select private.is_admin()));

revoke execute on function private.has_role(public.app_role) from anon;
revoke execute on function private.is_admin() from anon;

-- table privileges: anon is read-only on public reference/listing tables only
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
revoke insert, update, delete on all tables in schema public from anon;
revoke all on public.profiles, public.user_roles, public.audit_logs,
              public.verification_requests, public.verification_documents, public.verification_events from anon;

-- ============ 2. audit triggers (single emitter per event) ============
create function public.audit_provider_changes() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  _req uuid; _action text; _reason text;
  _note text := nullif(current_setting('app.audit_note', true), '');
begin
  if tg_op = 'INSERT' then
    if new.verification_status <> 'unsubmitted' then
      _action := case when new.verification_status = 'pending' then 'verification.submitted'
                      else 'verification.' || new.verification_status::text end;
      perform public.write_audit(_action, 'provider_profile', new.id,
        jsonb_build_object('from', null::text, 'to', new.verification_status, 'request_id', null::uuid, 'note', _note));
    end if;
    if new.is_published then
      perform public.write_audit('provider.published', 'provider_profile', new.id, '{}'::jsonb);
    end if;
    return null;
  end if;

  if new.verification_status is distinct from old.verification_status then
    select id into _req from public.verification_requests
     where provider_profile_id = new.id and status = new.verification_status
     order by coalesce(reviewed_at, submitted_at) desc limit 1;
    _action := case when new.verification_status = 'pending' then 'verification.submitted'
                    else 'verification.' || new.verification_status::text end;
    perform public.write_audit(_action, 'provider_profile', new.id,
      jsonb_build_object('from', old.verification_status, 'to', new.verification_status,
                         'request_id', _req, 'note', _note));
  end if;

  if new.is_published is distinct from old.is_published then
    if new.is_published then
      perform public.write_audit('provider.published', 'provider_profile', new.id, '{}'::jsonb);
    else
      _reason := case
        when new.verification_status is distinct from old.verification_status then 'verification_' || new.verification_status::text
        when coalesce((select is_suspended from public.profiles where id = new.user_id), false) then 'owner_suspended'
        else 'unpublished' end;
      perform public.write_audit('provider.unpublished', 'provider_profile', new.id, jsonb_build_object('reason', _reason));
    end if;
  end if;
  return null;
end $$;
revoke execute on function public.audit_provider_changes() from public, anon, authenticated;

create trigger provider_profiles_audit_ins after insert on public.provider_profiles
  for each row execute function public.audit_provider_changes();
create trigger provider_profiles_audit_upd after update on public.provider_profiles
  for each row when (old.verification_status is distinct from new.verification_status
                     or old.is_published is distinct from new.is_published)
  execute function public.audit_provider_changes();

-- suspension: audit + atomic unpublish (unsuspension never publishes anything)
create function public.on_profile_suspension_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.write_audit(case when new.is_suspended then 'user.suspended' else 'user.unsuspended' end,
    'user', new.id, jsonb_build_object('reason', nullif(current_setting('app.audit_note', true), '')));
  if new.is_suspended then
    update public.provider_profiles set is_published = false where user_id = new.id and is_published;
  end if;
  return null;
end $$;
revoke execute on function public.on_profile_suspension_change() from public, anon, authenticated;
create trigger profiles_suspension_sync after update of is_suspended on public.profiles
  for each row when (old.is_suspended is distinct from new.is_suspended)
  execute function public.on_profile_suspension_change();

-- role grants/revocations
create function public.audit_role_changes() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.write_audit('role.granted', 'user', new.user_id,
      jsonb_build_object('role', new.role, 'granted_by', new.granted_by));
  else
    perform public.write_audit('role.revoked', 'user', old.user_id, jsonb_build_object('role', old.role));
  end if;
  return null;
end $$;
revoke execute on function public.audit_role_changes() from public, anon, authenticated;
create trigger user_roles_audit after insert or delete on public.user_roles
  for each row execute function public.audit_role_changes();

-- publish guard: definer + row lock on the owner's profile so publish vs suspend cannot race
create or replace function public.enforce_publish_rules() returns trigger
language plpgsql security definer set search_path = '' as $$
declare _susp boolean;
begin
  if new.is_published then
    if tg_op = 'INSERT' or not old.is_published then
      if new.verification_status <> 'verified' then
        raise exception 'only verified providers can be published' using errcode = '23514';
      end if;
      select is_suspended into _susp from public.profiles where id = new.user_id for share;
      if coalesce(_susp, false) then
        raise exception 'suspended accounts cannot be published' using errcode = '42501';
      end if;
    elsif new.verification_status <> 'verified' then
      new.is_published := false;
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.enforce_publish_rules() from public, anon, authenticated;

-- ============ 3. RPCs: remove audit calls now emitted by triggers; pass note via txn-local setting ============
create or replace function public.choose_role(_role public.app_role) returns void
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
  on conflict do nothing;                              -- audited by user_roles_audit trigger
end $$;

create or replace function public.submit_verification(_provider_profile_id uuid) returns uuid
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
  update public.provider_profiles set verification_status = 'pending' where id = _p.id;   -- audited by trigger
  insert into public.verification_events(request_id, actor_id, from_status, to_status)
  values (_rid, _uid, _p.verification_status, 'pending');
  return _rid;
end $$;

create or replace function public.admin_review_verification(
  _request_id uuid, _new_status public.verification_status, _note text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  _uid uuid := (select auth.uid());
  _r public.verification_requests;
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
  perform 1 from public.provider_profiles where id = _r.provider_profile_id for update;
  perform set_config('app.audit_note', coalesce(_note, ''), true);
  update public.verification_requests
     set status = _new_status, reviewer_id = _uid, review_notes = _note,
         reviewed_at = case when _new_status in ('verified','rejected') then now() end
   where id = _request_id;
  update public.provider_profiles                      -- verification + unpublish audited by trigger
     set verification_status = _new_status,
         verified_at = case when _new_status = 'verified' then now() end,
         is_published = case when _new_status = 'verified' then is_published else false end
   where id = _r.provider_profile_id;
  insert into public.verification_events(request_id, actor_id, from_status, to_status, note)
  values (_request_id, _uid, _r.status, _new_status, _note);
  perform set_config('app.audit_note', '', true);
end $$;

create or replace function public.admin_set_suspension(_user_id uuid, _suspended boolean, _reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if _user_id = (select auth.uid()) then raise exception 'admins cannot change their own suspension'; end if;
  if _suspended and coalesce(trim(_reason), '') = '' then
    raise exception 'a reason is required when suspending';
  end if;
  perform set_config('app.audit_note', coalesce(_reason, ''), true);
  update public.profiles set is_suspended = _suspended where id = _user_id;   -- audited + unpublish by trigger
  perform set_config('app.audit_note', '', true);
  if not found then raise exception 'user not found' using errcode = 'P0002'; end if;
end $$;
