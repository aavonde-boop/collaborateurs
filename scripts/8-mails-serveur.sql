-- ════════════════════════════════════════════════════════════════════
--  MAILS ENVOYÉS UNIQUEMENT PAR SUPABASE — Gestion Collaborateurs
--  À lancer une fois dans Supabase → SQL Editor (projet jymobewqenhcjtzniytb).
--  Peut être relancé sans risque. Ne touche à aucune donnée.
--
--  Avant : le mail Field Support et les mails de test partaient depuis le
--          navigateur, avec la clé EmailJS visible dans le code de l'appli.
--  Après : ils partent de Supabase (clé privée, jamais visible), comme les
--          mails de 6 h. L'appli n'a plus besoin d'EmailJS.
-- ════════════════════════════════════════════════════════════════════

-- ── Outils de mise en forme (mêmes styles que les autres mails)
create or replace function public.lp24_esc(t text) returns text
language sql immutable as $f$ select replace(replace(replace(coalesce(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;') $f$;

create or replace function public.lp24_nom_propre(t text) returns text
language sql immutable as $f$ select initcap(lower(trim(coalesce(t, '')))) $f$;

-- ── Contenu du mail Field Support
create or replace function public.lp24_message_fss(p_nom text, p_prenom text, p_situation text, p_date text, p_manager text, p_id bigint)
returns text language plpgsql stable set search_path = public as $f$
declare
  police constant text := 'font-family:Calibri,Arial,sans-serif;';
  pstyle constant text := 'margin:0 0 12px;font-family:Calibri,Arial,sans-serif;font-size:11pt;line-height:1.45;color:#1f2937';
  cel1 constant text := 'padding:7px 16px 7px 12px;border:1px solid #e5e7eb;background:#f5f7fa;font-family:Calibri,Arial,sans-serif;font-size:10.5pt;color:#6b7280;white-space:nowrap';
  cel2 constant text := 'padding:7px 16px 7px 12px;border:1px solid #e5e7eb;font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#111827;font-weight:bold';
  lib text; dfr text; url text; lignes text := ''; r text[]; sig text;
begin
  lib := case when p_situation ~* 'd[ée]part' then 'Date de départ' when p_situation ~* 'arriv' then 'Date d''arrivée' else 'Date' end;
  dfr := case when coalesce(p_date, '') ~ '^\d{4}-\d{2}-\d{2}' then to_char(left(p_date, 10)::date, 'DD/MM/YYYY') else coalesce(p_date, '') end;
  url := 'https://aavonde-boop.github.io/collaborateurs/' || coalesce('?fiche=' || p_id::text, '');
  foreach r slice 1 in array array[
      ['Nom', upper(coalesce(p_nom, ''))], ['Prénom', public.lp24_nom_propre(p_prenom)], ['Situation', coalesce(p_situation, '')],
      [lib, dfr], ['Manager', coalesce(nullif(trim(p_manager), ''), 'Non renseigné')]] loop
    lignes := lignes || '<tr><td style="' || cel1 || '">' || public.lp24_esc(r[1]) || '</td><td style="' || cel2 || '">'
                     || public.lp24_esc(coalesce(nullif(r[2], ''), '—')) || '</td></tr>';
  end loop;
  sig := replace(public.lp24_esc(public.lp24_texte('autoSignature')), E'\n', '<br>');
  return '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;max-width:620px"><tr><td style="' || police || 'font-size:11pt;line-height:1.45;color:#1f2937">'
    || '<p style="' || pstyle || '">Bonjour,</p><p style="' || pstyle || '">Une nouvelle demande Field Support a été enregistrée :</p>'
    || '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin:2px 0 18px">' || lignes || '</table>'
    || '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin:0 0 6px"><tr><td style="background:#1E3A8A;border-radius:6px"><a href="' || url
    || '" style="display:inline-block;padding:9px 18px;' || police || 'font-size:11pt;font-weight:bold;color:#ffffff;text-decoration:none">Ouvrir la fiche dans l''application</a></td></tr></table>'
    || '<div style="' || police || 'font-size:9pt;color:#6b7280;margin:0 0 18px">Accès réservé aux utilisateurs habilités.</div>'
    || '<p style="' || pstyle || '">Cordialement,<br>' || sig || '</p></td></tr></table>';
end $f$;

-- ── Envoi d'un mail par EmailJS avec la clé privée (jamais visible dans l'appli)
create or replace function public.lp24_envoyer(dest text, cc text, sujet text, message text, type_mail text) returns bigint
language plpgsql security definer set search_path = public, extensions as $f$
declare cfg record; rid bigint;
begin
  select * into cfg from public.lp24_mail_config where id = 1;
  if cfg is null or not cfg.actif or cfg.emailjs_private_key like '<<%' then return null; end if;
  rid := net.http_post(
    url     := 'https://api.emailjs.com/api/v1.0/email/send',
    body    := jsonb_build_object('service_id', cfg.emailjs_service, 'template_id', cfg.emailjs_template,
                 'user_id', cfg.emailjs_public_key, 'accessToken', cfg.emailjs_private_key,
                 'template_params', jsonb_build_object('to_email', dest, 'cc_email', coalesce(cc, ''), 'sujet', sujet, 'message', message)),
    headers := '{"Content-Type": "application/json"}'::jsonb);
  if to_regclass('public.lp24_mails_appli') is not null then
    insert into public.lp24_mails_appli(type, destinataire) values (type_mail, dest);
  end if;
  return rid;
end $f$;
revoke all on function public.lp24_envoyer(text, text, text, text, text) from public, anon, authenticated;

-- ── Mail Field Support : part tout seul à la création d'une fiche
create or replace function public.mail_fss_it() returns trigger
language plpgsql security definer set search_path = public, extensions as $f$
declare st jsonb; it text; fm text; dest text; cc text; sujet text;
begin
  -- seulement une vraie nouvelle fiche (pas une restauration d'anciennes fiches)
  if new.date_ajout is not null and left(new.date_ajout::text, 10) < to_char(current_date - 1, 'YYYY-MM-DD') then return new; end if;
  st := public.lp24_reglages();
  if coalesce(st->>'envoiMails', 'true') = 'false' or coalesce(st->>'envoiFSS', 'true') = 'false' then return new; end if;
  it := nullif(trim(coalesce(st->>'itEmail', '')), ''); fm := nullif(trim(coalesce(st->>'fssEmail', '')), '');
  dest := coalesce(it, fm);
  if dest is null then return new; end if;
  cc := case when it is not null and fm is not null and lower(fm) <> lower(it) then fm else '' end;
  sujet := 'Field Support — ' || public.lp24_nom_propre(new.prenom) || ' ' || upper(coalesce(new.nom, ''));
  perform public.lp24_envoyer(regexp_replace(dest, '\s*;\s*', ',', 'g'), regexp_replace(cc, '\s*;\s*', ',', 'g'), sujet,
            public.lp24_message_fss(new.nom, new.prenom, new.situation, new."dateEvt"::text, new.manager, new.id), 'field_support');
  insert into public.historique(action, detail, user_email, ts)
  values ('Mail Field Support', public.lp24_nom_propre(new.prenom) || ' ' || upper(coalesce(new.nom, '')) || ' → ' || dest, 'automatique', now());
  return new;
exception when others then
  return new;
end $f$;
drop trigger if exists mail_fss_it on public.lp24_fss;
create trigger mail_fss_it after insert on public.lp24_fss for each row execute function public.mail_fss_it();

-- ── Mails de test (Réglages → Tester les e-mails) : un appel par mail, réservé aux membres de l'appli
create or replace function public.lp24_envoyer_test(adresse text, numero int) returns text
language plpgsql security definer set search_path = public, extensions as $f$
declare
  d1 text := to_char(current_date + 1, 'DD/MM/YYYY'); d0 text := to_char(current_date, 'DD/MM/YYYY');
  p jsonb; sujet text; msg text; sig text := public.lp24_texte('autoSignature');
begin
  if not public.lp24_est_membre() then raise exception 'Réservé aux membres de l''appli'; end if;
  if coalesce(adresse, '') !~ '^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$' then raise exception 'Adresse e-mail invalide'; end if;
  p := jsonb_build_object('nom', 'DUPONT', 'prenom', 'Jean', 'manager', 'LEROY THOMAS', 'badge', '12345',
                          'email', 'jean.dupont@exemple.fr', 'signature', sig);
  case numero
    when 1 then sujet := '[TEST] Arrivée — Jean DUPONT — ' || d1 || '  (IT, la veille)';       msg := public.lp24_remplir(public.lp24_texte('autoITArrivee'), p || jsonb_build_object('date', d1));
    when 2 then sujet := '[TEST] Départ — Jean DUPONT — ' || d1 || '  (IT, la veille)';        msg := public.lp24_remplir(public.lp24_texte('autoITDepart'), p || jsonb_build_object('date', d1));
    when 3 then sujet := '[TEST] Arrivée — Jean DUPONT — ' || d0 || '  (restaurant)';          msg := public.lp24_remplir(public.lp24_texte('autoRestoArrivee'), p || jsonb_build_object('date', d0));
    when 4 then sujet := '[TEST] Départ — Jean DUPONT — ' || d0 || '  (restaurant)';           msg := public.lp24_remplir(public.lp24_texte('autoRestoDepart'), p || jsonb_build_object('date', d0));
    when 5 then sujet := '[TEST] Field Support — Jean DUPONT';                                  msg := public.lp24_message_fss('DUPONT', 'Jean', 'Arrivée', to_char(current_date + 5, 'YYYY-MM-DD'), 'LEROY THOMAS', null);
    when 6 then sujet := '[TEST] Badge de prêt P002 — horaires de l''accueil';
                msg := public.lp24_remplir(public.lp24_texte('autoPret'), jsonb_build_object('emprunteur', 'Jean Dupont', 'code', 'P002', 'badge_nom', 'Badge Prêt 2',
                         'date_pret', d0, 'ligne_retour', 'Retour prévu : ' || d1, 'horaires', public.lp24_texte('autoHoraires'), 'signature', sig));
    when 7 then sujet := '[TEST] Rappel — badge de prêt P002 à restituer';
                msg := public.lp24_remplir(public.lp24_texte('autoRappel'), jsonb_build_object('emprunteur', 'Jean Dupont', 'code', 'P002', 'badge_nom', 'Badge Prêt 2',
                         'date_pret', to_char(current_date - 3, 'DD/MM/YYYY'), 'ligne_retour', 'Retour prévu : ' || to_char(current_date - 1, 'DD/MM/YYYY'),
                         'horaires', public.lp24_texte('autoHoraires'), 'signature', sig));
    else raise exception 'Mail de test inconnu';
  end case;
  perform public.lp24_envoyer(adresse, '', sujet, msg, 'test');
  return sujet;
end $f$;
revoke all on function public.lp24_envoyer_test(text, int) from public, anon;
grant execute on function public.lp24_envoyer_test(text, int) to authenticated;

-- ── Vérification : tout doit être « oui »
select 'Mail Field Support envoyé par Supabase' as point,
       case when exists (select 1 from pg_trigger where tgname = 'mail_fss_it' and not tgisinternal) then 'oui' else 'NON' end as ok
union all
select 'Mails de test envoyés par Supabase',
       case when to_regprocedure('public.lp24_envoyer_test(text,integer)') is not null then 'oui' else 'NON' end
union all
select 'Clé EmailJS privée configurée',
       case when exists (select 1 from public.lp24_mail_config where id = 1 and actif and emailjs_private_key not like '<<%') then 'oui' else 'NON' end;
