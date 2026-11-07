-- ════════════════════════════════════════════════════════════════════
--  SÉCURITÉ + RGPD — Gestion Collaborateurs
--  À lancer une fois dans Supabase → SQL Editor (tout le bloc d'un coup).
--  Peut être relancé sans risque. Aucune donnée n'est supprimée au lancement :
--  l'effacement des données de plus de 24 mois se fait ensuite chaque nuit.
--
--  1. Base fermée à toute personne non connectée (toutes les tables)
--  2. Fonctions internes (envois de mails, réglages) non appelables de l'extérieur
--  3. Seul un administrateur peut modifier la liste des comptes et des rôles
--  4. Effacement automatique des données de plus de 24 mois (chaque nuit, 3 h 30)
--  5. Droit à l'effacement : bouton dans la fiche pour effacer toutes les
--     données d'une personne (réservé aux administrateurs)
--  6. Espace photos rendu privé
-- ════════════════════════════════════════════════════════════════════

-- ── Outil : lire un champ JSON quel que soit son format (texte, jsonb, jsonb « chaîne »)
create or replace function public.lp24_json(x anyelement) returns jsonb
language plpgsql immutable as $f$
declare v jsonb;
begin
  begin v := to_jsonb(x); exception when others then return '{}'::jsonb; end;
  while v is not null and jsonb_typeof(v) = 'string' loop
    begin v := (v #>> '{}')::jsonb; exception when others then return '{}'::jsonb; end;
  end loop;
  return coalesce(v, '{}'::jsonb);
end $f$;

-- ── Qui fait la demande ? (vide = SQL Editor / tâches automatiques de Supabase)
create or replace function public.lp24_email_appelant() returns text
language sql stable as $f$
  select lower(coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', ''))
$f$;

-- ── Est-ce un administrateur de l'appli ? (même règle que l'appli)
create or replace function public.lp24_est_admin(users jsonb) returns boolean
language plpgsql stable as $f$
declare em text := public.lp24_email_appelant(); u jsonb := coalesce(users, '[]'::jsonb);
begin
  if current_setting('request.jwt.claims', true) is null or current_setting('request.jwt.claims', true) = '' then
    return true;                                   -- SQL Editor, cron, déclencheurs internes
  end if;
  if jsonb_typeof(u) <> 'array' then u := '[]'::jsonb; end if;
  if exists (select 1 from jsonb_array_elements(u) e where lower(trim(e->>'email')) = em and e->>'role' = 'admin') then
    return true;
  end if;
  -- tant qu'aucun administrateur n'est défini, le compte du responsable de site l'est (comme dans l'appli)
  return not exists (select 1 from jsonb_array_elements(u) e where e->>'role' = 'admin')
         and em = 'a.avonde@allianceautomotive.fr';
end $f$;

do $$
declare
  t text; p record; n int;
  internes text[] := array['lp24_mail_config','lp24_mails_auto','lp24_mails_depart','lp24_mails_pret','lp24_relances_pret'];
begin
  -- 1. Toutes les tables : RLS activée, aucun accès sans connexion
  for t in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind = 'r' loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    if t = any(internes) then
      for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
        execute format('drop policy %I on public.%I', p.policyname, t);
      end loop;
      execute format('revoke all on public.%I from authenticated', t);
    else
      select count(*) into n from pg_policies where schemaname = 'public' and tablename = t;
      if n = 0 then
        execute format('create policy "membres_connectes" on public.%I for all to authenticated using (true) with check (true)', t);
        execute format('grant select, insert, update, delete on public.%I to authenticated', t);
      end if;
    end if;
  end loop;
  execute 'grant usage, select on all sequences in schema public to authenticated';
  execute 'revoke all on all sequences in schema public from anon';
end $$;

-- 2. Fonctions : plus rien d'appelable sans connexion ; les fonctions internes
--    (envois de mails, réglages) ne sont appelables que par la base elle-même
revoke execute on all functions in schema public from public, anon;
alter default privileges in schema public revoke execute on functions from public, anon;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' loop
    if f.proname in ('lp24_compteur_mails','lp24_effacer_personne') then
      execute format('grant execute on function %s to authenticated', f.sig);
    elsif f.proname in ('envoyer_mails_auto','envoyer_relances_pret','envoyer_mails_depart','lp24_reglages',
                        'lp24_texte','lp24_texte_defaut','lp24_remplir','lp24_purge_rgpd') then
      execute format('revoke execute on function %s from authenticated', f.sig);
    else
      execute format('grant execute on function %s to authenticated', f.sig);   -- outils utilisés par les déclencheurs
    end if;
  end loop;
end $$;

-- 3. Comptes et rôles : seul un administrateur peut les modifier
create or replace function public.lp24_proteger_comptes() returns trigger
language plpgsql as $f$
declare avant jsonb; apres jsonb;
begin
  if tg_op = 'DELETE' then
    if old.id = 1 and not public.lp24_est_admin(public.lp24_json(old.data)->'users') then
      raise exception 'Seul un administrateur peut supprimer les réglages';
    end if;
    return old;
  end if;
  if new.id <> 1 then return new; end if;
  avant := case when tg_op = 'UPDATE' then public.lp24_json(old.data)->'users' else null end;
  apres := public.lp24_json(new.data)->'users';
  if coalesce(avant, '[]'::jsonb) is distinct from coalesce(apres, '[]'::jsonb)
     and not public.lp24_est_admin(avant) then
    raise exception 'Seul un administrateur peut modifier les comptes et les rôles';
  end if;
  return new;
end $f$;
drop trigger if exists lp24_proteger_comptes on public.lp24_settings;
create trigger lp24_proteger_comptes before insert or update or delete on public.lp24_settings
  for each row execute function public.lp24_proteger_comptes();

-- Le registre des colis remis reste protégé, sauf pour l'effacement RGPD
create or replace function public.lp24_colis_proteger() returns trigger
language plpgsql as $f$
begin
  if current_setting('lp24.purge', true) = 'oui' then return old; end if;
  if old.statut = 'recupere' or old.signature is not null then
    raise exception 'Colis remis : il est conservé pour l''historique et ne peut pas être supprimé';
  end if;
  return old;
end $f$;

-- 4. Effacement automatique : tout ce qui concerne une personne partie depuis plus de 24 mois
create or replace function public.lp24_purge_rgpd() returns jsonb
language plpgsql security definer set search_path = public as $f$
declare
  limite timestamptz := now() - interval '24 months';
  lim text := to_char(now() - interval '24 months', 'YYYY-MM-DD');
  r jsonb := '{}'::jsonb; n bigint; debut timestamptz := clock_timestamp();
  procedure_sql text;
begin
  perform set_config('lp24.purge', 'oui', true);
  -- fiches archivées depuis plus de 24 mois
  begin
  delete from public.lp24_badges
   where statut = 'Archivé'
     and left(coalesce(nullif(date_archive::text, ''), nullif(date_sortie_prevue::text, ''), '9999'), 10) ~ '^\d{4}-\d{2}-\d{2}$'
     and left(coalesce(nullif(date_archive::text, ''), nullif(date_sortie_prevue::text, '')), 10) < lim;
  get diagnostics n = row_count; r := r || jsonb_build_object('fiches', n);
  exception when others then raise notice 'Fiches ignorées : %', sqlerrm;
  end;
  -- colis remis depuis plus de 24 mois (avec leur signature)
  if to_regclass('public.lp24_colis') is not null then
    delete from public.lp24_colis where statut = 'recupere' and coalesce(recupere_le, recu_le) < limite;
    get diagnostics n = row_count; r := r || jsonb_build_object('colis', n);
  end if;
  -- historiques et journaux de plus de 24 mois (et lignes créées par cet effacement)
  foreach procedure_sql in array array[
    'delete from public.lp24_colis_journal where le < $1 or le >= $2',
    'delete from public.lp24_casiers_journal where le < $1 or le >= $2',
    'delete from public.badges_pret_histo where ts::timestamptz < $1',
    'delete from public.historique where ts::timestamptz < $1',
    'delete from public.lp24_mails_auto where envoye_le < $1',
    'delete from public.lp24_mails_pret where envoye_le < $1',
    'delete from public.lp24_relances_pret where jour < $1::date',
    'delete from public.lp24_mails_depart where envoye_le < $1',
    'delete from public.lp24_mails_appli where envoye_le < $1'] loop
    begin
      execute procedure_sql using limite, debut;
      get diagnostics n = row_count;
      r := r || jsonb_build_object(split_part(split_part(procedure_sql, 'public.', 2), ' ', 1), n);
    exception when others then raise notice 'Effacement ignoré (%): %', sqlerrm, procedure_sql;
    end;
  end loop;
  -- demandes Field Support clôturées depuis plus de 24 mois
  begin
    execute $q$delete from public.lp24_fss where coalesce(cloture, false)
             and left(coalesce(nullif("dateEvt"::text, ''), '9999'), 10) ~ '^\d{4}-\d{2}-\d{2}$'
             and left("dateEvt"::text, 10) < $1$q$ using lim;
    get diagnostics n = row_count; r := r || jsonb_build_object('field_support', n);
  exception when others then raise notice 'Field Support ignoré : %', sqlerrm;
  end;
  return r;
end $f$;
revoke execute on function public.lp24_purge_rgpd() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'lp24-purge-rgpd') then
      perform cron.unschedule('lp24-purge-rgpd');
    end if;
    perform cron.schedule('lp24-purge-rgpd', '30 2 * * *', 'select public.lp24_purge_rgpd()');
  else
    raise notice 'pg_cron absent : effacement automatique non programmé';
  end if;
end $$;

-- 5. Droit à l'effacement : toutes les données d'une personne (administrateurs seulement)
create or replace function public.lp24_effacer_personne(p_nom text, p_prenom text, p_email text default '')
returns jsonb language plpgsql security definer set search_path = public as $f$
declare
  nm text := upper(trim(coalesce(p_nom, ''))); pr text := lower(trim(coalesce(p_prenom, '')));
  em text := lower(trim(coalesce(p_email, '')));
  r jsonb := '{}'::jsonb; n bigint; debut timestamptz := clock_timestamp(); q text;
begin
  if not public.lp24_est_admin(public.lp24_reglages()->'users') then
    raise exception 'Réservé aux administrateurs';
  end if;
  if nm = '' or pr = '' then raise exception 'Nom et prénom obligatoires'; end if;
  perform set_config('lp24.purge', 'oui', true);
  delete from public.lp24_badges where upper(trim(nom)) = nm and lower(trim(prenom)) = pr;
  get diagnostics n = row_count; r := r || jsonb_build_object('fiches', n);
  foreach q in array array[
    'delete from public.lp24_colis where (upper(trim(nom)) = $1 and lower(trim(prenom)) = $2) or ($3 <> '''' and lower(trim(email)) = $3)',
    'delete from public.lp24_fss where upper(trim(nom)) = $1 and lower(trim(prenom)) = $2',
    'delete from public.badges_pret_histo where upper(emprunteur) like ''%''||$1||''%'' and lower(emprunteur) like ''%''||$2||''%''',
    'update public.badges_pret set emprunteur = '''', email_emprunteur = '''' where statut = ''disponible'' and ((upper(emprunteur) like ''%''||$1||''%'' and lower(emprunteur) like ''%''||$2||''%'') or ($3 <> '''' and lower(email_emprunteur) = $3))',
    'delete from public.lp24_casiers_journal where upper(personne) like ''%''||$1||''%'' and lower(personne) like ''%''||$2||''%''',
    'delete from public.historique where upper(detail) like ''%''||$1||''%'' and lower(detail) like ''%''||$2||''%''',
    'delete from public.lp24_mails_auto where (upper(trim(nom)) = $1 and lower(trim(prenom)) = $2)',
    'delete from public.lp24_mails_pret where $3 <> '''' and lower(destinataire) = $3',
    'delete from public.lp24_relances_pret where $3 <> '''' and lower(destinataire) = $3',
    'delete from public.lp24_mails_appli where $3 <> '''' and lower(destinataire) = $3',
    'update public.lp24_casiers set occupant = '''', statut = ''Libre'' where upper(occupant) like ''%''||$1||''%'' and lower(occupant) like ''%''||$2||''%'''] loop
    begin
      execute q using nm, pr, em;
      get diagnostics n = row_count;
      r := r || jsonb_build_object(split_part(split_part(q, 'public.', 2), ' ', 1), n);
    exception when undefined_table or undefined_column then null;
    end;
  end loop;
  -- lignes de journal créées par cet effacement : elles contiennent encore le nom
  begin execute 'delete from public.lp24_colis_journal where le >= $1' using debut; exception when undefined_table then null; end;
  begin execute 'delete from public.lp24_casiers_journal where le >= $1' using debut; exception when undefined_table then null; end;
  return r;
end $f$;
revoke execute on function public.lp24_effacer_personne(text, text, text) from public, anon;
grant execute on function public.lp24_effacer_personne(text, text, text) to authenticated;

-- 6. Espace photos : plus accessible par simple lien
do $$
begin
  if to_regclass('storage.buckets') is not null then
    update storage.buckets set public = false where id = 'photos';
  end if;
end $$;

select 'Installé' as resultat;
