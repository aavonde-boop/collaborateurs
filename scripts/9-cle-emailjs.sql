-- ════════════════════════════════════════════════════════════════════
--  NOUVELLE CLÉ PUBLIQUE EMAILJS — Gestion Collaborateurs
--  À lancer APRÈS avoir régénéré la clé publique dans EmailJS
--  (Account → General → API keys). Remplace COLLE_ICI_LA_NOUVELLE_CLE
--  par la nouvelle clé publique, en gardant les guillemets simples.
-- ════════════════════════════════════════════════════════════════════
update public.lp24_mail_config
   set emailjs_public_key = 'COLLE_ICI_LA_NOUVELLE_CLE'
 where id = 1 and 'COLLE_ICI_LA_NOUVELLE_CLE' not like 'COLLE%';

select case when emailjs_public_key like 'COLLE%' or emailjs_public_key = 'n04JbAxmU3mf9UuXz'
            then 'NON : ancienne clé toujours en place' else 'oui : nouvelle clé enregistrée' end as resultat
from public.lp24_mail_config where id = 1;
