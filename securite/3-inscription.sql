-- ════════════════════════════════════════════════════════════════════
--  CRÉATION DE COMPTE PAR LA PERSONNE ELLE-MÊME — Gestion Collaborateurs
--  À lancer une fois dans Supabase → SQL Editor.
--  Seules les adresses ajoutées dans l'appli (Réglages → Comptes) peuvent
--  créer un compte. Toute autre adresse est refusée par la base.
-- ════════════════════════════════════════════════════════════════════
create or replace function public.lp24_inscription_autorisee() returns trigger
language plpgsql security definer set search_path = public as $f$
declare
  u jsonb;
begin
  u := coalesce(public.lp24_reglages()->'users', '[]'::jsonb);
  if jsonb_typeof(u) <> 'array' or not exists (
       select 1 from jsonb_array_elements(u) e
       where lower(trim(e->>'email')) = lower(trim(new.email))) then
    raise exception 'Adresse non autorisée : ajoutez-la dans Réglages → Comptes';
  end if;
  return new;
end $f$;

drop trigger if exists lp24_inscription_autorisee on auth.users;
create trigger lp24_inscription_autorisee before insert on auth.users
  for each row execute function public.lp24_inscription_autorisee();

-- Vérification : doit afficher 1
select count(*) as protection_active from pg_trigger where tgname = 'lp24_inscription_autorisee';
