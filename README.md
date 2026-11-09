-- ════════════════════════════════════════════════════════════════════
--  MAILS AUTOMATIQUES : MISE EN FORME PROPRE (Outlook) — Gestion Collaborateurs
--  À lancer une fois dans Supabase → SQL Editor (projet jymobewqenhcjtzniytb).
--  Peut être relancé sans risque. Ne touche à aucune donnée.
--
--  Avant : les mails arrivaient sur une seule ligne dans Outlook.
--  Après : paragraphes séparés, informations (Nom, Prénom, Date…) dans un
--  petit tableau, signature sur plusieurs lignes. Les textes modifiables
--  dans les Réglages restent les mêmes.
--  Concerne : mails IT et restaurant (veille / jour même), prêt de badge, rappels.
-- ════════════════════════════════════════════════════════════════════
create or replace function public.lp24_remplir(modele text, vars jsonb) returns text
language plpgsql stable as $r$
declare
  k text; v text; t text := coalesce(modele, '');
  para text; lignes text[]; l text; tableau boolean; corps text := '';
  police constant text := 'font-family:Calibri,Arial,sans-serif;';
  cel1 constant text := 'padding:7px 16px 7px 12px;border:1px solid #e5e7eb;background:#f5f7fa;font-family:Calibri,Arial,sans-serif;font-size:10.5pt;color:#6b7280;white-space:nowrap';
  cel2 constant text := 'padding:7px 16px 7px 12px;border:1px solid #e5e7eb;font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#111827;font-weight:bold';
begin
  for k, v in select key, value from jsonb_each_text(vars) loop
    t := replace(t, '{' || k || '}', coalesce(v, ''));
  end loop;
  t := replace(t, E'\r', '');
  t := regexp_replace(t, ' +\(\)', '', 'g');
  t := regexp_replace(t, 'Bonjour +,', 'Bonjour,', 'g');
  t := regexp_replace(t, E'\n[ \t]*\n([ \t]*\n)+', E'\n\n', 'g');
  -- texte → HTML (les caractères spéciaux sont neutralisés)
  t := replace(replace(replace(t, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
  foreach para in array regexp_split_to_array(btrim(t, E' \n\t'), E'\n[ \t]*\n') loop
    para := btrim(para, E' \n\t');
    continue when para = '';
    lignes := array(select btrim(x, E' \t') from unnest(string_to_array(para, E'\n')) x where btrim(x, E' \t') <> '');
    tableau := coalesce(array_length(lignes, 1), 0) >= 2;
    foreach l in array lignes loop
      if l !~ '^[^:]{1,30} : .' then tableau := false; end if;
    end loop;
    if tableau then
      corps := corps || '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin:2px 0 18px">';
      foreach l in array lignes loop
        corps := corps || '<tr><td style="' || cel1 || '">' || split_part(l, ' : ', 1) || '</td><td style="' || cel2 || '">'
                       || substr(l, length(split_part(l, ' : ', 1)) + 4) || '</td></tr>';
      end loop;
      corps := corps || '</table>';
    else
      corps := corps || '<p style="margin:0 0 12px;' || police || 'font-size:11pt;line-height:1.45;color:#1f2937">'
                     || replace(para, E'\n', '<br>') || '</p>';
    end if;
  end loop;
  return '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;max-width:620px"><tr><td style="'
         || police || 'font-size:11pt;line-height:1.45;color:#1f2937">' || corps || '</td></tr></table>';
end
$r$;

-- Aperçu : à quoi ressemble un mail IT d'arrivée
select public.lp24_remplir(
  E'Bonjour,\n\nNous vous informons de l''arrivée d''un nouveau collaborateur :\n\nNom : {nom}\nPrénom : {prenom}\nDate d''arrivée : {date}\nManager : {manager}\n\nCordialement,\nArnaud AVONDE\n07.85.42.37.24\nResponsable de site',
  '{"nom":"DUPONT","prenom":"Jean","date":"12/11/2026","manager":"LEROY THOMAS"}'::jsonb) as apercu_html;

-- Vérification : les 3 envois automatiques utilisent bien cette mise en forme (tout doit être « oui »)
select p.proname as envoi,
       case when p.prosrc like '%lp24_remplir%' then 'oui' else 'NON' end as "mise en forme appliquée"
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('envoyer_mails_auto','mail_pret_accueil','envoyer_relances_pret')
order by 1;
