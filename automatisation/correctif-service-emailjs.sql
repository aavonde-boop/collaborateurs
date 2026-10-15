-- ════════════════════════════════════════════════════════════════════
--  CORRECTIF — nouveau service EmailJS + adresses séparées par « ; » acceptées
--  À lancer UNE FOIS dans Supabase → SQL Editor (rien à remplir).
-- ════════════════════════════════════════════════════════════════════
update public.lp24_mail_config set emailjs_service = 'service_gv8it64' where id = 1;

create or replace function public.envoyer_mails_auto() returns integer
language plpgsql security definer set search_path = public, extensions as $fn$
declare
  cfg record; st jsonb; b record; t record;
  dest text; cc text; d date; dfr text; rid bigint; n integer := 0;
  arrivee boolean; params jsonb; sujet text; msg text;
begin
  select * into cfg from public.lp24_mail_config where id = 1;
  if cfg is null or not cfg.actif or cfg.emailjs_private_key like '<<%' then return 0; end if;

  -- envois refusés par EmailJS : retirés du journal pour être retentés
  delete from public.lp24_mails_auto m using net._http_response r
   where r.id = m.requete and coalesce(r.status_code, 0) <> 200;

  select (data::text)::jsonb into st from public.lp24_settings where id = 1;
  cc := regexp_replace(coalesce(st->>'ccEmails', ''), '\s*;\s*', ',', 'g');

  for t in select * from (values
      ('it_arrivee',    'it',    true,  cfg.jours_avant_it),
      ('it_depart',     'it',    false, cfg.jours_avant_it),
      ('resto_arrivee', 'resto', true,  cfg.jours_avant_resto),
      ('resto_depart',  'resto', false, cfg.jours_avant_resto)) as v(type, cible, arr, avance)
  loop
    dest := nullif(trim(coalesce(st->>(case when t.cible = 'it' then 'itEmail' else 'restaurantEmail' end), '')), '');
    continue when dest is null;
    dest := regexp_replace(dest, '\s*;\s*', ',', 'g');
    for b in
      select x.*, left((case when t.arr then x.date_entree else x.date_sortie_prevue end)::text, 10) as dtxt
        from public.lp24_badges x
       where coalesce((case when t.arr then x.date_entree else x.date_sortie_prevue end)::text, '') ~ '^\d{4}-\d{2}-\d{2}'
         and not exists (select 1 from public.lp24_mails_auto m where m.badge_id = x.id and m.type = t.type)
    loop
      d := b.dtxt::date;
      -- à envoyer quand on est à « avance » jours (ou moins) de la date, sans remonter avant l'installation
      continue when d - t.avance > current_date or d < cfg.depuis;
      continue when (not t.arr) and d < current_date - 7;   -- départ trop ancien : on ne relance pas
      continue when t.arr and d < current_date;              -- arrivée déjà passée : inutile
      dfr := to_char(d, 'DD/MM/YYYY');
      arrivee := t.arr;
      sujet := (case when arrivee then 'Arrivée' else 'Départ' end) || ' — ' || initcap(coalesce(b.prenom,'')) || ' ' || upper(coalesce(b.nom,'')) || ' — ' || dfr;
      msg := 'Bonjour,' || E'\n\n'
          || 'Nous vous informons ' || (case when arrivee then 'de l''arrivée d''un nouveau collaborateur' else 'du départ du collaborateur suivant' end) || ' :' || E'\n\n'
          || 'Nom : '    || upper(coalesce(b.nom, ''))      || E'\n'
          || 'Prénom : ' || initcap(coalesce(b.prenom, '')) || E'\n'
          || 'Date '     || (case when arrivee then 'd''arrivée' else 'de départ' end) || ' : ' || dfr || E'\n'
          || (case when t.cible = 'it'
                   then 'Manager : '         || coalesce(nullif(b.manager::text, ''), 'Non renseigné')
                   else 'Numéro de badge : ' || coalesce(nullif(b.serie::text, ''), 'Non attribué') end) || E'\n\n'
          || (case
                when t.cible = 'it'    and arrivee     then 'Merci de créer les accès nécessaires.'
                when t.cible = 'it'    and not arrivee then 'Merci de supprimer les accès.'
                when t.cible = 'resto' and arrivee     then 'Merci de bien vouloir l''ajouter à vos systèmes.'
                else                                        'Merci de bien vouloir le retirer de vos systèmes.' end) || E'\n\n'
          || E'Cordialement,\nArnaud AVONDE\n07.85.42.37.24\nResponsable de site';
      params := jsonb_build_object('to_email', dest, 'cc_email', cc, 'sujet', sujet, 'message', msg);
      rid := net.http_post(
        url     := 'https://api.emailjs.com/api/v1.0/email/send',
        body    := jsonb_build_object('service_id', cfg.emailjs_service,
                     'template_id', cfg.emailjs_template,
                     'user_id', cfg.emailjs_public_key, 'accessToken', cfg.emailjs_private_key,
                     'template_params', params),
        headers := '{"Content-Type": "application/json"}'::jsonb);
      insert into public.lp24_mails_auto(badge_id, type, nom, prenom, date_evt, destinataire, requete)
      values (b.id, t.type, b.nom, b.prenom, d, dest, rid);
      insert into public.historique(action, detail, user_email, ts)
      values ('Mail ' || (case when t.cible = 'it' then 'IT' else 'restaurant' end) || ' — ' || (case when arrivee then 'arrivée' else 'départ' end),
              initcap(coalesce(b.prenom,'')) || ' ' || upper(coalesce(b.nom,'')) || ' (' || dfr || ') → ' || dest, 'automatique', now());
      n := n + 1;
    end loop;
  end loop;
  return n;
end
$fn$;

create or replace function public.envoyer_relances_pret() returns integer
language plpgsql security definer set search_path = public, extensions as $fn$
declare cfg record; st jsonb; b record; cc text; msg text; quand text; rid bigint; n int := 0;
begin
  select * into cfg from public.lp24_mail_config where id = 1;
  if cfg is null or not cfg.actif or cfg.emailjs_private_key like '<<%' then return 0; end if;
  delete from public.lp24_relances_pret m using net._http_response r
   where r.id = m.requete and coalesce(r.status_code, 0) <> 200;      -- refusé par EmailJS : retenté
  select (data::text)::jsonb into st from public.lp24_settings where id = 1;
  cc := regexp_replace(coalesce(st->>'ccEmails', ''), '\s*;\s*', ',', 'g');
  for b in
    select * from public.badges_pret x
     where x.statut in ('prete','empruntee')
       and x.pret_le <= now() - interval '24 hours'
       and trim(coalesce(x.email_emprunteur,'')) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
       and not exists (select 1 from public.lp24_relances_pret m
                        where m.badge_id = x.id and m.pret_le = x.pret_le and m.jour = current_date)
  loop
    quand := to_char(b.pret_le at time zone 'Europe/Paris', 'DD/MM/YYYY "à" HH24"h"MI');
    msg := 'Bonjour' || coalesce(' ' || initcap(lower(nullif(trim(b.emprunteur::text), ''))), '') || ',' || E'\n\n'
        || 'Le badge de prêt ' || coalesce(b.code::text,'') || coalesce(' (' || nullif(b.nom::text,'') || ')', '')
        || ' vous a été remis le ' || quand || ' et n''a pas encore été restitué.' || E'\n\n'
        || 'Merci de bien vouloir le rapporter à l''accueil dès que possible.' || E'\n'
        || 'Si vous l''avez déjà rendu, merci de ne pas tenir compte de ce message.' || E'\n\n'
        || E'Cordialement,\nArnaud AVONDE\n07.85.42.37.24\nResponsable de site';
    rid := net.http_post(
      url     := 'https://api.emailjs.com/api/v1.0/email/send',
      body    := jsonb_build_object('service_id', cfg.emailjs_service, 'template_id', cfg.emailjs_template,
                   'user_id', cfg.emailjs_public_key, 'accessToken', cfg.emailjs_private_key,
                   'template_params', jsonb_build_object('to_email', trim(b.email_emprunteur), 'cc_email', cc,
                       'sujet', 'Rappel — badge de prêt ' || coalesce(b.code::text,'') || ' à restituer', 'message', msg)),
      headers := '{"Content-Type": "application/json"}'::jsonb);
    insert into public.lp24_relances_pret(badge_id, pret_le, destinataire, requete) values (b.id, b.pret_le, trim(b.email_emprunteur), rid);
    insert into public.historique(action, detail, user_email, ts)
    values ('Rappel badge de prêt', coalesce(b.code::text,'') || ' — ' || coalesce(b.emprunteur::text,'') || ' (prêté le ' || quand || ') → ' || trim(b.email_emprunteur), 'automatique', now());
    n := n + 1;
  end loop;
  return n;
end
$fn$;

-- Vérification (doit afficher service_gv8it64) :
select emailjs_service from public.lp24_mail_config;
