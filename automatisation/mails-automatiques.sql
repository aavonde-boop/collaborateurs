-- ════════════════════════════════════════════════════════════════════
--  E-MAILS AUTOMATIQUES (IT + RESTAURANT, ARRIVÉES + DÉPARTS) — Gestion Collaborateurs
--  À lancer UNE FOIS dans Supabase → SQL Editor (après avoir rempli l'étape 2).
--  Un seul modèle EmailJS sert aux 4 mails (le texte est écrit par le script).
--  Remplace l'ancien script « mail-depart-restaurant.sql » (inutile de lancer les deux).
--
--  Chaque matin (vers 7 h), la base envoie via EmailJS :
--   • à l'IT         : la VEILLE de chaque arrivée et de chaque départ
--   • au restaurant  : le JOUR de chaque arrivée et de chaque départ
--  Adresses : celles des Réglages de l'appli (e-mail IT, e-mail restaurant, copies).
--  Un seul e-mail par personne et par type. Chaque envoi apparaît dans l'Historique.
--  Fonctionne même si personne n'ouvre l'appli. Aucune donnée existante n'est modifiée.
-- ════════════════════════════════════════════════════════════════════

-- ── Étape 1 : outils de la base (planification + envoi web) ──
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ── Étape 2 : réglages EmailJS — À REMPLIR : les deux valeurs entre << >> ──
create table if not exists public.lp24_mail_config(
  id int primary key default 1 check (id = 1),
  emailjs_service     text not null,
  emailjs_public_key  text not null,
  emailjs_private_key text not null,
  emailjs_template    text not null,                -- un seul modèle « passe-partout » pour les 4 mails
  jours_avant_it      int  not null default 1,   -- 1 = la veille
  jours_avant_resto   int  not null default 0,   -- 0 = le jour même
  actif   boolean not null default true,
  depuis  date    not null default current_date  -- rien pour les mouvements antérieurs à l'installation
);
alter table public.lp24_mail_config add column if not exists emailjs_template text;
alter table public.lp24_mail_config add column if not exists jours_avant_it int not null default 1;
alter table public.lp24_mail_config add column if not exists jours_avant_resto int not null default 0;
alter table public.lp24_mail_config enable row level security;   -- clé privée invisible depuis l'appli

insert into public.lp24_mail_config(id, emailjs_service, emailjs_public_key, emailjs_private_key, emailjs_template)
values (1, 'service_i09ljga', 'n04JbAxmU3mf9UuXz', '<<CLE_PRIVEE_EMAILJS>>', '<<ID_DU_MODELE>>')
on conflict (id) do update set
  emailjs_service = excluded.emailjs_service, emailjs_public_key = excluded.emailjs_public_key,
  emailjs_private_key = excluded.emailjs_private_key,
  emailjs_template = excluded.emailjs_template;

-- ── Étape 3 : journal (un e-mail par personne et par type) ──
create table if not exists public.lp24_mails_auto(
  badge_id     bigint not null,
  type         text   not null,          -- it_arrivee | it_depart | resto_arrivee | resto_depart
  nom text, prenom text, date_evt date, destinataire text,
  envoye_le    timestamptz not null default now(),
  requete      bigint,
  primary key (badge_id, type)
);

-- ── Étape 4 : la fonction d'envoi ──
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
  cc := coalesce(st->>'ccEmails', '');

  for t in select * from (values
      ('it_arrivee',    'it',    true,  cfg.jours_avant_it),
      ('it_depart',     'it',    false, cfg.jours_avant_it),
      ('resto_arrivee', 'resto', true,  cfg.jours_avant_resto),
      ('resto_depart',  'resto', false, cfg.jours_avant_resto)) as v(type, cible, arr, avance)
  loop
    dest := nullif(trim(coalesce(st->>(case when t.cible = 'it' then 'itEmail' else 'restaurantEmail' end), '')), '');
    continue when dest is null;
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
          || 'Cordialement,' || E'\n' || 'Le responsable de site';
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

-- ── Étape 5 : tous les jours à 5 h UTC (7 h en été, 6 h en hiver à Paris) ──
select cron.unschedule('mail-depart-restaurant') where exists (select 1 from cron.job where jobname = 'mail-depart-restaurant');
select cron.unschedule('mails-automatiques')     where exists (select 1 from cron.job where jobname = 'mails-automatiques');
select cron.schedule('mails-automatiques', '0 5 * * *', $job$select public.envoyer_mails_auto();$job$);

-- ════════════════════════════════════════════════════════════════════
--  Utile :
--  • Envoyer tout de suite :          select public.envoyer_mails_auto();
--  • Voir les e-mails envoyés :       select * from public.lp24_mails_auto order by envoye_le desc;
--  • Réponses d'EmailJS :             select id, status_code, content from net._http_response order by id desc limit 10;
--  • IT 2 jours avant au lieu de 1 :  update public.lp24_mail_config set jours_avant_it = 2;
--  • Mettre en pause :                update public.lp24_mail_config set actif = false;
--  • Tout arrêter :                   select cron.unschedule('mails-automatiques');
-- ════════════════════════════════════════════════════════════════════
