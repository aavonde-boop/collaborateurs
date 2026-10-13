-- ════════════════════════════════════════════════════════════════════
--  VERROUILLAGE DE LA BASE — Gestion Collaborateurs
--  À lancer dans Supabase → SQL Editor, UNIQUEMENT après la bascule du
--  site sur la connexion par compte.
--
--  Effet : seules les personnes connectées avec un compte (créé dans
--  Authentication → Users) peuvent lire ou modifier les données.
--  Aucune donnée n'est modifiée ni supprimée par ce script.
-- ════════════════════════════════════════════════════════════════════
do $$
declare
  t text;
  p record;
  tables text[] := array['lp24_badges','lp24_casiers','lp24_fss','lp24_settings',
                         'historique','badges_pret','badges_pret_histo'];
begin
  foreach t in array tables loop
    if to_regclass('public.'||t) is null then
      raise notice 'Table % absente, ignorée', t;
      continue;
    end if;
    -- 1. On retire les anciennes règles (qui laissaient souvent tout passer)
    for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    -- 2. On active le contrôle d'accès
    execute format('alter table public.%I enable row level security', t);
    -- 3. Seuls les comptes connectés ont accès
    execute format('create policy "membres_connectes" on public.%I for all to authenticated using (true) with check (true)', t);
    raise notice 'Table % verrouillée', t;
  end loop;
end $$;

-- Vérification : chaque table doit afficher rls_active = true
select c.relname as table_name, c.relrowsecurity as rls_active
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in
  ('lp24_badges','lp24_casiers','lp24_fss','lp24_settings','historique','badges_pret','badges_pret_histo')
order by 1;
