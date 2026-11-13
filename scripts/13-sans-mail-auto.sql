-- ════════════════════════════════════════════════════════════════════
--  13 · « Nouveau collaborateur » sans mail automatique
--  Projet jymobewqenhcjtzniytb → SQL Editor → Run. Peut être relancé sans risque.
--  Une fiche marquée « sans mail automatique » ne déclenche ni le mail IT
--  ni le mail restaurant (arrivée et départ). Les mails s'envoient à la main
--  depuis la fiche. Décocher la case sur la fiche réactive les envois.
-- ════════════════════════════════════════════════════════════════════

alter table public.lp24_badges add column if not exists sans_mail_auto boolean not null default false;

-- Les envois automatiques sautent toute personne déjà présente dans le journal :
-- on y inscrit donc la fiche comme « déjà traitée » (date ancienne, hors compteur du mois).
create or replace function public.lp24_sans_mail_auto() returns trigger
language plpgsql security definer set search_path = public as $f$
begin
  if coalesce(new.sans_mail_auto, false) then
    insert into public.lp24_mails_auto(badge_id, type, nom, prenom, date_evt, destinataire, envoye_le, requete)
    select new.id, t, new.nom, new.prenom, null, 'coupé sur la fiche', timestamptz '2000-01-01', null
      from unnest(array['it_arrivee','it_depart','resto_arrivee','resto_depart']) as t
    on conflict (badge_id, type) do nothing;
  elsif tg_op = 'UPDATE' and coalesce(old.sans_mail_auto, false) then
    delete from public.lp24_mails_auto where badge_id = new.id and destinataire = 'coupé sur la fiche';
  end if;
  return new;
end
$f$;

drop trigger if exists lp24_sans_mail_auto on public.lp24_badges;
create trigger lp24_sans_mail_auto after insert or update of sans_mail_auto on public.lp24_badges
  for each row execute function public.lp24_sans_mail_auto();

-- Vérification : doit afficher « prêt »
select case when exists (select 1 from information_schema.columns where table_schema='public' and table_name='lp24_badges' and column_name='sans_mail_auto')
             and exists (select 1 from pg_trigger where tgname='lp24_sans_mail_auto') then 'prêt' else 'à vérifier' end as resultat;
