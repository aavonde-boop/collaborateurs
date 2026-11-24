-- ════════════════════════════════════════════════════════════════════
--  17 · Parking & véhicules
--  • crée la table du parking (places + véhicules) ;
--  • accès réservé à l'administrateur et aux comptes cochés « 🚗 Parking »
--    dans Réglages → Comptes.
--  À lancer une fois dans Supabase → SQL Editor. Ne touche à aucune autre donnée.
-- ════════════════════════════════════════════════════════════════════

create table if not exists public.lp24_parking (
  id    int primary key default 1 check (id = 1),
  data  jsonb not null default '{"places":[],"vehicules":[]}'::jsonb,
  maj   timestamptz not null default now()
);
insert into public.lp24_parking (id) values (1) on conflict (id) do nothing;

-- Qui a le droit : administrateur, ou compte avec la case « Parking » cochée
create or replace function public.lp24_acces_parking() returns boolean
language plpgsql stable security definer set search_path = public as $f$
declare em text;
begin
  if coalesce(current_setting('request.jwt.claims', true), '') = '' then return true; end if;  -- SQL Editor
  em := public.lp24_email_appelant();
  return exists (
    select 1 from public.lp24_settings s,
           jsonb_array_elements(coalesce(public.lp24_json(s.data)->'users', '[]'::jsonb)) e
     where s.id = 1 and lower(trim(e->>'email')) = em
       and (e->>'role' = 'admin' or e->>'parking' = 'true'));
end $f$;

alter table public.lp24_parking enable row level security;
revoke all on public.lp24_parking from anon;
drop policy if exists "membres_appli" on public.lp24_parking;
drop policy if exists "parking" on public.lp24_parking;
create policy "parking" on public.lp24_parking for all to authenticated
  using ((select public.lp24_acces_parking())) with check ((select public.lp24_acces_parking()));
grant select, update on public.lp24_parking to authenticated;

-- Vérification : doit afficher « Installé »
select 'Installé' as resultat, jsonb_array_length(data->'places') as places from public.lp24_parking;
