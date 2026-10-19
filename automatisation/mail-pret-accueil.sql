-- ════════════════════════════════════════════════════════════════════
--  MAIL À L'EMPRUNTEUR AU MOMENT DU PRÊT (horaires de l'accueil) — Gestion Collaborateurs
--  À lancer UNE FOIS dans Supabase → SQL Editor (rien à remplir).
--  Part tout seul quand un badge est marqué « Prêtée » avec un e-mail
--  (ou quand on ajoute l'e-mail à un prêt en cours). Un seul mail par prêt.
--  Le rappel quotidien après 24 h rappelle aussi les horaires.
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.lp24_mails_pret(
  badge_id bigint not null,
  pret_le  timestamptz not null,
  destinataire text,
  envoye_le timestamptz not null default now(),
  requete  bigint,
  primary key (badge_id, pret_le)
);

create or replace function public.lp24_horaires_accueil() returns text
language sql immutable as $h$
  select E'Horaires de l''accueil :\n'
      || E'• Du lundi au jeudi : de 8h00 à 12h00 et de 13h30 à 17h00\n'
      || E'• Le vendredi : de 8h00 à 13h00\n'
      || E'Accueil joignable au 07.77.64.82.06 pendant les horaires d''ouverture.'
$h$;

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

  msg := 'Bonjour' || coalesce(' ' || initcap(lower(nullif(trim(new.emprunteur::text), ''))), '') || ',' || E'\n\n'
      || 'Le badge de prêt ' || coalesce(new.code::text, '') || coalesce(' (' || nullif(new.nom::text, '') || ')', '')
      || ' vous a été remis le ' || to_char(new.pret_le at time zone 'Europe/Paris', 'DD/MM/YYYY "à" HH24"h"MI') || '.' || E'\n'
      || coalesce('Retour prévu : ' || to_char(left(nullif(new.date_retour_prevu::text, ''), 10)::date, 'DD/MM/YYYY') || E'\n', '')
      || E'\nMerci de le rapporter à l''accueil.\n\n'
      || public.lp24_horaires_accueil() || E'\n\n'
      || 'À défaut de retour de votre part, des rappels vous seront envoyés jusqu''à confirmation de la restitution du badge.' || E'\n\n'
      || E'Cordialement,\nArnaud AVONDE\n07.85.42.37.24\nResponsable de site';

  rid := net.http_post(
    url     := 'https://api.emailjs.com/api/v1.0/email/send',
    body    := jsonb_build_object('service_id', cfg.emailjs_service, 'template_id', cfg.emailjs_template,
                 'user_id', cfg.emailjs_public_key, 'accessToken', cfg.emailjs_private_key,
                 'template_params', jsonb_build_object('to_email', dest, 'cc_email', '',
                     'sujet', 'Badge de prêt ' || coalesce(new.code::text, '') || ' — horaires de l''accueil', 'message', msg)),
    headers := '{"Content-Type": "application/json"}'::jsonb);
  insert into public.lp24_mails_pret(badge_id, pret_le, destinataire, requete) values (new.id, new.pret_le, dest, rid)
  on conflict do nothing;
  insert into public.historique(action, detail, user_email, ts)
  values ('Mail prêt de badge', coalesce(new.code::text, '') || ' — ' || coalesce(new.emprunteur::text, '') || ' → ' || dest, 'automatique', now());
  return new;
exception when others then
  return new;   -- un souci d'envoi ne doit jamais bloquer l'enregistrement du prêt
end
$fn$;

drop trigger if exists mail_pret_accueil on public.badges_pret;
create trigger mail_pret_accueil after insert or update on public.badges_pret
  for each row execute function public.mail_pret_accueil();

-- Le rappel quotidien rappelle aussi les horaires
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
    msg := 'Bonjour' || coalesce(' ' || initcap(lower(nullif(trim(b.emprunteur::text), ''))), '') || ',' || E'\n\n'
        || 'Le badge de prêt ' || coalesce(b.code::text,'') || coalesce(' (' || nullif(b.nom::text,'') || ')', '')
        || ' vous a été remis le ' || quand || ' et n''a pas encore été restitué.' || E'\n\n'
        || 'Merci de bien vouloir le rapporter à l''accueil dès que possible.' || E'\n'
        || 'Si vous l''avez déjà rendu, merci de ne pas tenir compte de ce message.' || E'\n\n'
        || public.lp24_horaires_accueil() || E'\n\n'
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

select 'Installé' as resultat;
