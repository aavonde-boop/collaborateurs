-- ════════════════════════════════════════════════════════════════════
--  PIÈCES JOINTES DU MAIL DE BIENVENUE — Gestion Collaborateurs
--  À lancer une fois dans Supabase → SQL Editor (projet jymobewqenhcjtzniytb).
--  Peut être relancé sans risque. Ne touche à aucune autre donnée.
--
--  Crée une petite table pour les 2 pièces jointes fixes du mail de bienvenue
--  (Réglages → Textes des mails). Accès réservé aux membres de l'appli.
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.lp24_pieces_jointes (
  slot   int primary key check (slot in (1, 2)),
  nom    text not null,
  type   text not null default 'application/octet-stream',
  taille int  not null default 0 check (taille <= 4194304),
  data   text not null,
  maj    timestamptz not null default now()
);
alter table public.lp24_pieces_jointes enable row level security;
do $$ declare p record; begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'lp24_pieces_jointes' loop
    execute format('drop policy %I on public.lp24_pieces_jointes', p.policyname);
  end loop;
end $$;
create policy "membres_appli" on public.lp24_pieces_jointes for all to authenticated
  using ((select public.lp24_est_membre())) with check ((select public.lp24_est_membre()));
revoke all on public.lp24_pieces_jointes from anon;
grant select, insert, update, delete on public.lp24_pieces_jointes to authenticated;

-- Vérification
select 'Pièces jointes : table prête' as point, case when to_regclass('public.lp24_pieces_jointes') is not null then 'oui' else 'NON' end as ok
union all
select 'Fermée sans connexion', case when not has_table_privilege('anon', 'public.lp24_pieces_jointes', 'select') then 'oui' else 'NON' end
union all
select 'Réservée aux membres de l''appli', case when exists (select 1 from pg_policies where tablename = 'lp24_pieces_jointes' and policyname = 'membres_appli') then 'oui' else 'NON' end;
