-- ════════════════════════════════════════════════════════════════════
--  E-MAIL AUTOMATIQUE AU RESTAURANT LE JOUR DU DÉPART — Gestion Collaborateurs
--  À lancer UNE FOIS dans Supabase → SQL Editor (après avoir rempli l'étape 2).
--
--  Chaque matin (vers 7 h), la base cherche les collaborateurs dont la date de
--  sortie est arrivée et envoie un e-mail au restaurant d'entreprise via EmailJS.
--  • Adresses et texte : repris des Réglages de l'appli (e-mail restaurant, copies,
--    modèle « Départ → Restaurant »).
--  • Un seul e-mail par personne. Chaque envoi est noté dans l'Historique de l'appli.
--  • Fonctionne même si personne n'ouvre l'appli.
--  Aucune donnée existante n'est modifiée.
-- ════════════════════════════════════════════════════════════════════

-- ── Étape 1 : outils de la base (planification + envoi web) ──
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ── Étape 2 : réglages EmailJS (À REMPLIR : remplace les deux valeurs entre << >>) ──
create table if not exists public.lp24_mail_config(
  id int primary key default 1 check (id = 1),
  emailjs_service     text not null,
  emailjs_template    text not null,
  emailjs_public_key  text not null,
  emailjs_private_key text not null,
  actif   boolean not null default true,
  depuis  date    not null default current_date   -- pas d'envoi pour les départs antérieurs à l'installation
);
-- clé privée : table invisible depuis l'appli (aucune règle d'accès)
alter table public.lp24_mail_config enable row level security;

insert into public.lp24_mail_config(id, emailjs_service, emailjs_template, emailjs_public_key, emailjs_private_key)
values (1, 'service_i09ljga', '<<ID_DU_MODELE_RESTAURANT>>', 'n04JbAxmU3mf9UuXz', '<<CLE_PRIVEE_EMAILJS>>')
on conflict (id) do update set
  emailjs_service = excluded.emailjs_service, emailjs_template = excluded.emailjs_template,
  emailjs_public_key = excluded.emailjs_public_key, emailjs_private_key = excluded.emailjs_private_key;

-- ── Étape 3 : journal des e-mails envoyés (un par collaborateur) ──
create table if not exists public.lp24_mails_depart(
  badge_id     bigint primary key,
  nom          text,
  prenom       text,
  date_sortie  date,
  destinataire text,
  envoye_le    timestamptz not null default now(),
  requete      bigint
);

-- ── Étape 4 : la fonction d'envoi ──
create or replace function public.envoyer_mails_depart() returns integer
language plpgsql security definer set search_path = public, extensions as $fn$
declare
  cfg  record; st jsonb; b record;
  dest text; cc text; modele text; corps text; sujet text; dfr text;
  rid  bigint; n integer := 0; d date;
begin
  select * into cfg from public.lp24_mail_config where id = 1;
  if cfg is null or not cfg.actif or cfg.emailjs_private_key like '<<%' then return 0; end if;

  -- envois précédents refusés par EmailJS : on les retire du journal pour réessayer
  delete from public.lp24_mails_depart m
   using net._http_response r
   where r.id = m.requete and coalesce(r.status_code, 0) <> 200;

  select (data::text)::jsonb into st from public.lp24_settings where id = 1;
  dest := nullif(trim(coalesce(st->>'restaurantEmail', '')), '');
  if dest is null then return 0; end if;
  cc := coalesce(st->>'ccEmails', '');
  modele := coalesce(nullif(st->>'bodyDepartResto', ''),
    E'Bonjour,\n\nNous vous informons du départ du collaborateur suivant :\n\nNom : {nom}\nPrénom : {prenom}\nMatricule : {matricule}\nN° badge : {serie}\nDate de départ : {date_sortie_prevue}\nManager : {manager}\n\nMerci de bien vouloir le retirer de vos systèmes.\n\nCordialement,\nLe responsable de site');

  for b in
    select x.* from public.lp24_badges x
     where coalesce(x.date_sortie_prevue::text, '') ~ '^\d{4}-\d{2}-\d{2}'
       and left(x.date_sortie_prevue::text, 10)::date <= current_date
       and left(x.date_sortie_prevue::text, 10)::date >= cfg.depuis
       and not exists (select 1 from public.lp24_mails_depart m where m.badge_id = x.id)
  loop
    d   := left(b.date_sortie_prevue::text, 10)::date;
    dfr := to_char(d, 'DD/MM/YYYY');
    corps := modele;
    corps := replace(corps, '{nom}',               coalesce(b.nom, ''));
    corps := replace(corps, '{prenom}',            coalesce(b.prenom, ''));
    corps := replace(corps, '{matricule}',         coalesce(nullif(b.matricule::text, ''), 'NC'));
    corps := replace(corps, '{serie}',             coalesce(nullif(b.serie::text, ''), 'Non attribué'));
    corps := replace(corps, '{manager}',           coalesce(nullif(b.manager::text, ''), '—'));
    corps := replace(corps, '{date_sortie_prevue}', dfr);
    corps := replace(corps, 'Date de sortie', 'Date de départ');
    if position('Date de départ' in corps) = 0 then
      corps := regexp_replace(corps, E'\n\nMerci', E'\nDate de départ : ' || dfr || E'\n\nMerci');
      if position('Date de départ' in corps) = 0 then corps := corps || E'\n\nDate de départ : ' || dfr; end if;
    end if;
    corps := replace(corps, 'Service RH', 'Le responsable de site');
    if position('responsable de site' in lower(corps)) = 0 then
      corps := regexp_replace(rtrim(corps), 'Cordialement\.?$', 'Cordialement,');
      corps := rtrim(corps) || E'\nLe responsable de site';
    end if;
    sujet := 'Départ collaborateur — ' || coalesce(b.prenom, '') || ' ' || coalesce(b.nom, '');

    rid := net.http_post(
      url     := 'https://api.emailjs.com/api/v1.0/email/send',
      body    := jsonb_build_object(
                   'service_id',  cfg.emailjs_service,
                   'template_id', cfg.emailjs_template,
                   'user_id',     cfg.emailjs_public_key,
                   'accessToken', cfg.emailjs_private_key,
                   'template_params', jsonb_build_object(
                      'to_email', dest, 'cc_email', cc, 'subject', sujet, 'message', corps)),
      headers := '{"Content-Type": "application/json"}'::jsonb);

    insert into public.lp24_mails_depart(badge_id, nom, prenom, date_sortie, destinataire, requete)
    values (b.id, b.nom, b.prenom, d, dest, rid);
    insert into public.historique(action, detail, user_email, ts)
    values ('Mail départ restaurant', coalesce(b.prenom,'') || ' ' || coalesce(b.nom,'') || ' (départ le ' || dfr || ') → ' || dest, 'automatique', now());
    n := n + 1;
  end loop;
  return n;
end
$fn$;

-- ── Étape 5 : tous les jours à 5 h UTC (7 h en été, 6 h en hiver à Paris) ──
select cron.unschedule('mail-depart-restaurant') where exists (select 1 from cron.job where jobname = 'mail-depart-restaurant');
select cron.schedule('mail-depart-restaurant', '0 5 * * *', $job$select public.envoyer_mails_depart();$job$);

-- ════════════════════════════════════════════════════════════════════
--  Utile :
--  • Envoyer tout de suite (test) :      select public.envoyer_mails_depart();
--  • Voir les e-mails envoyés :          select * from public.lp24_mails_depart order by envoye_le desc;
--  • Voir la réponse d'EmailJS :         select id, status_code, content from net._http_response order by id desc limit 10;
--  • Mettre en pause :                   update public.lp24_mail_config set actif = false;
--  • Tout arrêter définitivement :       select cron.unschedule('mail-depart-restaurant');
-- ════════════════════════════════════════════════════════════════════
