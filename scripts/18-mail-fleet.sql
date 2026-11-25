-- ════════════════════════════════════════════════════════════════════
--  18 · Prêts de véhicules : mail à la boîte fleet
--  Quand la case « Envoyer à la boîte mail fleet » est cochée sur un prêt,
--  l'appli demande à la base d'envoyer le récapitulatif de l'attestation
--  à l'adresse fleet enregistrée dans le parking.
--  • le mail est construit ici, à partir du prêt enregistré (rien d'autre) ;
--  • il ne part QU'À l'adresse fleet du parking (pas n'importe où) ;
--  • réservé à l'administrateur et aux comptes « 🚗 Parking ».
--  À lancer une fois dans Supabase → SQL Editor. Ne touche à aucune donnée.
-- ════════════════════════════════════════════════════════════════════

create or replace function public.lp24_mail_pret_vehicule(p_id text) returns text
language plpgsql security definer set search_path = public, extensions as $f$
declare
  d jsonb; pr jsonb; dest text; sujet text; lignes text := ''; docs text := ''; r text[]; sig text; msg text;
  cel1 constant text := 'padding:7px 16px 7px 12px;border:1px solid #e5e7eb;background:#f5f7fa;font-family:Calibri,Arial,sans-serif;font-size:10.5pt;color:#6b7280;white-space:nowrap';
  cel2 constant text := 'padding:7px 16px 7px 12px;border:1px solid #e5e7eb;font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#111827;font-weight:bold';
  pst  constant text := 'margin:0 0 12px;font-family:Calibri,Arial,sans-serif;font-size:11pt;line-height:1.45;color:#1f2937';
  fr text;
begin
  if not public.lp24_acces_parking() then raise exception 'Accès réservé au parking'; end if;
  select data into d from public.lp24_parking where id = 1;
  dest := nullif(trim(coalesce(d->>'fleetEmail', '')), '');
  if dest is null or dest !~ '^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$' then raise exception 'Adresse fleet manquante ou invalide'; end if;
  select x into pr from jsonb_array_elements(coalesce(d->'prets', '[]'::jsonb)) x where x->>'id' = p_id;
  if pr is null then raise exception 'Prêt introuvable'; end if;

  foreach r slice 1 in array array[
      ['Véhicule', coalesce(pr->>'plaque', '') || coalesce(' — ' || nullif(pr->>'modele', ''), '')],
      ['Collaborateur', coalesce(pr->>'nom', '')],
      ['Matricule', coalesce(nullif(pr->>'matricule', ''), '—')],
      ['Demeurant', coalesce(pr->>'adresse', '')],
      ['Du', to_char((pr->>'du')::date, 'DD/MM/YYYY')],
      ['Au', to_char((pr->>'au')::date, 'DD/MM/YYYY')],
      ['À', coalesce(nullif(pr->>'heure', ''), '—')],
      ['Km au départ', coalesce(nullif(pr->>'km', ''), '—')]] loop
    lignes := lignes || '<tr><td style="' || cel1 || '">' || public.lp24_esc(r[1]) || '</td><td style="' || cel2 || '">' || public.lp24_esc(r[2]) || '</td></tr>';
  end loop;
  if (pr->'docs'->>'cg') = 'true' then docs := docs || '<li>La copie de carte grise du véhicule</li>'; end if;
  if (pr->'docs'->>'assur') = 'true' then docs := docs || '<li>La carte d''assurance</li>'; end if;
  if (pr->'docs'->>'carbu') = 'true' then docs := docs || '<li>La carte carburant</li>'; end if;
  if (pr->'docs'->>'critair') = 'true' then docs := docs || '<li>La vignette Crit''Air</li>'; end if;
  fr := to_char(((pr->>'cree')::timestamptz) at time zone 'Europe/Paris', 'DD/MM/YYYY à HH24:MI');
  sig := replace(public.lp24_esc(public.lp24_texte('autoSignature')), E'\n', '<br>');

  sujet := 'Prêt véhicule — ' || coalesce(pr->>'plaque', '') || ' — ' || coalesce(pr->>'nom', '')
        || ' — du ' || to_char((pr->>'du')::date, 'DD/MM/YYYY') || ' au ' || to_char((pr->>'au')::date, 'DD/MM/YYYY');
  msg := '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;max-width:640px"><tr><td style="font-family:Calibri,Arial,sans-serif;font-size:11pt;line-height:1.45;color:#1f2937">'
    || '<p style="' || pst || '">Bonjour,</p>'
    || '<p style="' || pst || '">Un véhicule de prêt vient d''être remis. L''<b>attestation d''attribution de véhicule de prêt</b> a été lue et signée électroniquement par le collaborateur le ' || fr || '.</p>'
    || '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin:2px 0 16px">' || lignes || '</table>'
    || case when docs <> '' then '<p style="' || pst || '"><b>Remis ce jour :</b></p><ul style="margin:0 0 14px 18px;padding:0;font-family:Calibri,Arial,sans-serif;font-size:11pt">' || docs || '</ul>' else '' end
    || '<p style="' || pst || '"><b>Le collaborateur s''est engagé :</b></p><ul style="margin:0 0 14px 18px;padding:0;font-family:Calibri,Arial,sans-serif;font-size:10.5pt;color:#374151">'
    || '<li>à informer immédiatement la Société de tout retrait de son permis de conduire, temporaire ou définitif ;</li>'
    || '<li>à gérer, en cas de panne, la communication et le suivi du dossier auprès de l''assistance et du garage jusqu''à la clôture du dossier ;</li>'
    || '<li>à prendre en charge tous procès-verbaux adressés à la Société (horodateur, FPS, stationnement interdit, excès de vitesse) ;</li>'
    || '<li>à informer la Société de tout événement survenant au véhicule dans les 48 heures.</li></ul>'
    || '<p style="margin:0 0 16px;font-family:Calibri,Arial,sans-serif;font-size:9.5pt;color:#6b7280">L''attestation signée (avec la signature) est conservée dans Gestion Collaborateurs → Parking &amp; véhicules → Prêts de véhicules' || coalesce(', enregistrée par ' || public.lp24_esc(nullif(pr->>'par', '')), '') || '.</p>'
    || '<p style="' || pst || '">Cordialement,<br>' || sig || '</p></td></tr></table>';

  perform public.lp24_envoyer(regexp_replace(dest, '\s*;\s*', ',', 'g'), '', sujet, msg, 'pret_vehicule');
  insert into public.historique(action, detail, user_email, ts)
  values ('Mail fleet', coalesce(pr->>'plaque', '') || ' — ' || coalesce(pr->>'nom', '') || ' → ' || dest, coalesce(public.lp24_email_appelant(), 'appli'), now());
  return dest;
end $f$;
revoke all on function public.lp24_mail_pret_vehicule(text) from public, anon;
grant execute on function public.lp24_mail_pret_vehicule(text) to authenticated;

-- Vérification : doit afficher « Installé »
select 'Installé' as resultat;
