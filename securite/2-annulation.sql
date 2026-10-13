-- ════════════════════════════════════════════════════════════════════
--  ANNULATION DU VERROUILLAGE — Gestion Collaborateurs
--  À lancer dans Supabase → SQL Editor si l'appli ne fonctionne plus
--  après le verrouillage. Remet l'accès comme avant (ouvert).
--  Aucune donnée n'est modifiée ni supprimée par ce script.
-- ════════════════════════════════════════════════════════════════════
do $$
declare
  t text;
  tables text[] := array['lp24_badges','lp24_casiers','lp24_fss','lp24_settings',
                         'historique','badges_pret','badges_pret_histo'];
begin
  foreach t in array tables loop
    if to_regclass('public.'||t) is null then continue; end if;
    execute format('drop policy if exists "membres_connectes" on public.%I', t);
    execute format('alter table public.%I disable row level security', t);
    raise notice 'Table % rouverte', t;
  end loop;
end $$;
