-- ════════════════════════════════════════════════════════════════════
--  TEXTE EN GRAS DANS LES MAILS — Gestion Collaborateurs
--  À lancer une fois dans Supabase → SQL Editor (projet jymobewqenhcjtzniytb).
--  Peut être relancé sans risque. Ne touche à aucune donnée.
--
--  Dans Réglages → Textes des mails, un texte entouré de ** (bouton B)
--  apparaît en gras dans les mails automatiques (IT, restaurant, prêts, rappels,
--  Field Support et mails de test).
-- ════════════════════════════════════════════════════════════════════
create or replace function public.lp24_gras(t text) returns text
language sql immutable as $f$ select regexp_replace(coalesce(t, ''), '\*\*([^*\n]+?)\*\*', '<b>\1</b>', 'g') $f$;

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
  t := public.lp24_gras(t);                           -- **texte** → gras
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
  sig := replace(public.lp24_gras(public.lp24_esc(public.lp24_texte('autoSignature'))), E'\n', '<br>');
  return '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;max-width:620px"><tr><td style="' || police || 'font-size:11pt;line-height:1.45;color:#1f2937">'
    || '<p style="' || pstyle || '">Bonjour,</p><p style="' || pstyle || '">Une nouvelle demande Field Support a été enregistrée :</p>'
    || '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin:2px 0 18px">' || lignes || '</table>'
    || '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin:0 0 6px"><tr><td style="background:#1E3A8A;border-radius:6px"><a href="' || url
    || '" style="display:inline-block;padding:9px 18px;' || police || 'font-size:11pt;font-weight:bold;color:#ffffff;text-decoration:none">Ouvrir la fiche dans l''application</a></td></tr></table>'
    || '<div style="' || police || 'font-size:9pt;color:#6b7280;margin:0 0 18px">Accès réservé aux utilisateurs habilités.</div>'
    || '<p style="' || pstyle || '">Cordialement,<br>' || sig || '</p></td></tr></table>';
end $f$;


-- Vérification : doit afficher « oui »
select case when public.lp24_remplir('Bonjour **{prenom}**', '{"prenom":"Jean"}'::jsonb) like '%<b>Jean</b>%' then 'oui' else 'NON' end as "gras dans les mails";
