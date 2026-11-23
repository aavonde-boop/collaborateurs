-- ════════════════════════════════════════════════════════════════════
--  16 · Mails des badges de prêt : bon accueil + copie
--  • badge d'Hexagone : horaires et téléphone de l'accueil d'Hexagone
--    (badge de Levallois : rien ne change) ;
--  • le mail envoyé au moment du prêt part aussi aux adresses « en copie »
--    des Réglages (comme les rappels).
--  À lancer une fois dans Supabase → SQL Editor. Aucune donnée n'est modifiée.
-- ════════════════════════════════════════════════════════════════════

-- Horaires de l'accueil selon le site du badge
create or replace function public.lp24_horaires_site(p_site text) returns text
language sql stable security definer set search_path = public as $h$
  select case when p_site = 'Hexagone'
    then coalesce(nullif(btrim(public.lp24_reglages()->>'autoHorairesHexagone'), ''),
         E'Horaires de l''accueil d''Hexagone :\n• Du lundi au vendredi : de 7h00 à 18h00\nAccueil joignable au 02.99.42.73.00 pendant les horaires d''ouverture.')
    else public.lp24_texte('autoHoraires') end
$h$;

-- ── Mail au moment du prêt ──
create or replace function public.mail_pret_accueil() returns trigger
language plpgsql security definer set search_path = public, extensions as $fn$
declare cfg record; dest text; cc text; msg text; rid bigint;
begin
  dest := trim(coalesce(new.email_emprunteur, ''));
  if new.statut not in ('prete','empruntee') or new.pret_le is null
     or dest !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return new; end if;
  if exists (select 1 from public.lp24_mails_pret where badge_id = new.id and pret_le = new.pret_le) then return new; end if;
  select * into cfg from public.lp24_mail_config where id = 1;
  if cfg is null or not cfg.actif or cfg.emailjs_private_key like '<<%' then return new; end if;
  if coalesce(public.lp24_reglages()->>'envoiMails', 'true') = 'false' or coalesce(public.lp24_reglages()->>'envoiPret', 'true') = 'false' then return new; end if;
  cc := regexp_replace(coalesce(public.lp24_reglages()->>'ccEmails', ''), '\s*;\s*', ',', 'g');
  msg := public.lp24_remplir(public.lp24_texte('autoPret'), jsonb_build_object(
           'emprunteur', coalesce(initcap(lower(nullif(trim(new.emprunteur::text), ''))), ''),
           'code', coalesce(new.code::text, ''), 'badge_nom', coalesce(new.nom::text, ''),
           'date_pret', to_char(new.pret_le at time zone 'Europe/Paris', 'DD/MM/YYYY "à" HH24"h"MI'),
           'ligne_retour', coalesce('Retour prévu : ' || to_char(left(nullif(new.date_retour_prevu::text, ''), 10)::date, 'DD/MM/YYYY'), ''),
           'horaires', public.lp24_horaires_site(new.site), 'signature', public.lp24_texte('autoSignature')));
  rid := net.http_post(
    url     := 'https://api.emailjs.com/api/v1.0/email/send',
    body    := jsonb_build_object('service_id', cfg.emailjs_service, 'template_id', cfg.emailjs_template,
                 'user_id', cfg.emailjs_public_key, 'accessToken', cfg.emailjs_private_key,
                 'template_params', jsonb_build_object('to_email', dest, 'cc_email', cc,
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
declare cfg record; st jsonb; b record; cc text; msg text; quand text; rid bigint; n int := 0; tpl text; lr text;
begin
  select * into cfg from public.lp24_mail_config where id = 1;
  if cfg is null or not cfg.actif or cfg.emailjs_private_key like '<<%' then return 0; end if;
  if coalesce(public.lp24_reglages()->>'envoiMails', 'true') = 'false' or coalesce(public.lp24_reglages()->>'envoiRappel', 'true') = 'false' then return 0; end if;
  delete from public.lp24_relances_pret m using net._http_response r
   where r.id = m.requete and coalesce(r.status_code, 0) <> 200;
  st := public.lp24_reglages();
  cc := regexp_replace(coalesce(st->>'ccEmails', ''), '\s*;\s*', ',', 'g');
  for b in
    select * from public.badges_pret x
     where x.statut in ('prete','empruntee')
       and x.pret_le <= now() - interval '24 hours'
       -- Date de retour indiquée : pas de rappel avant le lendemain de cette date
       and not (left(coalesce(x.date_retour_prevu::text, ''), 10) ~ '^\d{4}-\d{2}-\d{2}$'
                and left(x.date_retour_prevu::text, 10)::date >= current_date)
       and trim(coalesce(x.email_emprunteur,'')) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
       and not exists (select 1 from public.lp24_relances_pret m
                        where m.badge_id = x.id and m.pret_le = x.pret_le and m.jour = current_date)
  loop
    quand := to_char(b.pret_le at time zone 'Europe/Paris', 'DD/MM/YYYY "à" HH24"h"MI');
    -- Date de retour prévue rappelée dans le mail (ajoutée avant les horaires si le texte personnalisé n'a pas {ligne_retour})
    lr := case when left(coalesce(b.date_retour_prevu::text, ''), 10) ~ '^\d{4}-\d{2}-\d{2}$'
               then 'Retour prévu : ' || to_char(left(b.date_retour_prevu::text, 10)::date, 'DD/MM/YYYY') else '' end;
    tpl := public.lp24_texte('autoRappel');
    if lr = '' then tpl := replace(tpl, E'\n{ligne_retour}', '');
    elsif position('{ligne_retour}' in tpl) = 0 then tpl := replace(tpl, '{horaires}', lr || E'\n\n{horaires}'); end if;
    msg := public.lp24_remplir(tpl, jsonb_build_object(
             'emprunteur', coalesce(initcap(lower(nullif(trim(b.emprunteur::text), ''))), ''),
             'code', coalesce(b.code::text, ''), 'badge_nom', coalesce(b.nom::text, ''), 'date_pret', quand, 'ligne_retour', lr,
             'horaires', public.lp24_horaires_site(b.site), 'signature', public.lp24_texte('autoSignature')));
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

-- Vérification : doit afficher « Installé »
select 'Installé' as resultat, public.lp24_horaires_site('Hexagone') as horaires_hexagone;
