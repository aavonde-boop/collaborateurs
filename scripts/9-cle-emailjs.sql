-- ════════════════════════════════════════════════════════════════════
--  NOUVELLES CLÉS EMAILJS — Gestion Collaborateurs
--  1. Dans EmailJS (Account → General → API keys), clique « Refresh Keys ».
--  2. Remplace ci-dessous COLLE_LA_PUBLIC_KEY et COLLE_LA_PRIVATE_KEY par les
--     2 nouvelles clés (en gardant les guillemets simples), puis « Run ».
--  La clé privée ne va QUE dans Supabase : ne l'envoie à personne.
-- ════════════════════════════════════════════════════════════════════
do $$
declare
  publique text := 'COLLE_LA_PUBLIC_KEY';
  privee   text := 'COLLE_LA_PRIVATE_KEY';
begin
  if publique like 'COLLE%' or privee like 'COLLE%' or length(trim(publique)) < 8 or length(trim(privee)) < 8 then
    raise exception 'Remplace d''abord COLLE_LA_PUBLIC_KEY et COLLE_LA_PRIVATE_KEY par les nouvelles clés';
  end if;
  if trim(publique) = 'n04JbAxmU3mf9UuXz' then
    raise exception 'C''est encore l''ancienne clé publique : clique d''abord « Refresh Keys » dans EmailJS';
  end if;
  update public.lp24_mail_config
     set emailjs_public_key = trim(publique), emailjs_private_key = trim(privee)
   where id = 1;
end $$;

select case when emailjs_public_key = 'n04JbAxmU3mf9UuXz' then 'NON : ancienne clé toujours en place'
            else 'oui : nouvelles clés enregistrées' end as resultat
from public.lp24_mail_config where id = 1;
