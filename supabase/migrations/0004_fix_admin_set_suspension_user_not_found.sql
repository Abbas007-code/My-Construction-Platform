-- 0004_fix_admin_set_suspension_user_not_found
-- Applied to project trjrkzkpdilgyfuogfba as remote migration "fix_admin_set_suspension_user_not_found".
-- Fix: FOUND was overwritten by the PERFORM set_config that followed the UPDATE, so "user not found" never fired.
create or replace function public.admin_set_suspension(_user_id uuid, _suspended boolean, _reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare _n bigint;
begin
  if not private.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if _user_id = (select auth.uid()) then raise exception 'admins cannot change their own suspension'; end if;
  if _suspended and coalesce(trim(_reason), '') = '' then
    raise exception 'a reason is required when suspending';
  end if;
  perform set_config('app.audit_note', coalesce(_reason, ''), true);
  update public.profiles set is_suspended = _suspended where id = _user_id;   -- audited + unpublish by trigger
  get diagnostics _n = row_count;
  perform set_config('app.audit_note', '', true);
  if _n = 0 then raise exception 'user not found' using errcode = 'P0002'; end if;
end $$;
