-- ════════════════════════════════════════════════════════════════════
--  PHOTO DES COLLABORATEURS + SIGNATURE À LA REMISE DES COLIS
--  À lancer une fois dans Supabase → SQL Editor.
-- ════════════════════════════════════════════════════════════════════
alter table public.lp24_badges add column if not exists photo text;
alter table public.lp24_colis  add column if not exists signature text;
alter table public.lp24_colis  add column if not exists signe_le timestamptz;

-- Dossier « photos » (lisible par lien, pour pouvoir afficher la photo dans le mail de bienvenue)
insert into storage.buckets (id, name, public) values ('photos', 'photos', true)
  on conflict (id) do update set public = true;
drop policy if exists "photos_ajout"  on storage.objects;
drop policy if exists "photos_modif"  on storage.objects;
drop policy if exists "photos_suppr"  on storage.objects;
create policy "photos_ajout" on storage.objects for insert to authenticated with check (bucket_id = 'photos');
create policy "photos_modif" on storage.objects for update to authenticated using (bucket_id = 'photos');
create policy "photos_suppr" on storage.objects for delete to authenticated using (bucket_id = 'photos');

-- Vérification : doit afficher « photos | true »
select id, public from storage.buckets where id = 'photos';
