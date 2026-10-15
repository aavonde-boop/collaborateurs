-- ════════════════════════════════════════════════════════════════════
--  RAPPEL AUTOMATIQUE — BADGES DE PRÊT NON RENDUS — Gestion Collaborateurs
--  À lancer UNE FOIS dans Supabase → SQL Editor, APRÈS « mails-automatiques ».
--  (utilise les mêmes réglages EmailJS : rien à remplir)
--
--  • Ajoute l'e-mail de l'emprunteur aux badges de prêt (saisi ou repris de la base collaborateurs).
--  • La base note l'heure exacte de chaque prêt.
--  • Chaque matin (vers 8 h), si un badge est prêté depuis plus de 24 h et pas rendu,
--    un rappel part à l'emprunteur (personnes en copie des Réglages en copie).
--    Un rappel par jour maximum, jusqu'au retour du badge. Chaque envoi va dans l'Historique.
--  Aucune donnée existante n'est modifiée ou supprimée.
-- ════════════════════════════════════════════════════════════════════

-- ── Étape 1 : nouvelles colonnes ──
alter table public.badges_pret add column if not exists email_emprunteur text;
alter table public.badges_pret add column if not exists pret_le timestamptz;

-- Prêts déjà en cours : on part de la date d'emprunt connue, sinon de maintenant
update public.badges_pret
   set pret_le = case when coalesce(date_emprunt::text,'') ~ '^\d{4}-\d{2}-\d{2}'
                      then (left(date_emprunt::text,10)::date + time '09:00') at time zone 'Europe/Paris'
                      else now() end
 where statut in ('prete','empruntee') and pret_le is null;

-- ── Étape 2 : l'heure du prêt est notée automatiquement ──
create or replace function public.badges_pret_heure() returns trigger
language plpgsql as $fn$
begin
  if new.statut in ('prete','empruntee') then
    if tg_op = 'UPDATE' and old.statut in ('prete','empruntee')
       and upper(trim(coalesce(old.emprunteur,''))) = upper(trim(coalesce(new.emprunteur,''))) then
      new.pret_le := coalesce(old.pret_le, now());          -- même prêt : on garde l'heure d'origine
    elsif tg_op = 'INSERT' and new.pret_le is not null then
      null;                                                  -- (enregistrement depuis l'appli : tranché à la mise à jour)
    else
      new.pret_le := now();                                  -- nouveau prêt
    end if;
  else
    new.pret_le := null;                                     -- badge rendu
  end if;
  return new;
end
$fn$;
drop trigger if exists badges_pret_heure on public.badges_pret;
create trigger badges_pret_heure before insert or update on public.badges_pret
  for each row execute function public.badges_pret_heure();

-- ── Étape 3 : journal des rappels (un par prêt et par jour) ──
create table if not exists public.lp24_relances_pret(
  badge_id  bigint not null,
  pret_le   timestamptz not null,
  jour      date not null default current_date,
  destinataire text,
  requete   bigint,
  primary key (badge_id, pret_le, jour)
);

-- ── Étape 4 : la fonction d'envoi ──
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

-- ── Étape 5 : du lundi au vendredi à 6 h UTC (8 h en été, 7 h en hiver à Paris) ──
select cron.unschedule('relances-badges-pret') where exists (select 1 from cron.job where jobname = 'relances-badges-pret');
select cron.schedule('relances-badges-pret', '0 6 * * 1-5', $job$select public.envoyer_relances_pret();$job$);

-- ════════════════════════════════════════════════════════════════════
--  Utile :
--  • Envoyer les rappels tout de suite : select public.envoyer_relances_pret();
--  • Voir les rappels envoyés :         select * from public.lp24_relances_pret order by jour desc;
--  • Tous les jours (week-end compris) : select cron.schedule('relances-badges-pret', '0 6 * * *', $j$select public.envoyer_relances_pret();$j$);
--  • Tout arrêter :                     select cron.unschedule('relances-badges-pret');
-- ════════════════════════════════════════════════════════════════════
