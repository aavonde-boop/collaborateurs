-- ════════════════════════════════════════════════════════════════════
--  TEXTES DES MAILS MODIFIABLES DEPUIS L'APPLI (Réglages → Modèles)
--  À lancer UNE FOIS dans Supabase → SQL Editor (rien à remplir).
--  Tant qu'un texte n'est pas modifié dans l'appli, le texte actuel est utilisé.
-- ════════════════════════════════════════════════════════════════════

-- Textes d'origine (utilisés si le champ est vide dans l'appli)
create or replace function public.lp24_texte_defaut(cle text) returns text
language sql immutable as $d$
  select case cle
    when 'autoSignature' then E'Arnaud AVONDE\n07.85.42.37.24\nResponsable de site'
    when 'autoHoraires'  then E'Horaires de l''accueil :\n• Du lundi au jeudi : de 8h00 à 12h00 et de 13h30 à 17h00\n• Le vendredi : de 8h00 à 13h00\nAccueil joignable au 07.77.64.82.06 pendant les horaires d''ouverture.'
    when 'autoITArrivee' then E'Bonjour,\n\nNous vous informons de l''arrivée d''un nouveau collaborateur :\n\nNom : {nom}\nPrénom : {prenom}\nDate d''arrivée : {date}\nManager : {manager}\n\nMerci de créer les accès nécessaires.\n\nCordialement,\n{signature}'
    when 'autoITDepart'  then E'Bonjour,\n\nNous vous informons du départ du collaborateur suivant :\n\nNom : {nom}\nPrénom : {prenom}\nDate de départ : {date}\nManager : {manager}\n\nMerci de supprimer les accès.\n\nCordialement,\n{signature}'
    when 'autoRestoArrivee' then E'Bonjour,\n\nNous vous informons de l''arrivée d''un nouveau collaborateur :\n\nNom : {nom}\nPrénom : {prenom}\nDate d''arrivée : {date}\nNuméro de badge : {badge}\n\nMerci de bien vouloir l''ajouter à vos systèmes.\n\nCordialement,\n{signature}'
    when 'autoRestoDepart'  then E'Bonjour,\n\nNous vous informons du départ du collaborateur suivant :\n\nNom : {nom}\nPrénom : {prenom}\nDate de départ : {date}\nNuméro de badge : {badge}\n\nMerci de bien vouloir le retirer de vos systèmes.\n\nCordialement,\n{signature}'
    when 'autoPret'   then E'Bonjour {emprunteur},\n\nLe badge de prêt {code} ({badge_nom}) vous a été remis le {date_pret}.\n{ligne_retour}\n\nMerci de le rapporter à l''accueil.\n\n{horaires}\n\nÀ défaut de retour de votre part, des rappels vous seront envoyés jusqu''à confirmation de la restitution du badge.\n\nCordialement,\n{signature}'
    when 'autoRappel' then E'Bonjour {emprunteur},\n\nLe badge de prêt {code} ({badge_nom}) vous a été remis le {date_pret} et n''a pas encore été restitué.\n\nMerci de bien vouloir le rapporter à l''accueil dès que possible.\nSi vous l''avez déjà rendu, merci de ne pas tenir compte de ce message.\n\n{horaires}\n\nCordialement,\n{signature}'
  end
$d$;

-- Texte en vigueur : celui des Réglages de l'appli, sinon l'origine
create or replace function public.lp24_texte(cle text) returns text
language sql stable security definer set search_path = public as $t$
  select coalesce(nullif(btrim(public.lp24_reglages()->>cle), ''), public.lp24_texte_defaut(cle))
$t$;

-- Remplace les {variables} et nettoie (lignes vides en trop, « Bonjour , », « () »)
create or replace function public.lp24_remplir(modele text, vars jsonb) returns text
language plpgsql stable as $r$
declare k text; v text; t text := coalesce(modele, '');
begin
  for k, v in select key, value from jsonb_each_text(vars) loop
    t := replace(t, '{' || k || '}', coalesce(v, ''));
  end loop;
  t := replace(t, E'\r', '');
  t := regexp_replace(t, ' +\(\)', '', 'g');
  t := regexp_replace(t, 'Bonjour +,', 'Bonjour,', 'g');
  t := regexp_replace(t, E'\n[ \t]*\n([ \t]*\n)+', E'\n\n', 'g');
  return t;
end
$r$;

create or replace function public.lp24_horaires_accueil() returns text
language sql stable as $h$ select public.lp24_texte('autoHoraires') $h$;

-- ── Mails IT / restaurant ──
create or replace function public.envoyer_mails_auto() returns integer
language plpgsql security definer set search_path = public, extensions as $fn$
declare
  cfg record; st jsonb; b record; t record;
  dest text; cc text; d date; dfr text; rid bigint; n integer := 0;
  arrivee boolean; params jsonb; sujet text; msg text;
begin
  select * into cfg from public.lp24_mail_config where id = 1;
  if cfg is null or not cfg.actif or cfg.emailjs_private_key like '<<%' then return 0; end if;
  delete from public.lp24_mails_auto m using net._http_response r
   where r.id = m.requete and coalesce(r.status_code, 0) <> 200;
  st := public.lp24_reglages();
  cc := regexp_replace(coalesce(st->>'ccEmails', ''), '\s*;\s*', ',', 'g');
  for t in select * from (values
      ('it_arrivee',    'it',    true,  cfg.jours_avant_it,    'autoITArrivee'),
      ('it_depart',     'it',    false, cfg.jours_avant_it,    'autoITDepart'),
      ('resto_arrivee', 'resto', true,  cfg.jours_avant_resto, 'autoRestoArrivee'),
      ('resto_depart',  'resto', false, cfg.jours_avant_resto, 'autoRestoDepart')) as v(type, cible, arr, avance, cle)
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
      continue when d - t.avance > current_date or d < cfg.depuis;
      continue when (not t.arr) and d < current_date - 7;
      continue when t.arr and d < current_date;
      dfr := to_char(d, 'DD/MM/YYYY');
      arrivee := t.arr;
      sujet := (case when arrivee then 'Arrivée' else 'Départ' end) || ' — ' || initcap(coalesce(b.prenom,'')) || ' ' || upper(coalesce(b.nom,'')) || ' — ' || dfr;
      msg := public.lp24_remplir(public.lp24_texte(t.cle), jsonb_build_object(
               'nom', upper(coalesce(b.nom, '')), 'prenom', initcap(coalesce(b.prenom, '')), 'date', dfr,
               'manager', coalesce(nullif(b.manager::text, ''), 'Non renseigné'),
               'badge', coalesce(nullif(b.serie::text, ''), 'Non attribué'),
               'signature', public.lp24_texte('autoSignature')));
      params := jsonb_build_object('to_email', dest, 'cc_email', cc, 'sujet', sujet, 'message', msg);
      rid := net.http_post(
        url     := 'https://api.emailjs.com/api/v1.0/email/send',
        body    := jsonb_build_object('service_id', cfg.emailjs_service, 'template_id', cfg.emailjs_template,
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

-- ── Mail au moment du prêt ──
create or replace function public.mail_pret_accueil() returns trigger
language plpgsql security definer set search_path = public, extensions as $fn$
declare cfg record; dest text; msg text; rid bigint;
begin
  dest := trim(coalesce(new.email_emprunteur, ''));
  if new.statut not in ('prete','empruntee') or new.pret_le is null
     or dest !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return new; end if;
  if exists (select 1 from public.lp24_mails_pret where badge_id = new.id and pret_le = new.pret_le) then return new; end if;
  select * into cfg from public.lp24_mail_config where id = 1;
  if cfg is null or not cfg.actif or cfg.emailjs_private_key like '<<%' then return new; end if;
  msg := public.lp24_remplir(public.lp24_texte('autoPret'), jsonb_build_object(
           'emprunteur', coalesce(initcap(lower(nullif(trim(new.emprunteur::text), ''))), ''),
           'code', coalesce(new.code::text, ''), 'badge_nom', coalesce(new.nom::text, ''),
           'date_pret', to_char(new.pret_le at time zone 'Europe/Paris', 'DD/MM/YYYY "à" HH24"h"MI'),
           'ligne_retour', coalesce('Retour prévu : ' || to_char(left(nullif(new.date_retour_prevu::text, ''), 10)::date, 'DD/MM/YYYY'), ''),
           'horaires', public.lp24_texte('autoHoraires'), 'signature', public.lp24_texte('autoSignature')));
  rid := net.http_post(
    url     := 'https://api.emailjs.com/api/v1.0/email/send',
    body    := jsonb_build_object('service_id', cfg.emailjs_service, 'template_id', cfg.emailjs_template,
                 'user_id', cfg.emailjs_public_key, 'accessToken', cfg.emailjs_private_key,
                 'template_params', jsonb_build_object('to_email', dest, 'cc_email', '',
                     'sujet', 'Badge de prêt ' || coalesce(new.code::text, '') || ' — horaires de l''accueil', 'message', msg)),
    headers := '{"Content-Type": "application/json"}'::jsonb);
  insert into public.lp24_mails_pret(badge_id, pret_le, destinataire, requete) values (new.id, new.pret_le, dest, rid) on conflict do nothing;
  insert into public.historique(action, detail, user_email, ts)
  values ('Mail prêt de badge', coalesce(new.code::text, '') || ' — ' || coalesce(new.emprunteur::text, '') || ' → ' || dest, 'automatique', now());
  return new;
exception when others then
  return new;
end
$fn$;

-- ── Rappel quotidien ──
create or replace function public.envoyer_relances_pret() returns integer
language plpgsql security definer set search_path = public, extensions as $fn$
declare cfg record; st jsonb; b record; cc text; msg text; quand text; rid bigint; n int := 0;
begin
  select * into cfg from public.lp24_mail_config where id = 1;
  if cfg is null or not cfg.actif or cfg.emailjs_private_key like '<<%' then return 0; end if;
  delete from public.lp24_relances_pret m using net._http_response r
   where r.id = m.requete and coalesce(r.status_code, 0) <> 200;
  st := public.lp24_reglages();
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
    msg := public.lp24_remplir(public.lp24_texte('autoRappel'), jsonb_build_object(
             'emprunteur', coalesce(initcap(lower(nullif(trim(b.emprunteur::text), ''))), ''),
             'code', coalesce(b.code::text, ''), 'badge_nom', coalesce(b.nom::text, ''), 'date_pret', quand,
             'horaires', public.lp24_texte('autoHoraires'), 'signature', public.lp24_texte('autoSignature')));
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

select 'Installé' as resultat;
