-- ════════════════════════════════════════════════════════════════════
--  MENTIONS LÉGALES ET CONFIDENTIALITÉ — Gestion Collaborateurs
--  À lancer une fois dans Supabase → SQL Editor (projet jymobewqenhcjtzniytb).
--  Peut être relancé sans risque. Ne touche à aucune autre donnée.
--
--  Crée une petite table pour ces 2 textes :
--   · lisibles par tout le monde (même sans compte, depuis l'écran de connexion) ;
--   · modifiables uniquement par un administrateur de l'appli (bouton « Modifier »).
--  Elle ne contient que ces 2 textes : aucune donnée personnelle.
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.lp24_textes_publics (
  cle   text primary key check (cle in ('mentions', 'confidentialite')),
  texte text not null default '',
  maj   timestamptz not null default now()
);

create or replace function public.lp24_est_admin_appli() returns boolean
language sql stable security definer set search_path = public as $f$
  select public.lp24_est_admin(public.lp24_comptes())
$f$;
revoke all on function public.lp24_est_admin_appli() from public, anon;
grant execute on function public.lp24_est_admin_appli() to authenticated;

alter table public.lp24_textes_publics enable row level security;
do $$ declare p record; begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'lp24_textes_publics' loop
    execute format('drop policy %I on public.lp24_textes_publics', p.policyname);
  end loop;
end $$;
create policy "lecture_publique" on public.lp24_textes_publics for select to anon, authenticated using (true);
create policy "ecriture_admin" on public.lp24_textes_publics for insert to authenticated with check ((select public.lp24_est_admin_appli()));
create policy "modif_admin" on public.lp24_textes_publics for update to authenticated using ((select public.lp24_est_admin_appli())) with check ((select public.lp24_est_admin_appli()));
revoke all on public.lp24_textes_publics from anon, authenticated;
grant select on public.lp24_textes_publics to anon, authenticated;
grant insert, update on public.lp24_textes_publics to authenticated;

-- Vérification
select 'Textes lisibles sans compte' as point, case when has_table_privilege('anon', 'public.lp24_textes_publics', 'select') then 'oui' else 'NON' end as ok
union all
select 'Modification impossible sans compte', case when not has_table_privilege('anon', 'public.lp24_textes_publics', 'insert') and not has_table_privilege('anon', 'public.lp24_textes_publics', 'update') then 'oui' else 'NON' end
union all
select 'Modification réservée aux administrateurs', case when exists (select 1 from pg_policies where tablename = 'lp24_textes_publics' and policyname = 'modif_admin') then 'oui' else 'NON' end;
