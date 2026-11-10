-- ════════════════════════════════════════════════════════════════════
--  NOUVELLE CLÉ PUBLIQUE EMAILJS — Gestion Collaborateurs
--  À lancer APRÈS avoir régénéré la clé publique dans EmailJS.
--  Remplace COLLE_ICI_LA_NOUVELLE_CLE (ligne 8) par la nouvelle clé publique,
--  en gardant les guillemets simples, puis « Run ».
-- ════════════════════════════════════════════════════════════════════
do $$
declare cle text := 'COLLE_ICI_LA_NOUVELLE_CLE';
begin
  if cle like 'COLLE%' or length(trim(cle)) < 8 then
    raise exception 'Remplace d''abord COLLE_ICI_LA_NOUVELLE_CLE par la nouvelle clé publique';
  end if;
  update public.lp24_mail_config set emailjs_public_key = trim(cle) where id = 1;
end $$;

select case when emailjs_public_key = 'n04JbAxmU3mf9UuXz' then 'NON : ancienne clé toujours en place'
            else 'oui : nouvelle clé enregistrée' end as resultat
from public.lp24_mail_config where id = 1;
