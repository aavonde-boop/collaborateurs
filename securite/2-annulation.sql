-- ════════════════════════════════════════════════════════════════════
--  ANNULATION DU VERROUILLAGE — Gestion Collaborateurs (version du 21/10)
--  À lancer dans Supabase → SQL Editor si l'appli ne fonctionne plus
--  après le verrouillage. Remet les tables de l'appli ouvertes comme avant.
--  Aucune donnée n'est modifiée ni supprimée.
-- ════════════════════════════════════════════════════════════════════
do $$
declare
  t text;
  appli text[] := array['lp24_badges','lp24_casiers','lp24_fss','lp24_settings',
                        'historique','badges_pret','badges_pret_histo','lp24_colis'];
begin
  foreach t in array appli loop
    if to_regclass('public.'||t) is null then continue; end if;
    execute format('drop policy if exists "membres_connectes" on public.%I', t);
    execute format('alter table public.%I disable row level security', t);
    execute format('grant select, insert, update, delete on public.%I to anon, authenticated', t);
    raise notice 'Table % rouverte', t;
  end loop;
  execute 'grant usage, select on all sequences in schema public to anon, authenticated';
end $$;
