-- ════════════════════════════════════════════════════════════════════
--  14 · Deuxième accueil : Hexagone
--  Projet jymobewqenhcjtzniytb → SQL Editor → Run. Peut être relancé sans risque.
--  • ajoute la colonne « site » aux badges de prêt, à leur historique et aux colis
--    (tout ce qui existe déjà reste à Levallois) ;
--  • crée les 51 badges de prêt d'Hexagone : visiteurs 1 à 10, AAG 1 à 13,
--    intérimaires 1 à 28 (ceux qui existent déjà ne sont pas recréés).
-- ════════════════════════════════════════════════════════════════════

alter table public.badges_pret       add column if not exists site text not null default 'Levallois';
alter table public.badges_pret_histo add column if not exists site text not null default 'Levallois';
alter table public.lp24_colis        add column if not exists site text not null default 'Levallois';

with liste(code, nom, ordre) as (
  select 'VIS-' || lpad(n::text, 2, '0'), 'Badge visiteur ' || n, n from generate_series(1, 10) n
  union all
  select 'AAG-' || lpad(n::text, 2, '0'), 'Badge AAG ' || n, 100 + n from generate_series(1, 13) n
  union all
  select 'INT-' || lpad(n::text, 2, '0'), 'Badge intérimaire ' || n, 200 + n from generate_series(1, 28) n
), a_creer as (
  select l.* from liste l
  where not exists (select 1 from public.badges_pret b where b.site = 'Hexagone' and b.code = l.code)
)
insert into public.badges_pret (id, code, nom, statut, emprunteur, date_emprunt, date_retour_prevu, commentaire, site)
select (select coalesce(max(id), 0) from public.badges_pret) + row_number() over (order by ordre),
       code, nom, 'disponible', '', '', '', '', 'Hexagone'
from a_creer;

-- Vérification : doit afficher 51 badges pour Hexagone
select site, count(*) as badges from public.badges_pret group by site order by site;
