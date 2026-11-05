-- Fase 3: funções do reinício. A execução única fica em supabase/maintenance/reset/.
begin;

-- Carreira reiniciada: o mundo já existe e o técnico escolhe clube pelas propostas da carreira.
alter table public.careers add column if not exists world_started boolean not null default false;

-- Legado do rank geral (pontos de antes do reinício) e resumo da carreira anterior.
create table if not exists public.career_legacy(
 career_id uuid primary key references public.careers(id) on delete cascade,
 legacy_points bigint not null,
 previous jsonb not null,
 created_at timestamptz not null default now());
alter table public.career_legacy enable row level security;
revoke all on public.career_legacy from anon,authenticated;

-- careers.club_id acompanha o clube do técnico (Home mostra este clube).
create or replace function public.cw_coach_career_club_trg() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if new.club_id is not null and new.status='employed' and (tg_op='INSERT' or new.club_id is distinct from old.club_id or new.status is distinct from old.status) then
  update public.careers set club_id=new.club_id where id=new.career_id and club_id is distinct from new.club_id;
 end if;
 return null;
end $$;
drop trigger if exists cw_coach_career_club on public.mgr_coach;
create trigger cw_coach_career_club after insert or update of club_id,status on public.mgr_coach for each row execute function public.cw_coach_career_club_trg();

-- Técnico começa desempregado num mundo novo (Brasil + Libertadores), sem clube.
create or replace function public.career_begin_unemployed(p_career uuid) returns uuid
language plpgsql security definer set search_path=public as $$
declare sid uuid;
begin
 perform 1 from public.careers where id=p_career for update;
 if exists(select 1 from public.career_seasons where career_id=p_career) then raise exception 'Carreira já tem mundo; reinicie antes';end if;
 update public.careers set club_id=null,world_started=true where id=p_career;
 insert into public.mgr_coach(career_id,status,club_id,unemployed_day,unemployed_season_no) values(p_career,'unemployed',null,0,1)
 on conflict(career_id) do update set status='unemployed',club_id=null,spell_id=null,unemployed_day=0,unemployed_season_no=1;
 -- sim_create_season exige um clube na carreira: um clube brasileiro provisório só durante a criação
 -- (a temporada do técnico desempregado fica sem clube; ver mgr_new_season_before_world).
 update public.careers set club_id=(select id from public.sim_clubs where region='BRA' order by strength desc,id limit 1) where id=p_career;
 sid:=public.mgr_new_season(p_career);
 update public.careers set club_id=null where id=p_career;
 update public.career_seasons set club_id=null where id=sid;
 perform public.cw_ensure(p_career);
 perform public.cw_runtime_ensure(p_career);
 perform public.mgr_msg(p_career,sid,0,'board','Um novo começo',
  'O futebol recomeçou com Brasil e Libertadores. Sua reputação, credibilidade e ranks continuam com você. '
  ||'Três clubes da Série A querem conversar: veja as propostas em Carreira > Propostas, com a força de cada time e o elenco. '
  ||'Recusar todas deixa você livre para se candidatar às vagas abertas.',null);
 return sid;
end $$;

-- Três propostas de clubes da Série A, pela faixa de reputação (posição por força no catálogo).
create table if not exists public.cw_reset_offer_bands(
 min_reputation numeric primary key,
 rank_from integer not null,
 rank_to integer not null);
insert into public.cw_reset_offer_bands values(55,1,8),(35,5,12),(0,9,14) on conflict do nothing;
alter table public.cw_reset_offer_bands enable row level security;
revoke all on public.cw_reset_offer_bands from anon,authenticated;

create or replace function public.career_reset_offers(p_career uuid) returns integer
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rep numeric;cred numeric;b public.cw_reset_offer_bands;w public.cw_world;cl record;pay bigint;budget bigint;n int:=0;
begin
 select reputation into rep from public.mgr_coach where career_id=p_career;
 select coalesce(credibility,65) into cred from public.cw_coach where career_id=p_career;
 select * into b from public.cw_reset_offer_bands where min_reputation<=coalesce(rep,25) order by min_reputation desc limit 1;
 select * into w from public.cw_world where career_id=p_career;
 for cl in select x.club_id from(
   select pa.club_id,row_number() over(order by c.strength desc,c.id) rk
   from public.season_participants pa join public.sim_clubs c on c.id=pa.club_id
   where pa.season_id=w.primary_season and pa.competition_id='brasileirao')x
  where x.rk between b.rank_from and b.rank_to
  order by public.cw_random(p_career::text||':reset-offer:'||x.club_id) limit 3 loop
  perform public.cw_materialize_club(p_career,cl.club_id);
  pay:=greatest(70,round(coalesce((select prestige from public.cw_clubs where career_id=p_career and club_id=cl.club_id),50)*2.5+cred));
  budget:=greatest(0,public.cw_available_budget(p_career,cl.club_id)-2*pay);
  insert into public.season_offers(career_id,season_id,from_club,kind,status,pitch,salary,contract_years,budget_guarantee,expires_on,expires_day,bonus_coins,context)
  values(p_career,w.primary_season,cl.club_id,'coach','pending',
   'Recomeço do futebol: queremos você no comando desde o primeiro dia da temporada.',pay,2,budget,w.today+30,w.elapsed_days+30,0,
   jsonb_build_object('source','reset'));
  n:=n+1;
 end loop;
 return n;
end $$;

commit;
