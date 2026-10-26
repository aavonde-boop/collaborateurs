-- ════════════════════════════════════════════════════════════════════
--  COMPTEUR DES MAILS DU MOIS (quota EmailJS : 200 / mois)
--  À lancer une fois dans Supabase → SQL Editor.
--  • lp24_mails_appli : journal des mails envoyés depuis l'appli (Field Support, tests)
--  • lp24_compteur_mails() : total du mois en cours, tous envois confondus
-- ════════════════════════════════════════════════════════════════════
create table if not exists public.lp24_mails_appli(
  id bigserial primary key,
  type text,
  destinataire text,
  envoye_le timestamptz not null default now()
);
alter table public.lp24_mails_appli enable row level security;
drop policy if exists "membres_connectes" on public.lp24_mails_appli;
create policy "membres_connectes" on public.lp24_mails_appli for all to authenticated using (true) with check (true);
revoke all on public.lp24_mails_appli from anon;
grant select, insert on public.lp24_mails_appli to authenticated;
grant usage, select on sequence public.lp24_mails_appli_id_seq to authenticated;

create or replace function public.lp24_compteur_mails() returns jsonb
language plpgsql stable security definer set search_path = public as $f$
declare
  debut timestamptz := date_trunc('month', now() at time zone 'Europe/Paris') at time zone 'Europe/Paris';
  n_auto int := 0; n_pret int := 0; n_rel int := 0; n_app int := 0;
begin
  if to_regclass('public.lp24_mails_auto') is not null then
    select count(*) into n_auto from public.lp24_mails_auto where envoye_le >= debut; end if;
  if to_regclass('public.lp24_mails_pret') is not null then
    select count(*) into n_pret from public.lp24_mails_pret where envoye_le >= debut; end if;
  if to_regclass('public.lp24_relances_pret') is not null then
    select count(*) into n_rel from public.lp24_relances_pret where jour >= debut::date; end if;
  if to_regclass('public.lp24_mails_appli') is not null then
    select count(*) into n_app from public.lp24_mails_appli where envoye_le >= debut; end if;
  return jsonb_build_object('arrivees_departs', n_auto, 'prets', n_pret, 'relances', n_rel, 'appli', n_app,
                            'total', n_auto + n_pret + n_rel + n_app, 'depuis', debut);
end $f$;
revoke all on function public.lp24_compteur_mails() from public, anon;
grant execute on function public.lp24_compteur_mails() to authenticated;

-- Vérification : affiche le compteur du mois
select public.lp24_compteur_mails();
