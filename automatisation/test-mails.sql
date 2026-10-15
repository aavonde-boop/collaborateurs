-- ════════════════════════════════════════════════════════════════════
--  TEST : envoie les 5 mails types (avec un collaborateur fictif) à UNE adresse.
--  Aucun mail n'est envoyé à l'IT, au restaurant ou aux copies. Rien n'est enregistré.
--  À lancer dans Supabase → SQL Editor, APRÈS avoir modifié le modèle EmailJS.
-- ════════════════════════════════════════════════════════════════════
do $test$
declare
  adresse text := 'a.avonde@allianceautomotive.fr';
  cfg record; m record; n int := 0;
  sig text := E'\n\nCordialement,\nLe responsable de site';
begin
  select * into cfg from public.lp24_mail_config where id = 1;
  for m in select * from (values
    ('[TEST] Arrivée — Jean DUPONT — 16/10/2026  (mail IT, la veille)',
     E'Bonjour,\n\nNous vous informons de l''arrivée d''un nouveau collaborateur :\n\nNom : DUPONT\nPrénom : Jean\nDate d''arrivée : 16/10/2026\nManager : LEROY THOMAS\n\nMerci de créer les accès nécessaires.' || sig),
    ('[TEST] Départ — Jean DUPONT — 16/10/2026  (mail IT, la veille)',
     E'Bonjour,\n\nNous vous informons du départ du collaborateur suivant :\n\nNom : DUPONT\nPrénom : Jean\nDate de départ : 16/10/2026\nManager : LEROY THOMAS\n\nMerci de supprimer les accès.' || sig),
    ('[TEST] Arrivée — Jean DUPONT — 15/10/2026  (mail restaurant, le jour même)',
     E'Bonjour,\n\nNous vous informons de l''arrivée d''un nouveau collaborateur :\n\nNom : DUPONT\nPrénom : Jean\nDate d''arrivée : 15/10/2026\nNuméro de badge : 60FF1BC5\n\nMerci de bien vouloir l''ajouter à vos systèmes.' || sig),
    ('[TEST] Départ — Jean DUPONT — 15/10/2026  (mail restaurant, le jour même)',
     E'Bonjour,\n\nNous vous informons du départ du collaborateur suivant :\n\nNom : DUPONT\nPrénom : Jean\nDate de départ : 15/10/2026\nNuméro de badge : 60FF1BC5\n\nMerci de bien vouloir le retirer de vos systèmes.' || sig),
    ('[TEST] Field Support — Jean DUPONT  (notification envoyée par l''appli)',
     E'Bonjour,\n\nUne nouvelle demande Field Support a été enregistrée :\n\nNom : DUPONT\nPrénom : Jean\nSituation : Arrivée\nDate : 20/10/2026\nManager : LEROY THOMAS' || sig)
  ) as v(sujet, message)
  loop
    perform net.http_post(
      url     := 'https://api.emailjs.com/api/v1.0/email/send',
      body    := jsonb_build_object('service_id', cfg.emailjs_service, 'template_id', cfg.emailjs_template,
                   'user_id', cfg.emailjs_public_key, 'accessToken', cfg.emailjs_private_key,
                   'template_params', jsonb_build_object('to_email', adresse, 'cc_email', '', 'sujet', m.sujet, 'message', m.message)),
      headers := '{"Content-Type": "application/json"}'::jsonb);
    n := n + 1;
  end loop;
  raise notice '% mails de test envoyés à %', n, adresse;
end
$test$;

-- 10 secondes après, pour voir la réponse d'EmailJS (200 = envoyé) :
-- select id, status_code, content from net._http_response order by id desc limit 5;
