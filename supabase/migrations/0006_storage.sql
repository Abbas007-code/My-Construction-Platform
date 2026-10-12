-- 0006_storage.sql  [Written, untested]  Requires Supabase's `storage` schema.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('verification-docs', 'verification-docs', false, 5242880, array['image/jpeg','image/png','application/pdf']),
  ('public-media',      'public-media',      true,  2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- private identity documents: path must be {auth.uid()}/...; owner and admins only
create policy verification_docs_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'verification-docs'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy verification_docs_select on storage.objects for select to authenticated
  using (bucket_id = 'verification-docs'
         and ((storage.foldername(name))[1] = (select auth.uid())::text or (select private.is_admin())));
-- intentionally NO update/delete policy for users: submitted evidence is immutable

-- public media: anyone reads, users manage only their own folder
create policy public_media_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'public-media');
create policy public_media_write_own on storage.objects for insert to authenticated
  with check (bucket_id = 'public-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy public_media_update_own on storage.objects for update to authenticated
  using (bucket_id = 'public-media' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'public-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy public_media_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'public-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
