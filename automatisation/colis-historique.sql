-- ════════════════════════════════════════════════════════════════════
--  COLIS : HISTORIQUE COMPLET + SIGNATURES CONSERVÉES
--  À lancer une fois dans Supabase → SQL Editor (après photos-signature.sql).
--  • Chaque création / modification / suppression d'un colis est copiée
--    dans lp24_colis_journal (avec la date et l'auteur). Rien ne s'y efface.
--  • Un colis remis (récupéré ou signé) ne peut plus être supprimé.
-- ════════════════════════════════════════════════════════════════════
alter table public.lp24_colis add column if not exists signature text;
alter table public.lp24_colis add column if not exists signe_le timestamptz;

create table if not exists public.lp24_colis_journal(
  id bigserial primary key,
  colis_id bigint,
  numero int,
  action text,
  avant jsonb,
  apres jsonb,
  par text,
  le timestamptz not null default now()
);
alter table public.lp24_colis_journal enable row level security;
drop policy if exists "lecture_connectes" on public.lp24_colis_journal;
create policy "lecture_connectes" on public.lp24_colis_journal for select to authenticated using (true);
revoke all on public.lp24_colis_journal from anon;
revoke insert, update, delete on public.lp24_colis_journal from authenticated;
grant select on public.lp24_colis_journal to authenticated;

create or replace function public.lp24_colis_journaliser() returns trigger
language plpgsql security definer set search_path = public as $f$
declare
  qui text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', 'système');
  act text;
begin
  if tg_op = 'INSERT' then act := 'Reçu';
  elsif tg_op = 'DELETE' then act := 'Supprimé';
  elsif new.statut is distinct from old.statut then
    act := case new.statut when 'prevenu' then 'Prévenu' when 'recupere' then 'Récupéré' when 'recu' then 'Remis à « à prévenir »' else new.statut end;
  else act := 'Modifié';
  end if;
  if tg_op <> 'DELETE' and new.signature is not null and (tg_op = 'INSERT' or old.signature is null) then act := act || ' · signé'; end if;
  insert into public.lp24_colis_journal(colis_id, numero, action, avant, apres, par)
  values (coalesce(new.id, old.id), coalesce(new.numero, old.numero), act,
          case when tg_op = 'INSERT' then null else to_jsonb(old) end,
          case when tg_op = 'DELETE' then null else to_jsonb(new) end, qui);
  return coalesce(new, old);
end $f$;
drop trigger if exists lp24_colis_journal on public.lp24_colis;
create trigger lp24_colis_journal after insert or update or delete on public.lp24_colis
  for each row execute function public.lp24_colis_journaliser();

-- Un colis remis ne peut plus être supprimé (sa signature reste conservée)
create or replace function public.lp24_colis_proteger() returns trigger
language plpgsql as $f$
begin
  if old.statut = 'recupere' or old.signature is not null then
    raise exception 'Colis remis : il est conservé pour l''historique et ne peut pas être supprimé';
  end if;
  return old;
end $f$;
drop trigger if exists lp24_colis_proteger on public.lp24_colis;
create trigger lp24_colis_proteger before delete on public.lp24_colis
  for each row execute function public.lp24_colis_proteger();

-- Les signatures ne peuvent pas être effacées ni remplacées une fois posées
create or replace function public.lp24_colis_signature_figee() returns trigger
language plpgsql as $f$
begin
  if old.signature is not null and new.signature is distinct from old.signature then
    new.signature := old.signature; new.signe_le := old.signe_le;
  end if;
  return new;
end $f$;
drop trigger if exists lp24_colis_signature_figee on public.lp24_colis;
create trigger lp24_colis_signature_figee before update on public.lp24_colis
  for each row execute function public.lp24_colis_signature_figee();

-- Vérification : doit afficher 3
select count(*) as protections from pg_trigger where tgname in ('lp24_colis_journal','lp24_colis_proteger','lp24_colis_signature_figee');
