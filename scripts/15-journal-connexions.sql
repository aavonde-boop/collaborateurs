-- ════════════════════════════════════════════════════════════════════
--  15 · Journal des connexions
--  Projet jymobewqenhcjtzniytb → SQL Editor → Run. Peut être relancé sans risque.
--  • une ligne par ouverture de l'appli (au plus une toutes les 30 min par appareil) ;
--  • l'adresse vient du jeton de connexion (impossible de se faire passer pour un autre) ;
--  • seuls les administrateurs peuvent lire le journal ;
--  • les lignes de plus d'un an sont effacées automatiquement (RGPD).
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.lp24_connexions (
  id        bigserial primary key,
  email     text not null,
  le        timestamptz not null default now(),
  appareil  text,
  espace    text
);
create index if not exists lp24_connexions_le on public.lp24_connexions (le desc);

alter table public.lp24_connexions enable row level security;
revoke all on public.lp24_connexions from anon, authenticated;
grant select on public.lp24_connexions to authenticated;
drop policy if exists connexions_admin on public.lp24_connexions;
create policy connexions_admin on public.lp24_connexions for select to authenticated
  using ((select public.lp24_est_admin_appli()));

create or replace function public.lp24_noter_connexion(p_appareil text, p_espace text default null)
returns void language plpgsql security definer set search_path = public as $f$
declare em text := lower(coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email', ''));
begin
  if em = '' or not public.lp24_est_membre() then return; end if;
  delete from public.lp24_connexions where le < now() - interval '1 year';
  if exists (select 1 from public.lp24_connexions
             where email = em and coalesce(appareil,'') = coalesce(left(p_appareil, 60),'') and le > now() - interval '30 minutes') then
    return;
  end if;
  insert into public.lp24_connexions(email, appareil, espace) values (em, left(p_appareil, 60), left(p_espace, 30));
end
$f$;
revoke all on function public.lp24_noter_connexion(text, text) from public, anon;
grant execute on function public.lp24_noter_connexion(text, text) to authenticated;

-- Vérification : doit afficher « prêt »
select case when to_regclass('public.lp24_connexions') is not null then 'prêt' else 'à vérifier' end as resultat;
