-- Gerado por scripts/build-elenco-release.mjs: evoluções 31 (avanço rápido) e 32 (satisfação, contratos, limite de elenco).
-- Cole tudo no SQL Editor do Supabase e execute de uma vez. É uma transação única: qualquer erro desfaz tudo.
-- Pode ser executado de novo sem duplicar nada. A manutenção (public/maintenance.json e o hook da API) não é alterada.
-- Garantia: ao final, compara carreiras, carteiras, resultados, partidas ao vivo, elencos, contratos e caixas com o
-- estado de antes; se qualquer dado de usuário mudar, a transação inteira é desfeita.
begin;
set local statement_timeout='120s';
set local lock_timeout='10s';
select pg_advisory_xact_lock(hashtext('elenco-contratos-v32'));
do $preflight$ begin
 if to_regclass('public.cw_world') is null or to_regprocedure('public.career_world_advance(integer,uuid)') is null
    or to_regprocedure('public.career_player_search(text,text,text,text,bigint,integer,text)') is null then
  raise exception 'Instale antes a carreira completa (supabase/releases/carreira_completa.sql, evoluções 24–30)';
 end if;
 if to_regprocedure('public.mgr_squad(text)') is null or to_regprocedure('public.mgr_match_payload(bigint,integer)') is null
    or to_regprocedure('public.career_news(bigint)') is null or to_regprocedure('public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid)') is null
    or to_regprocedure('public.cw_register_transfer(uuid)') is null then
  raise exception 'Funções esperadas da carreira completa não encontradas; nada foi alterado';
 end if;
end $preflight$;
create temp table v32_careers on commit drop as select id,to_jsonb(c) as original from public.careers c;
create temp table v32_results on commit drop as select id,to_jsonb(f) as original from public.season_fixtures f where status='played';
create temp table v32_live on commit drop as select fixture_id,to_jsonb(m) as original from public.mgr_matches m where status='live';
create temp table v32_squads on commit drop as select career_id,player_id,to_jsonb(p) as original from public.mgr_players p;
create temp table v32_contracts on commit drop as select id,to_jsonb(c) as original from public.cw_contracts c;
create temp table v32_clubs on commit drop as select career_id,club_id,to_jsonb(c) as original from public.cw_clubs c;
create temp table v32_morale on commit drop as select career_id,player_id,morale,transfer_requested,promised_role from public.cw_players;

-- ===================== evolução 31 =====================
create or replace function public.cw_step_day(p_career uuid)
returns date language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;
begin
 select * into w from public.cw_world where career_id=p_career for update;
 if w.needs_sync then raise exception 'Conclua a atualização do calendário antes de avançar outro dia';end if;
 if exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 update public.cw_world set today=today+1,elapsed_days=elapsed_days+1,last_services_on=null,needs_sync=true where career_id=p_career returning * into w;
 update public.career_seasons set day_no=w.elapsed_days where career_id=p_career and status='active' and mode in('coach','world');
 update public.mgr_players set condition=least(100,condition+4.3),rhythm=greatest(35,rhythm-.4),
  injury=case when injured_until<=w.elapsed_days then null else injury end,
  injured_until=case when injured_until<=w.elapsed_days then null else injured_until end
  where career_id=p_career and (condition<100 or rhythm is distinct from 35 or injured_until is not null or injury is not null);
 perform public.cw_finance_tick(p_career);
 perform public.cw_market_tick(p_career);
 perform public.cw_jobs_tick(p_career);
 update public.cw_world set last_services_on=w.today where career_id=p_career;
 return w.today;
end $$;
revoke all on function public.cw_step_day(uuid) from public,anon,authenticated,service_role;

create or replace function public.career_world_advance(p_days int,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;w public.cw_world;c public.mgr_coach;prev jsonb;days int:=0;n int:=0;t timestamptz:=clock_timestamp();sid uuid;summary jsonb;stopped boolean;ready boolean;s public.career_seasons;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'world_advance');if prev is not null then return prev;end if;
 if p_days is null or (p_days<0 or p_days>(select max_days_per_call from public.cw_rules)) then raise exception 'Quantidade de dias acima do limite por atualização';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 loop
  n:=n+public.cw_simulate_due(car.id,12);select * into w from public.cw_world where career_id=car.id;select * into c from public.mgr_coach where career_id=car.id;
  select * into s from public.career_seasons where id=w.primary_season;
  exit when w.needs_sync or days>=p_days or clock_timestamp()-t>interval '1200 milliseconds';
  exit when s.status='finished' and w.today>=public.cw_start(s.region,s.year+1);
  exit when exists(select 1 from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id where f.season_id=w.primary_season and f.status='pending' and c.club_id in(f.home_club,f.away_club) and fd.due_on<=w.today);
  perform public.cw_step_day(car.id);days:=days+1;
 end loop;
 if not exists(select 1 from public.season_fixtures where season_id=w.primary_season and status='pending') and(select status from public.career_seasons where id=w.primary_season)='active' then summary:=public.mgr_season_end(w.primary_season);end if;
 select exists(select 1 from public.season_fixtures f join public.cw_fixture_dates fd on fd.fixture_id=f.id where f.season_id=w.primary_season and f.status='pending' and c.club_id in(f.home_club,f.away_club) and fd.due_on<=w.today) into stopped;
 select cs.status='finished' and w.today>=public.cw_start(cs.region,cs.year+1) into ready from public.career_seasons cs where cs.id=w.primary_season;
 return public.econ_request_save(car.id,p_request,'world_advance',jsonb_build_object('today',w.today,'days',days,'days_remaining',greatest(0,p_days-days),'stopped_for_match',stopped,'next_season_ready',ready,'matches',n,'more',w.needs_sync,'rounds','[]'::jsonb,'offers','[]'::jsonb,'season_finished',summary is not null,'season_summary',summary));
end $$;
revoke all on function public.career_world_advance(int,uuid) from public,anon,service_role;
grant execute on function public.career_world_advance(int,uuid) to authenticated;
notify pgrst,'reload schema';

-- ===================== evolução 32 =====================
alter table public.cw_players add column if not exists shirt_number smallint check(shirt_number between 1 and 99);
alter table public.cw_players add column if not exists transfer_listed boolean not null default false;
-- Inspirado nas listas de inscrição reais (Premier League: 25 adultos + sub-21 livres). Os elencos do jogo
-- têm em média ~29 adultos, então o padrão é 30 com 21 anos ou mais; sub-21 não contam. Configurável em cw_rules.rules.
update public.cw_rules set rules=rules||'{"squad_limit":30,"squad_limit_age":21}'::jsonb where not(rules ? 'squad_limit');

do $$ begin
 if to_regprocedure('public.mgr_squad_before_v32(text)') is null then alter function public.mgr_squad(text) rename to mgr_squad_before_v32;end if;
 if to_regprocedure('public.mgr_match_payload_before_v32(bigint,integer)') is null then alter function public.mgr_match_payload(bigint,int) rename to mgr_match_payload_before_v32;end if;
 if to_regprocedure('public.career_news_before_v32(bigint)') is null then alter function public.career_news(bigint) rename to career_news_before_v32;end if;
 if to_regprocedure('public.career_player_search_before_v32(text,text,text,text,bigint,integer,text)') is null then alter function public.career_player_search(text,text,text,text,bigint,int,text) rename to career_player_search_before_v32;end if;
 if to_regprocedure('public.career_transfer_bid_before_v32(text,bigint,integer,bigint,boolean,uuid)') is null then alter function public.career_transfer_bid(text,bigint,int,bigint,boolean,uuid) rename to career_transfer_bid_before_v32;end if;
 if to_regprocedure('public.cw_register_transfer_before_v32(uuid)') is null then alter function public.cw_register_transfer(uuid) rename to cw_register_transfer_before_v32;end if;
end $$;

-- ---------- regras auxiliares ----------
create or replace function public.cw_age(p_career uuid,p_player text)
returns int language sql stable security definer set search_path=public as $$
 select cp.age_at_start+floor((w.today-w.started_on)/365.25)::int from public.cw_players cp join public.cw_world w on w.career_id=cp.career_id
 where cp.career_id=p_career and cp.player_id=p_player
$$;
create or replace function public.cw_squad_limit()
returns int language sql stable security definer set search_path=public as $$select coalesce((rules->>'squad_limit')::int,30) from public.cw_rules$$;
-- Atletas que contam no limite: contratados pelo clube, com 21 anos ou mais.
create or replace function public.cw_squad_count(p_career uuid,p_club text)
returns int language sql stable security definer set search_path=public as $$
 select count(*)::int from public.mgr_players mp join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
 join public.cw_world w on w.career_id=mp.career_id
 where mp.career_id=p_career and mp.club_id=p_club
  and cp.age_at_start+floor((w.today-w.started_on)/365.25)::int>=coalesce((select (rules->>'squad_limit_age')::int from public.cw_rules),21)
$$;
-- Satisfação → rendimento individual: abaixo de 45 cai até -12% (0 de moral); acima de 80 sobe até +3%.
create or replace function public.cw_morale_factor(p_morale numeric)
returns numeric language sql immutable as $$
 select case when p_morale<45 then 1-(45-p_morale)/45*.12 when p_morale>80 then 1+(p_morale-80)/20*.03 else 1 end
$$;
create or replace function public.cw_shirt_number(p_career uuid,p_player text)
returns int language sql stable security definer set search_path=public as $$
 select coalesce(cp.shirt_number,sp.shirt_number) from public.sim_players sp left join public.cw_players cp on cp.career_id=p_career and cp.player_id=sp.id where sp.id=p_player
$$;

-- ---------- desempenho: aplicado quando o atleta entra na súmula (titular ou banco) ----------
create or replace function public.cw_morale_perf_trg()
returns trigger language plpgsql security definer set search_path=public as $$
declare car uuid;f numeric;
begin
 select career_id into car from public.mgr_matches where fixture_id=new.fixture_id;
 if car is null then return new;end if;
 select public.cw_morale_factor(morale) into f from public.cw_players where career_id=car and player_id=new.player_id;
 if f is null or f=1 then return new;end if;
 new.c_att:=round(new.c_att*f,2);new.c_cre:=round(new.c_cre*f,2);new.c_def:=round(new.c_def*f,2);new.c_ctl:=round(new.c_ctl*f,2);
 new.c_gk:=round(new.c_gk*f,2);new.c_fin:=round(new.c_fin*f,2);new.c_head:=round(new.c_head*f,2);new.c_pace:=round(new.c_pace*f,2);
 new.c_tack:=round(new.c_tack*f,2);new.c_str:=round(new.c_str*f,2);
 return new;
end $$;
drop trigger if exists cw_morale_perf on public.mgr_match_players;
create trigger cw_morale_perf before insert on public.mgr_match_players for each row execute function public.cw_morale_perf_trg();

-- ---------- número de camisa no novo clube (a carta acompanha o atleta) ----------
create or replace function public.cw_assign_number(p_career uuid,p_player text,p_club text)
returns int language plpgsql security definer set search_path=public as $$
declare used int[];pos text;wanted int;n int;
begin
 if p_club is null or not exists(select 1 from public.cw_players where career_id=p_career and player_id=p_player) then return null;end if;
 select array_agg(public.cw_shirt_number(p_career,mp.player_id)) into used from public.mgr_players mp
  where mp.career_id=p_career and mp.club_id=p_club and mp.player_id<>p_player;
 used:=coalesce(used,'{}');
 select position,shirt_number into pos,wanted from public.sim_players where id=p_player;
 if wanted is not null and not wanted=any(used) then n:=wanted;
 else
  select x into n from unnest(case when pos='GOL' then array[1,12,23,40,99] else array[]::int[] end||array(select generate_series(2,99))) x
   where x is not null and not x=any(used) and (pos='GOL' or x not in(1,12)) limit 1;
 end if;
 update public.cw_players set shirt_number=n where career_id=p_career and player_id=p_player;
 return n;
end $$;
create or replace function public.cw_club_change_trg()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.club_id is distinct from old.club_id then
  update public.cw_players set transfer_listed=false where career_id=new.career_id and player_id=new.player_id and transfer_listed;
  if new.club_id is not null then perform public.cw_assign_number(new.career_id,new.player_id,new.club_id);end if;
 end if;
 return null;
end $$;
-- Carreiras novas: atleta sem número na fonte recebe um número livre ao entrar no mundo.
create or replace function public.cw_player_number_trg()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.shirt_number is null and (select shirt_number from public.sim_players where id=new.player_id) is null then
  perform public.cw_assign_number(new.career_id,new.player_id,(select club_id from public.mgr_players where career_id=new.career_id and player_id=new.player_id));
 end if;
 return null;
end $$;
drop trigger if exists cw_player_number on public.cw_players;
create trigger cw_player_number after insert on public.cw_players for each row execute function public.cw_player_number_trg();
drop trigger if exists cw_club_change on public.mgr_players;
create trigger cw_club_change after update of club_id on public.mgr_players for each row execute function public.cw_club_change_trg();

-- Patch de números em listas de atletas já montadas (elenco, partida, busca).
create or replace function public.cw_patch_players(p_career uuid,p_list jsonb,p_extra boolean default false)
returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(case when cp.player_id is null then e else e||jsonb_build_object('number',coalesce(cp.shirt_number,(e->>'number')::int))||
  case when p_extra then jsonb_build_object('morale',round(cp.morale),'transfer_requested',cp.transfer_requested,'transfer_listed',cp.transfer_listed,
   'promised_role',cp.promised_role,'age',cp.age_at_start+floor((w.today-w.started_on)/365.25)::int,
   'contract_expires',ct.expires_on,'monthly_salary',ct.monthly_salary,
   'precontract',exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cp.player_id and n.status='precontract' and n.buyer_club is distinct from (e->>'club_id')))
  else '{}'::jsonb end end order by o),'[]'::jsonb)
 from jsonb_array_elements(coalesce(p_list,'[]')) with ordinality x(e,o)
 left join public.cw_players cp on cp.career_id=p_career and cp.player_id=e->>'id'
 left join public.cw_world w on w.career_id=p_career
 left join public.cw_contracts ct on ct.career_id=p_career and ct.player_id=cp.player_id and ct.status='active'
$$;
create or replace function public.cw_current_career()
returns uuid language sql stable security definer set search_path=public as $$select id from public.careers where user_id=auth.uid() and status='active'$$;

create or replace function public.mgr_squad(p_club text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;car uuid:=public.cw_current_career();club text;
begin
 r:=public.mgr_squad_before_v32(p_club);
 if not exists(select 1 from public.cw_world where career_id=car) then return r;end if;
 club:=r->>'club_id';
 return r||jsonb_build_object('players',public.cw_patch_players(car,r->'players',true),
  'squad',jsonb_build_object('limit',public.cw_squad_limit(),'count',public.cw_squad_count(car,club),'age',coalesce((select (rules->>'squad_limit_age')::int from public.cw_rules),21)));
end $$;
create or replace function public.mgr_match_payload(p_fixture bigint,p_after_seq int)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r jsonb:=public.mgr_match_payload_before_v32(p_fixture,p_after_seq);car uuid;
begin
 select career_id into car from public.mgr_matches where fixture_id=p_fixture;
 if r is null or not exists(select 1 from public.cw_world where career_id=car) then return r;end if;
 return r||jsonb_build_object('players',public.cw_patch_players(car,r->'players'));
end $$;
create or replace function public.career_player_search(p_query text default '',p_position text default '',p_region text default '',p_club text default '',p_max_value bigint default null,p_page int default 0,p_country text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb:=public.career_player_search_before_v32(p_query,p_position,p_region,p_club,p_max_value,p_page,p_country);car uuid:=public.cw_current_career();
begin
 return coalesce((select jsonb_agg(e||jsonb_build_object('number',public.cw_shirt_number(car,e->>'id'),
   'transfer_listed',(select transfer_listed from public.cw_players where career_id=car and player_id=e->>'id')) order by o) from jsonb_array_elements(r) with ordinality x(e,o)),'[]');
end $$;
-- Notícias com a carta real do atleta (nome, número, posição e nota), em vez de montar a carta pelo título.
create or replace function public.career_news(p_before bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb:=public.career_news_before_v32(p_before);car uuid:=public.cw_current_career();
begin
 return coalesce((select jsonb_agg(case when e->>'player_id' is null then e else e||jsonb_build_object('player',(
   select jsonb_build_object('id',sp.id,'name',sp.full_name,'short_name',sp.short_name,'position',sp.position,'nationality',sp.nationality,
    'number',public.cw_shirt_number(car,sp.id),'club_id',mp.club_id,'overall',round(pr.rating))
   from public.sim_players sp left join public.mgr_players mp on mp.career_id=car and mp.player_id=sp.id
   left join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position where sp.id=e->>'player_id')) end order by o)
  from jsonb_array_elements(r) with ordinality x(e,o)),'[]');
end $$;

-- ---------- limite de elenco ----------
create or replace function public.career_transfer_bid(p_player text,p_fee bigint,p_installments int,p_bonus bigint,p_precontract boolean,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car uuid:=public.cw_current_career();own text;lim int:=public.cw_squad_limit();cnt int;incoming int;
begin
 select club_id into own from public.mgr_coach where career_id=car and status='employed';
 if own is not null and coalesce(public.cw_age(car,p_player),0)>=coalesce((select (rules->>'squad_limit_age')::int from public.cw_rules),21)
    and public.econ_request_get(car,p_request,'transfer_bid') is null then
  cnt:=public.cw_squad_count(car,own);
  select count(*) into incoming from public.cw_negotiations n where n.career_id=car and n.buyer_club=own and n.initiator<>'renewal' and n.status in('agreed','precontract')
   and coalesce(public.cw_age(car,n.player_id),0)>=21;
  if cnt+incoming>=lim then raise exception 'Elenco cheio: % de % atletas com 21 anos ou mais. Venda ou libere alguém antes de contratar (sub-21 não contam).',cnt+incoming,lim;end if;
 end if;
 return public.career_transfer_bid_before_v32(p_player,p_fee,p_installments,p_bonus,p_precontract,p_request);
end $$;
-- No registro o limite é conferido de novo (duas compras podem fechar ao mesmo tempo).
create or replace function public.cw_register_transfer(p_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare n public.cw_negotiations;own text;d date;
begin
 select * into n from public.cw_negotiations where id=p_id;
 select club_id into own from public.mgr_coach where career_id=n.career_id and status='employed';
 select today into d from public.cw_world where career_id=n.career_id;
 if n.status in('agreed','precontract') and n.buyer_club=own and n.initiator<>'renewal' and n.register_on<=d
    and (select club_id from public.mgr_players where career_id=n.career_id and player_id=n.player_id) is distinct from own
    and coalesce(public.cw_age(n.career_id,n.player_id),0)>=coalesce((select (rules->>'squad_limit_age')::int from public.cw_rules),21)
    and public.cw_squad_count(n.career_id,own)>=public.cw_squad_limit() then
  perform public.cw_neg_close(n.id,'cancelled','Elenco cheio no momento do registro. Venda ou libere um atleta e negocie de novo.');
  perform public.cw_news_add(n.career_id,'squad-full:'||n.id,'squad','Registro recusado: elenco cheio',
   public.mgr_player_name(n.player_id)||' não pôde ser inscrito. O limite é de '||public.cw_squad_limit()||' atletas com 21 anos ou mais.',95,own,n.player_id);
  return false;
 end if;
 return public.cw_register_transfer_before_v32(p_id);
end $$;

-- ---------- lista de transferências e rescisão ----------
create or replace function public.career_player_list(p_player text,p_listed boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car public.careers;own text;
begin
 car:=public.mgr_lock();select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 if own is null or not exists(select 1 from public.mgr_players where career_id=car.id and player_id=p_player and club_id=own) then raise exception 'Atleta fora do seu elenco';end if;
 update public.cw_players set transfer_listed=coalesce(p_listed,false) where career_id=car.id and player_id=p_player;
 return jsonb_build_object('ok',true,'listed',coalesce(p_listed,false));
end $$;
-- Rescisão: paga até seis salários restantes (acordo de saída) e o atleta fica livre no mercado.
create or replace function public.career_player_release(p_player text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car public.careers;own text;ct public.cw_contracts;d date;prev jsonb;months int;cost bigint;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'player_release');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';select today into d from public.cw_world where career_id=car.id;
 select * into ct from public.cw_contracts where career_id=car.id and player_id=p_player and club_id=own and status='active' for update;
 if not found then raise exception 'Atleta fora do seu elenco';end if;
 if exists(select 1 from public.cw_negotiations where career_id=car.id and player_id=p_player and status in('agreed','precontract')) then raise exception 'O atleta já tem uma transferência acertada';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 months:=greatest(1,least(6,ceil((ct.expires_on-d)/30.0)::int));cost:=ct.monthly_salary*months+ct.arrears;
 perform public.cw_cash(car.id,own,-cost,'player_release',ct.id::text,'Rescisão de contrato de '||public.mgr_player_name(p_player));
 update public.cw_contracts set status='ended',ended_on=d,arrears=0 where id=ct.id;
 update public.mgr_players set club_id=null where career_id=car.id and player_id=p_player;
 perform public.cw_prune_lineups(car.id,p_player);
 update public.cw_negotiations set status='cancelled',response='O atleta deixou o clube.' where career_id=car.id and player_id=p_player and status in('seller_review','club_pending','club_counter','player_pending','player_counter');
 perform public.cw_news_add(car.id,'release:'||p_player||':'||d,'contract',public.mgr_player_name(p_player)||' tem contrato rescindido',
  'O atleta deixa '||public.mgr_club_name(own)||' e está livre no mercado. Custo da rescisão: '||cost||' moedas.',85,own,p_player);
 return public.econ_request_save(car.id,p_request,'player_release',jsonb_build_object('ok',true,'cost',cost));
end $$;

-- ---------- serviços diários ----------
-- 1) Atletas listados (ou que pediram para sair) recebem propostas de clubes com orçamento e vaga no elenco.
-- 2) Contratos nos seis meses finais: clubes oferecem pré-contrato e o atleta sai de graça se não renovar.
-- 3) Clube à beira da falência: aviso e demissão por irresponsabilidade financeira.
create or replace function public.cw_v32_tick(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d date;own text;p record;buyer text;value bigint;nid uuid;ct public.cw_contracts;club public.cw_clubs;spell_start date;lim int:=public.cw_squad_limit();
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 -- 1) venda dos listados
 if own is not null and public.cw_window_open(public.cw_region(own),d) then
  for p in select cp.player_id,cp.transfer_listed,ct.id as contract_id,ct.monthly_salary from public.cw_players cp join public.mgr_players mp using(career_id,player_id)
    join public.cw_contracts ct on ct.career_id=cp.career_id and ct.player_id=cp.player_id and ct.status='active'
    where cp.career_id=p_career and mp.club_id=own and (cp.transfer_listed or cp.transfer_requested)
     and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cp.player_id and n.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
     and random()<case when cp.transfer_listed then .12 else .05 end loop
   value:=public.cw_player_value(p_career,p.player_id);
   -- amostra de clubes com caixa (o orçamento livre completo só é calculado para a amostra)
   select c.club_id into buyer from (select z.* from public.cw_clubs z where z.career_id=p_career and z.club_id<>own and z.financial_risk<75 and z.cash-z.debt>value*1.3
     order by random() limit 30) c
    where public.cw_available_budget(p_career,c.club_id)>value*1.1 and public.cw_squad_count(p_career,c.club_id)<lim+6
    order by (public.cw_region(c.club_id)=public.cw_region(own)) desc,random() limit 1;
   if buyer is null then continue;end if;
   insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
    values(p_career,p.player_id,own,buyer,'ai','seller_review',round(value*(case when p.transfer_listed then .85 else .95 end+random()*.25)),
     greatest(40,ceil(p.monthly_salary*1.1)),3,ceil(value*.02),d,d+2,public.cw_deadline(d),value,p.contract_id) returning id into nid;
   begin perform public.cw_reserve_offer(nid);exception when raise_exception then perform public.cw_neg_close(nid,'failed_funds',sqlerrm);continue;end;
   perform public.cw_neg_history(nid,'buyer','Proposta por atleta disponível para venda.');
   perform public.cw_news_add(p_career,'incoming:'||nid,'transfer',public.mgr_club_name(buyer)||' faz proposta por '||public.mgr_player_name(p.player_id),
    'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.player_id);
  end loop;
 end if;
 -- 2) pré-contratos (dias 1 e 15): o atleta sem renovação assina com outro clube e sai de graça no fim do vínculo
 if extract(day from d) in(1,15) then
  for ct in select x.* from public.cw_contracts x where x.career_id=p_career and x.status='active' and x.expires_on between d and d+180
   and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and n.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
   and random()<case when x.club_id=own then .35 else .12 end
   order by (x.club_id=own) desc,random() limit 25 loop
   value:=public.cw_player_value(p_career,ct.player_id);
   select c.club_id into buyer from (select z.* from public.cw_clubs z where z.career_id=p_career and z.club_id is distinct from ct.club_id and z.club_id is distinct from own
     and z.financial_risk<75 and z.cash-z.debt>ct.monthly_salary*8 order by random() limit 30) c
    order by abs(c.prestige-coalesce((select prestige from public.cw_clubs z where z.career_id=p_career and z.club_id=ct.club_id),c.prestige)) limit 1;
   if buyer is null or public.cw_squad_count(p_career,buyer)>=lim+6 then continue;end if;
   -- Atleta satisfeito tende a esperar a renovação do clube atual.
   if (select morale from public.cw_players where career_id=p_career and player_id=ct.player_id)>=70 and random()<.6 then continue;end if;
   insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,register_on,valuation,agreed_owner_contract,response)
    values(p_career,ct.player_id,ct.club_id,buyer,'ai','precontract',0,greatest(40,ceil(ct.monthly_salary*1.12)),2+floor(random()*3)::int,0,d,d,greatest(public.cw_deadline(d),ct.expires_on+1),ct.expires_on+1,value,ct.id,
     'Pré-contrato assinado: o atleta chega sem custo ao fim do vínculo atual.') returning id into nid;
   perform public.cw_neg_history(nid,'player','Pré-contrato assinado com o novo clube.');
   perform public.cw_news_add(p_career,'precontract:'||nid,'transfer',public.mgr_player_name(ct.player_id)||' assina pré-contrato com '||public.mgr_club_name(buyer),
    'Sem renovação com '||coalesce(public.mgr_club_name(ct.club_id),'o clube')||', o atleta sai de graça em '||to_char(ct.expires_on+1,'DD/MM/YYYY')||'.',case when ct.club_id=own then 95 else 35 end,ct.club_id,ct.player_id);
  end loop;
  -- aviso mensal dos vínculos do seu elenco que terminam em até seis meses
  if extract(day from d)=1 and own is not null then
   for ct in select x.* from public.cw_contracts x where x.career_id=p_career and x.club_id=own and x.status='active' and x.expires_on between d and d+180
    and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and n.status in('agreed','precontract')) loop
    perform public.cw_news_add(p_career,'expiring:'||ct.id||':'||to_char(d,'YYYY-MM'),'contract','Contrato de '||public.mgr_player_name(ct.player_id)||' termina em '||to_char(ct.expires_on,'DD/MM/YYYY'),
     'Sem renovação, o atleta pode assinar pré-contrato com outro clube e sair de graça. Negocie em Time ou em Mundo → Contratos.',80,own,ct.player_id);
   end loop;
  end if;
 end if;
 -- 3) falência iminente: risco ≥ 90 por 21 dias (com o treinador há pelo menos 45 dias no cargo)
 if own is not null then
  select * into club from public.cw_clubs where career_id=p_career and club_id=own;
  select min(starts_on) into spell_start from public.cw_coach_contracts where career_id=p_career and club_id=own and ended_on is null;
  if club.financial_risk>=90 and club.distress_since is not null then
   if d-club.distress_since>=21 and d-coalesce(spell_start,d-999)>=45 then
    perform public.mgr_fire(p_career,'irresponsabilidade financeira: o clube está à beira da falência');
   else
    perform public.cw_news_add(p_career,'bankrupt-warning:'||own||':'||to_char(d,'IYYY-IW'),'board','Último aviso: clube à beira da falência',
     'O risco financeiro chegou a '||round(club.financial_risk)||'%. Sem vender atletas, cortar a folha ou investir recursos, você será demitido por irresponsabilidade financeira.',100,own);
   end if;
  end if;
 end if;
end $$;

create or replace function public.cw_step_day(p_career uuid)
returns date language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;
begin
 select * into w from public.cw_world where career_id=p_career for update;
 if w.needs_sync then raise exception 'Conclua a atualização do calendário antes de avançar outro dia';end if;
 if exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 update public.cw_world set today=today+1,elapsed_days=elapsed_days+1,last_services_on=null,needs_sync=true where career_id=p_career returning * into w;
 update public.career_seasons set day_no=w.elapsed_days where career_id=p_career and status='active' and mode in('coach','world');
 update public.mgr_players set condition=least(100,condition+4.3),rhythm=greatest(35,rhythm-.4),
  injury=case when injured_until<=w.elapsed_days then null else injury end,
  injured_until=case when injured_until<=w.elapsed_days then null else injured_until end
  where career_id=p_career and (condition<100 or rhythm is distinct from 35 or injured_until is not null or injury is not null);
 perform public.cw_finance_tick(p_career);
 perform public.cw_market_tick(p_career);
 perform public.cw_v32_tick(p_career);
 perform public.cw_jobs_tick(p_career);
 update public.cw_world set last_services_on=w.today where career_id=p_career;
 return w.today;
end $$;

-- Números já em uso continuam; quem já mudou de clube (ou não tem número na fonte) recebe um número livre no clube atual.
do $numbers$ declare r record;begin
 for r in select mp.career_id,mp.player_id,mp.club_id from public.mgr_players mp join public.cw_players cp using(career_id,player_id) join public.sim_players sp on sp.id=mp.player_id
  where mp.club_id is not null and (mp.club_id is distinct from sp.club_id or sp.shirt_number is null) and cp.shirt_number is null loop
  perform public.cw_assign_number(r.career_id,r.player_id,r.club_id);
 end loop;
end $numbers$;

do $acl$ declare f text;begin
 foreach f in array array['public.mgr_squad_before_v32(text)','public.mgr_match_payload_before_v32(bigint,integer)','public.career_news_before_v32(bigint)',
  'public.career_player_search_before_v32(text,text,text,text,bigint,integer,text)','public.career_transfer_bid_before_v32(text,bigint,integer,bigint,boolean,uuid)',
  'public.cw_register_transfer_before_v32(uuid)','public.cw_age(uuid,text)','public.cw_squad_limit()','public.cw_squad_count(uuid,text)','public.cw_shirt_number(uuid,text)',
  'public.cw_morale_perf_trg()','public.cw_assign_number(uuid,text,text)','public.cw_club_change_trg()','public.cw_player_number_trg()','public.cw_patch_players(uuid,jsonb,boolean)','public.cw_current_career()',
  'public.cw_v32_tick(uuid)','public.cw_morale_factor(numeric)','public.cw_step_day(uuid)','public.cw_register_transfer(uuid)','public.mgr_match_payload(bigint,integer)'] loop
  execute format('revoke all on function %s from public,anon,authenticated',f);
 end loop;
 foreach f in array array['public.mgr_squad(text)','public.career_news(bigint)','public.career_player_search(text,text,text,text,bigint,integer,text)',
  'public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid)','public.career_player_list(text,boolean)','public.career_player_release(text,uuid)'] loop
  execute format('revoke all on function %s from public,anon',f);
  execute format('grant execute on function %s to authenticated',f);
 end loop;
end $acl$;
notify pgrst,'reload schema';

do $preserved$ begin
 if exists(select 1 from v32_careers b left join public.careers c using(id) where b.original is distinct from to_jsonb(c)) then raise exception 'Abortado: uma carreira mudaria';end if;
 if exists(select 1 from v32_results b left join public.season_fixtures f using(id) where b.original is distinct from to_jsonb(f)) then raise exception 'Abortado: um resultado mudaria';end if;
 if exists(select 1 from v32_live b left join public.mgr_matches m using(fixture_id) where b.original is distinct from to_jsonb(m)) then raise exception 'Abortado: uma partida ao vivo mudaria';end if;
 if exists(select 1 from v32_squads b left join public.mgr_players p using(career_id,player_id) where b.original is distinct from to_jsonb(p)) then raise exception 'Abortado: um elenco mudaria';end if;
 if exists(select 1 from v32_contracts b left join public.cw_contracts c using(id) where b.original is distinct from to_jsonb(c)) then raise exception 'Abortado: um contrato mudaria';end if;
 if exists(select 1 from v32_clubs b left join public.cw_clubs c using(career_id,club_id) where b.original is distinct from to_jsonb(c)) then raise exception 'Abortado: um caixa de clube mudaria';end if;
 if exists(select 1 from v32_morale b left join public.cw_players p using(career_id,player_id) where row(b.morale,b.transfer_requested,b.promised_role) is distinct from row(p.morale,p.transfer_requested,p.promised_role)) then raise exception 'Abortado: uma satisfação mudaria';end if;
 if to_regprocedure('public.mgr_squad_before_v32(text)') is null or position('1200 milliseconds' in (select prosrc from pg_proc where oid=to_regprocedure('public.career_world_advance(integer,uuid)')))=0 then raise exception 'Instalação incompleta';end if;
end $preserved$;
commit;
select 'Instalação concluída: evoluções 31 e 32 ativas; dados dos usuários preservados.' as resultado;
