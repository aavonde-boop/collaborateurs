-- ════════════════════════════════════════════════════════════════════
--  HISTORIQUE DES CASIERS
--  À lancer une fois dans Supabase → SQL Editor.
--  Chaque attribution, retrait, changement de statut, création ou
--  suppression de casier est noté (date, personne concernée, auteur).
--  Le journal ne peut être ni modifié ni effacé depuis l'appli.
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.lp24_casiers_journal(
  id bigserial primary key,
  casier text,            -- numéro normalisé (PA210)
  numero text,            -- numéro tel qu'écrit
  action text,
  personne text,
  par text,
  le timestamptz not null default now()
);
create index if not exists lp24_casiers_journal_casier on public.lp24_casiers_journal(casier, le);
alter table public.lp24_casiers_journal enable row level security;
drop policy if exists "lecture_connectes" on public.lp24_casiers_journal;
create policy "lecture_connectes" on public.lp24_casiers_journal for select to authenticated using (true);
revoke all on public.lp24_casiers_journal from anon;
revoke insert, update, delete on public.lp24_casiers_journal from authenticated;
grant select on public.lp24_casiers_journal to authenticated;

-- « PA 210 », « pa-0210 » → PA210 (même règle que l'appli)
create or replace function public.lp24_cle_casier(v text) returns text
language sql immutable as $k$
  select case when s ~ '^[A-Z]+0*[0-9]+$' then regexp_replace(s, '^([A-Z]+)0*([0-9]+)$', '\1\2') else s end
  from (select upper(regexp_replace(coalesce(v, ''), '[^A-Za-z0-9]', '', 'g')) as s) x
$k$;

create or replace function public.lp24_auteur() returns text
language sql stable as $a$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', 'système')
$a$;

-- Attributions : suivies sur la fiche du collaborateur (champ casier)
create or replace function public.lp24_casiers_suivi_fiche() returns trigger
language plpgsql security definer set search_path = public as $f$
declare
  ka text := case when tg_op in ('UPDATE','DELETE') then public.lp24_cle_casier(old.casier) else '' end;
  kn text := case when tg_op in ('UPDATE','INSERT') then public.lp24_cle_casier(new.casier) else '' end;
  qui text;
begin
  if tg_op = 'UPDATE' and ka = kn then
    if ka <> '' and new.statut = 'Archivé' and old.statut is distinct from 'Archivé' then
      insert into public.lp24_casiers_journal(casier, numero, action, personne, par)
      values (ka, old.casier, 'Collaborateur archivé (casier à vider)', initcap(coalesce(old.prenom,'')) || ' ' || upper(coalesce(old.nom,'')), public.lp24_auteur());
    end if;
    return new;
  end if;
  if ka <> '' then
    insert into public.lp24_casiers_journal(casier, numero, action, personne, par)
    values (ka, old.casier, case when tg_op = 'DELETE' then 'Fiche supprimée' else 'Retiré' end,
            initcap(coalesce(old.prenom,'')) || ' ' || upper(coalesce(old.nom,'')), public.lp24_auteur());
  end if;
  if kn <> '' then
    insert into public.lp24_casiers_journal(casier, numero, action, personne, par)
    values (kn, new.casier, 'Attribué', initcap(coalesce(new.prenom,'')) || ' ' || upper(coalesce(new.nom,'')), public.lp24_auteur());
  end if;
  return coalesce(new, old);
end $f$;
drop trigger if exists lp24_casiers_suivi_fiche on public.lp24_badges;
create trigger lp24_casiers_suivi_fiche after insert or update of casier, statut or delete on public.lp24_badges
  for each row execute function public.lp24_casiers_suivi_fiche();

-- Inventaire : création, suppression, statut, casier vidé
create or replace function public.lp24_casiers_suivi_inventaire() returns trigger
language plpgsql security definer set search_path = public as $f$
declare act text; pers text;
begin
  if tg_op = 'INSERT' then act := 'Casier créé' || coalesce(' (' || nullif(new.statut,'') || ')', '');
  elsif tg_op = 'DELETE' then act := 'Casier supprimé'; pers := nullif(old.occupant,'');
  else
    if new.statut is not distinct from old.statut and coalesce(new.occupant,'') = coalesce(old.occupant,'') then return new; end if;
    if new.statut = 'Occupé' and coalesce(new.occupant,'') <> '' then return new; end if;  -- attribution : déjà notée par la fiche
    if coalesce(old.occupant,'') <> '' and coalesce(new.occupant,'') = '' and new.statut = 'Libre' then act := 'Vidé'; pers := old.occupant;
    elsif new.statut = 'Occupé' then act := 'Occupé (sans nom)';
    else act := 'Statut : ' || coalesce(new.statut,'—');
    end if;
  end if;
  insert into public.lp24_casiers_journal(casier, numero, action, personne, par)
  values (public.lp24_cle_casier(coalesce(new.numero, old.numero)), coalesce(new.numero, old.numero), act, pers, public.lp24_auteur());
  return coalesce(new, old);
end $f$;
drop trigger if exists lp24_casiers_suivi_inventaire on public.lp24_casiers;
create trigger lp24_casiers_suivi_inventaire after insert or update or delete on public.lp24_casiers
  for each row execute function public.lp24_casiers_suivi_inventaire();

-- Vérification : doit afficher 2
select count(*) as suivis_actifs from pg_trigger where tgname in ('lp24_casiers_suivi_fiche','lp24_casiers_suivi_inventaire');
