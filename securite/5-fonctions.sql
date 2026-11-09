-- ════════════════════════════════════════════════════════════════════
--  FONCTIONS DES MAILS : FERMÉES AUX PERSONNES NON CONNECTÉES — Gestion Collaborateurs
--  À lancer une fois dans Supabase → SQL Editor (projet jymobewqenhcjtzniytb).
--  Peut être relancé sans risque. Ne touche à aucune donnée ni aux tables.
--
--  Avant : n'importe qui sur Internet pouvait déclencher les envois de mails
--  ou lire les réglages (adresses IT, restaurant…) sans se connecter.
--  Après : seuls les comptes connectés et les envois automatiques (cron,
--  déclencheurs) peuvent les utiliser. L'appli continue de marcher pareil.
-- ════════════════════════════════════════════════════════════════════
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in
             ('envoyer_mails_auto','envoyer_relances_pret','envoyer_mails_depart','lp24_reglages',
              'lp24_texte','lp24_texte_defaut','lp24_remplir','mail_pret_accueil') loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
    raise notice 'Fonction % : fermée sans connexion', f.sig;
  end loop;
end $$;

-- Vérification : tout doit être « oui »
select p.proname || '()' as fonction,
       case when has_function_privilege('anon', p.oid, 'execute') then 'NON' else 'oui' end as "fermée sans connexion"
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in
  ('envoyer_mails_auto','envoyer_relances_pret','envoyer_mails_depart','lp24_reglages',
   'lp24_texte','lp24_texte_defaut','lp24_remplir','mail_pret_accueil')
order by 1;
