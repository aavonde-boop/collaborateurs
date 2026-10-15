-- ════════════════════════════════════════════════════════════════════
--  APERÇU : quels mails partiront DEMAIN MATIN ? (lecture seule, n'envoie rien)
--  À lancer dans Supabase → SQL Editor.
-- ════════════════════════════════════════════════════════════════════
with cfg as (select * from public.lp24_mail_config where id = 1),
st as (select (data::text)::jsonb j from public.lp24_settings where id = 1),
ref as (select current_date + 1 as j),                         -- demain
types(type, cible, arr) as (values
  ('it_arrivee','IT',true), ('it_depart','IT',false),
  ('resto_arrivee','Restaurant',true), ('resto_depart','Restaurant',false)),
mvt as (
  select t.type, t.cible, t.arr, b.id, b.prenom, b.nom, b.manager, b.serie,
         left((case when t.arr then b.date_entree else b.date_sortie_prevue end)::text,10)::date d
    from public.lp24_badges b cross join types t
   where coalesce((case when t.arr then b.date_entree else b.date_sortie_prevue end)::text,'') ~ '^\d{4}-\d{2}-\d{2}')
select '7 h' as heure, m.cible as destinataire,
       case when m.arr then 'Arrivée' else 'Départ' end as type,
       initcap(coalesce(m.prenom,'')) || ' ' || upper(coalesce(m.nom,'')) as collaborateur,
       to_char(m.d,'DD/MM/YYYY') as date,
       case when m.cible = 'IT' then coalesce(nullif(m.manager::text,''),'—') else coalesce(nullif(m.serie::text,''),'Non attribué') end as "manager / badge",
       case when m.cible = 'IT' then st.j->>'itEmail' else st.j->>'restaurantEmail' end as adresse
  from mvt m, cfg, st, ref
 where cfg.actif
   and m.d - (case when m.cible = 'IT' then cfg.jours_avant_it else cfg.jours_avant_resto end) <= ref.j
   and m.d >= cfg.depuis
   and not (not m.arr and m.d < ref.j - 7)
   and not (m.arr and m.d < ref.j)
   and not exists (select 1 from public.lp24_mails_auto x where x.badge_id = m.id and x.type = m.type)
union all
select '8 h', 'Emprunteur', 'Rappel badge de prêt',
       coalesce(p.emprunteur,'') || ' (' || p.code || ')',
       'prêté le ' || to_char(p.pret_le at time zone 'Europe/Paris','DD/MM/YYYY HH24"h"MI'), '—', p.email_emprunteur
  from public.badges_pret p, ref
 where extract(isodow from ref.j) <= 5
   and p.statut in ('prete','empruntee')
   and p.pret_le <= (ref.j + time '08:00') at time zone 'Europe/Paris' - interval '24 hours'
   and trim(coalesce(p.email_emprunteur,'')) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
order by 1, 2, 3;
