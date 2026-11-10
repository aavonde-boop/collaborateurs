-- ════════════════════════════════════════════════════════════════════
--  ACCÈS RÉSERVÉ AUX MEMBRES DE L'APPLI — Gestion Collaborateurs
--  À lancer une fois dans Supabase → SQL Editor (projet jymobewqenhcjtzniytb).
--  Peut être relancé sans risque. Ne touche à aucune donnée.
--
--  Avant : tout compte connecté pouvait lire et modifier les tables.
--  Après : il faut en plus figurer dans Réglages → Comptes de l'appli.
--          Un compte créé en douce, ou retiré de la liste, ne voit plus rien.
--  Aussi : plus d'administrateur « automatique » par adresse e-mail.
--  Les envois automatiques (cron) et le SQL Editor ne sont pas concernés.
-- ════════════════════════════════════════════════════════════════════

-- ── Liste des comptes de l'appli (Réglages → Comptes), lue côté serveur
create or replace function public.lp24_comptes() returns jsonb
language sql stable security definer set search_path = public as $f$
  select coalesce((select case when jsonb_typeof(public.lp24_json(s.data)->'users') = 'array'
                               then public.lp24_json(s.data)->'users' end
                   from public.lp24_settings s where s.id = 1), '[]'::jsonb)
$f$;

-- ── La personne connectée fait-elle partie de l'appli ?
create or replace function public.lp24_est_membre() returns boolean
language plpgsql stable security definer set search_path = public as $f$
declare em text := public.lp24_email_appelant(); u jsonb := public.lp24_comptes();
begin
  if coalesce(current_setting('request.jwt.claims', true), '') = '' then
    return true;                                   -- SQL Editor, cron, déclencheurs internes
  end if;
  if em = '' then return false; end if;
  return exists (select 1 from jsonb_array_elements(u) e where lower(trim(e->>'email')) = em);
end $f$;
revoke all on function public.lp24_est_membre() from public, anon;
grant execute on function public.lp24_est_membre() to authenticated;
revoke all on function public.lp24_comptes() from public, anon, authenticated;

-- ── Administrateur : uniquement ceux marqués « Administrateur » dans Réglages → Comptes
create or replace function public.lp24_est_admin(users jsonb) returns boolean
language plpgsql stable as $f$
declare em text := public.lp24_email_appelant(); u jsonb := coalesce(users, '[]'::jsonb);
begin
  if coalesce(current_setting('request.jwt.claims', true), '') = '' then
    return true;                                   -- SQL Editor, cron, déclencheurs internes
  end if;
  if jsonb_typeof(u) <> 'array' then return false; end if;
  return exists (select 1 from jsonb_array_elements(u) e where lower(trim(e->>'email')) = em and e->>'role' = 'admin');
end $f$;

-- ── Toutes les tables : accès réservé aux membres
do $$
declare
  t text; p record;
  internes text[] := array['lp24_mail_config','lp24_mails_auto','lp24_mails_depart','lp24_mails_pret','lp24_relances_pret'];
begin
  for t in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind = 'r' and c.relname <> all(internes) loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('create policy "membres_appli" on public.%I for all to authenticated using ((select public.lp24_est_membre())) with check ((select public.lp24_est_membre()))', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
  execute 'grant usage, select on all sequences in schema public to authenticated';
end $$;

-- ── Vérification : chaque table doit afficher « membres de l'appli »
select c.relname as "table",
       case when c.relname in ('lp24_mail_config','lp24_mails_auto','lp24_mails_depart','lp24_mails_pret','lp24_relances_pret') then 'interne (fermée)'
            when not c.relrowsecurity then 'NON : RLS désactivée'
            when exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname and p.policyname = 'membres_appli') then 'membres de l''appli'
            else 'NON : à vérifier' end as acces
from pg_class c join pg_namespace s on s.oid = c.relnamespace
where s.nspname = 'public' and c.relkind = 'r'
order by 2 desc, 1;
