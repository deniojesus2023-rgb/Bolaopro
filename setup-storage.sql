-- ================================================================
-- BolãoPro — Setup Storage: Bucket de Avatars
-- Cole no SQL Editor do Supabase e clique em RUN
-- ================================================================

-- 1. Criar bucket 'avatars' (público para leitura)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  2097152,  -- 2MB máximo
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict (id) do update set
  public = true,
  file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

-- 2. RLS: qualquer um pode VER os avatars (bucket é público)
drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- 3. RLS: usuário autenticado pode FAZER UPLOAD no próprio folder
drop policy if exists "avatars_user_upload" on storage.objects;
create policy "avatars_user_upload"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- 4. RLS: usuário pode ATUALIZAR própria foto
drop policy if exists "avatars_user_update" on storage.objects;
create policy "avatars_user_update"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- 5. RLS: usuário pode DELETAR própria foto
drop policy if exists "avatars_user_delete" on storage.objects;
create policy "avatars_user_delete"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Verificar
select id, name, public from storage.buckets where id = 'avatars';
