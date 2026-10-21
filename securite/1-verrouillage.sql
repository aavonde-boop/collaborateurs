-- ════════════════════════════════════════════════════════════════════
--  VERROUILLAGE DE LA BASE — Gestion Collaborateurs (version du 21/10)
--  À lancer dans Supabase → SQL Editor (tout le bloc d'un coup).
--
--  Effet :
--   • Tables de l'appli : seules les personnes connectées avec leur
--     e-mail et mot de passe peuvent lire ou modifier les données.
--   • Tables internes des mails (dont la clé EmailJS) : plus aucun accès
--     depuis l'appli ou Internet ; seuls les envois automatiques
--     (cron, déclencheurs) y ont accès.
--  Aucune donnée n'est modifiée ni supprimée.
--  En cas de souci : lancer 2-annulation.sql.
-- ════════════════════════════════════════════════════════════════════
do $$
declare
  t text;
  p record;
  appli text[] := array['lp24_badges','lp24_casiers','lp24_fss','lp24_settings',
                        'historique','badges_pret','badges_pret_histo','lp24_colis'];
  internes text[] := array['lp24_mail_config','lp24_mails_auto','lp24_mails_depart',
                           'lp24_mails_pret','lp24_relances_pret'];
begin
  -- 1. Tables de l'appli : réservées aux comptes connectés
  foreach t in array appli loop
    if to_regclass('public.'||t) is null then raise notice 'Table % absente, ignorée', t; continue; end if;
    for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "membres_connectes" on public.%I for all to authenticated using (true) with check (true)', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    raise notice 'Table % : réservée aux comptes connectés', t;
  end loop;
  -- 2. Tables internes des mails : aucun accès depuis l'extérieur
  foreach t in array internes loop
    if to_regclass('public.'||t) is null then raise notice 'Table % absente, ignorée', t; continue; end if;
    for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    raise notice 'Table % : interne, fermée', t;
  end loop;
  -- 3. Séquences (numéros automatiques) utilisables par les comptes connectés seulement
  execute 'grant usage, select on all sequences in schema public to authenticated';
end $$;

-- Vérification : une ligne par table, tout doit être « oui »
select c.relname as "table",
       case when c.relrowsecurity then 'oui' else 'NON' end as "verrouillée",
       case when has_table_privilege('anon', c.oid, 'select') then 'NON' else 'oui' end as "fermée aux non-connectés"
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relname in
  ('lp24_badges','lp24_casiers','lp24_fss','lp24_settings','historique','badges_pret','badges_pret_histo','lp24_colis',
   'lp24_mail_config','lp24_mails_auto','lp24_mails_depart','lp24_mails_pret','lp24_relances_pret')
order by 1;
