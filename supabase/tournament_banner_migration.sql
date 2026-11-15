-- BFB X Tracker: dashboard tournament banner support
-- Run once in Supabase SQL Editor.

alter table public.tournaments
  add column if not exists banner_image_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('tournament-banners', 'tournament-banners', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = true,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "Public can view tournament banners" on storage.objects;
create policy "Public can view tournament banners"
on storage.objects for select
using (bucket_id = 'tournament-banners');

drop policy if exists "Admins can upload tournament banners" on storage.objects;
create policy "Admins can upload tournament banners"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'tournament-banners'
  and exists (select 1 from public.admin_users au where au.user_id = auth.uid())
);

drop policy if exists "Admins can update tournament banners" on storage.objects;
create policy "Admins can update tournament banners"
on storage.objects for update to authenticated
using (
  bucket_id = 'tournament-banners'
  and exists (select 1 from public.admin_users au where au.user_id = auth.uid())
)
with check (
  bucket_id = 'tournament-banners'
  and exists (select 1 from public.admin_users au where au.user_id = auth.uid())
);

drop policy if exists "Admins can delete tournament banners" on storage.objects;
create policy "Admins can delete tournament banners"
on storage.objects for delete to authenticated
using (
  bucket_id = 'tournament-banners'
  and exists (select 1 from public.admin_users au where au.user_id = auth.uid())
);
