-- ════════════════════════════════════════════════════════════════════
--  VÉRIFICATION SÉCURITÉ — Gestion Collaborateurs (lecture seule)
--  À lancer dans Supabase → SQL Editor. Ne modifie RIEN : affiche l'état.
--  Une ligne par point contrôlé ; la colonne « ok » doit valoir « oui ».
-- ════════════════════════════════════════════════════════════════════
with tables as (
  select c.relname as nom, c.oid, c.relrowsecurity as rls
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
), fonctions as (
  select p.proname as nom, p.oid
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in
    ('envoyer_mails_auto','envoyer_relances_pret','envoyer_mails_depart','lp24_reglages','lp24_texte','lp24_texte_defaut','lp24_remplir','mail_pret_accueil')
)
select 'Table ' || nom as point,
       case when rls then 'verrouillée' else 'NON verrouillée' end
         || ' · ' || case when has_table_privilege('anon', oid, 'select') then 'lisible SANS connexion' else 'fermée sans connexion' end as etat,
       case when rls and not has_table_privilege('anon', oid, 'select') then 'oui' else 'NON' end as ok
from tables
union all
select 'Fonction ' || nom || '()',
       case when has_function_privilege('anon', oid, 'execute') then 'appelable SANS connexion' else 'fermée sans connexion' end,
       case when has_function_privilege('anon', oid, 'execute') then 'NON' else 'oui' end
from fonctions
union all
select 'Création de compte limitée aux adresses autorisées',
       case when exists (select 1 from pg_trigger where tgname = 'lp24_inscription_autorisee') then 'active' else 'absente' end,
       case when exists (select 1 from pg_trigger where tgname = 'lp24_inscription_autorisee') then 'oui' else 'NON' end
order by 3, 1;
