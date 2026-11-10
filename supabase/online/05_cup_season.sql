-- MODO ONLINE — Fase 5: copa, fim de temporada e novos técnicos.
--
-- Copa nos dias 6, 12, 18 e 24 (entre as rodadas 5|6, 10|11, 15|16 e 20|21 da liga). Doze clubes:
-- primeira fase com 8 jogando e 4 folgando (os 4 primeiros da liga), depois quartas, semifinal e final
-- (campo neutro). Empate: prorrogação e pênaltis (on_match_open já marca jogo de copa como decisivo).
-- Cada fase é sorteada quando termina a rodada de liga anterior, só entre os clubes classificados.
--
-- Fim de temporada (último jogo terminado): prêmios por posição, recompensas na conta (moedas), contratos
-- vencidos viram lotes da próxima temporada, histórico arquivado, eventos e lances antigos apagados.
-- Nova temporada: os mesmos clubes, tabela zerada; quem está na fila assume os clubes de bot pior colocados,
-- com elenco novo e escolha dos 3 craques. A idade sobe 1 ano. Não há aposentadoria.

alter table public.on_seasons add column if not exists gap interval;               -- sandbox: intervalo entre jogos
alter table public.on_seasons add column if not exists champion int;
alter table public.on_seasons add column if not exists cup_champion int;
alter table public.on_config add column if not exists league_prizes bigint[] not null
 default array[200000,150000,120000,100000,85000,70000,60000,50000,40000,30000,20000,10000]::bigint[];
alter table public.on_config add column if not exists cup_prizes bigint[] not null default array[120000,60000,30000]::bigint[]; -- campeão, vice, semifinal
alter table public.on_config add column if not exists league_coins int[] not null default array[300,200,150,100,80,60,50,40,30,20,10,10];
alter table public.on_config add column if not exists cup_coins int not null default 100;

-- Histórico das temporadas encerradas (uma linha por clube).
create table if not exists public.on_history(
 season_id smallint not null,
 club_id int not null,
 user_id uuid,
 name text not null,
 pos smallint not null,
 p smallint,w smallint,d smallint,l smallint,gf smallint,ga smallint,pts smallint,
 cup text,
 primary key(season_id,club_id)
);
alter table public.on_history enable row level security;
revoke all on public.on_history from anon,authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Calendário
-- ─────────────────────────────────────────────────────────────────────────────

-- Liga em turno e returno (mesma regra de on_season_bootstrap): 132 jogos, dias de copa livres.
create or replace function public.on_league_fixtures(p_season smallint,p_start date,p_gap interval,p_now timestamptz) returns void
language plpgsql security definer set search_path=public as $$
declare v_tz text;v_slots time[];
begin
 select tz,slots into v_tz,v_slots from public.on_seasons where id=p_season;
 insert into public.on_fixtures(season_id,comp,round,home,away,kickoff)
 select p_season,'L',q.rnd,ch.id,ca.id,
  case when p_gap is not null then p_now+((q.rnd-1)*6+q.i+1)*p_gap
   else ((p_start+(q.rnd+(q.rnd-1)/5-1))+v_slots[1+(q.i+q.rnd)%6])::timestamp at time zone v_tz end
 from(select r0.r+1+lg.leg*11 rnd,i0.i,
   case when ((r0.r+i0.i)%2=0)=(lg.leg=0) then p.sa else p.sb end sh,
   case when ((r0.r+i0.i)%2=0)=(lg.leg=0) then p.sb else p.sa end sw
  from generate_series(0,10) r0(r) cross join generate_series(0,5) i0(i) cross join generate_series(0,1) lg(leg)
  cross join lateral(select case when i0.i=0 then 11 else (r0.r+i0.i)%11 end sa,
   case when i0.i=0 then r0.r else (r0.r-i0.i+11)%11 end sb) p) q
 join public.on_clubs ch on ch.season_id=p_season and ch.seat=q.sh+1
 join public.on_clubs ca on ca.season_id=p_season and ca.seat=q.sw+1;
end $$;

-- Classificação atual (mesmo desempate da tela: pontos, saldo, gols marcados, nome).
create or replace function public.on_rank(p_season smallint) returns table(club_id int,pos int)
language sql stable security definer set search_path=public as $$
 select t.club_id,row_number() over(order by t.pts desc,t.gf-t.ga desc,t.gf desc,k.name)::int
 from public.on_table t join public.on_clubs k on k.id=t.club_id where t.season_id=p_season
$$;

-- Vencedor de um jogo de copa terminado.
create or replace function public.on_cup_winner(f public.on_fixtures) returns int
language sql immutable as $$
 select case when f.hg>f.ag then f.home when f.ag>f.hg then f.away
  when (f.pens->>0)::int>(f.pens->>1)::int then f.home else f.away end
$$;

-- Cria uma fase da copa: sorteio entre os classificados; horários do dia de copa (ou, no sandbox, logo depois
-- da rodada, empurrando os jogos de liga seguintes).
create or replace function public.on_cup_stage(p_season smallint,p_round int,p_now timestamptz default now()) returns int
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;v_stage text:=(array['r1','qf','sf','final'])[p_round];v_teams int[];v_n int;v_day date;i int;
begin
 select * into s from public.on_seasons where id=p_season for update;
 if exists(select 1 from public.on_fixtures where season_id=p_season and comp='C' and round=p_round) then return 0;end if;
 if p_round=1 then
  -- 8 jogam (5º ao 12º da liga); os 4 primeiros folgam e entram nas quartas
  v_teams:=array(select r.club_id from public.on_rank(p_season) r where r.pos>4);
 else
  v_teams:=array(select public.on_cup_winner(f) from public.on_fixtures f where f.season_id=p_season and f.comp='C' and f.round=p_round-1 and f.status='done');
  if p_round=2 then v_teams:=v_teams||array(select r.club_id from public.on_rank(p_season) r where r.pos<=4);end if;
  if cardinality(v_teams)<>(array[8,8,4,2])[p_round] then return 0;end if; -- fase anterior ainda em andamento
 end if;
 v_teams:=array(select x from unnest(v_teams) x order by public.sim_hash01(s.seed||':cup:'||p_round||':'||x));
 v_n:=cardinality(v_teams)/2;
 v_day:=s.starts_on+(p_round*6-1);
 for i in 1..v_n loop
  insert into public.on_fixtures(season_id,comp,round,stage,home,away,kickoff)
  values(p_season,'C',p_round,v_stage,v_teams[2*i-1],v_teams[2*i],
   case when s.kind='sandbox' then p_now+coalesce(s.gap,interval '30 minutes')*i
    else (v_day+s.slots[1+(i+p_round)%6])::timestamp at time zone s.tz end);
 end loop;
 -- sandbox: os jogos de liga ainda não começados andam para depois da copa
 if s.kind='sandbox' then
  update public.on_fixtures set kickoff=kickoff+coalesce(s.gap,interval '30 minutes')*v_n
   where season_id=p_season and comp='L' and status='sched' and kickoff>p_now;
 end if;
 return v_n;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Fim de temporada e nova temporada
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_season_end(p_season smallint,p_now timestamptz default now()) returns smallint
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;cfg public.on_config;fin public.on_fixtures;v_new smallint;v_champ int;v_cup int;v_runner int;r record;
 v_start date;q record;v_free int[];v_seed text:=md5(gen_random_uuid()::text);i int:=0;v_seat int;
begin
 select * into s from public.on_seasons where id=p_season for update;
 if s.status<>'live' or exists(select 1 from public.on_fixtures where season_id=p_season and status<>'done') then return null;end if;
 select * into cfg from public.on_config;
 select club_id into v_champ from public.on_rank(p_season) where pos=1;
 select * into fin from public.on_fixtures where season_id=p_season and comp='C' and stage='final';
 if fin.id is not null then v_cup:=public.on_cup_winner(fin);v_runner:=case when v_cup=fin.home then fin.away else fin.home end;end if;

 -- histórico
 insert into public.on_history(season_id,club_id,user_id,name,pos,p,w,d,l,gf,ga,pts,cup)
 select p_season,k.id,k.user_id,k.name,rk.pos,t.p,t.w,t.d,t.l,t.gf,t.ga,t.pts,
  case when k.id=v_cup then 'champion' when k.id=v_runner then 'final'
   when exists(select 1 from public.on_fixtures f where f.season_id=p_season and f.comp='C' and f.stage='sf' and k.id in(f.home,f.away)) then 'sf' end
 from public.on_rank(p_season) rk join public.on_clubs k on k.id=rk.club_id join public.on_table t on t.season_id=p_season and t.club_id=k.id
 on conflict do nothing;

 -- prêmios em dinheiro e recompensas na conta (moedas na carreira ativa de cada técnico)
 for r in select h.* from public.on_history h where h.season_id=p_season order by h.club_id loop
  perform 1 from public.on_clubs where id=r.club_id for update;
  perform public.on_money(r.club_id,cfg.league_prizes[r.pos],'prize',format('%sº lugar na liga',r.pos));
  if r.cup is not null then
   perform public.on_money(r.club_id,cfg.cup_prizes[case r.cup when 'champion' then 1 when 'final' then 2 else 3 end],'prize','Copa');
  end if;
  if r.user_id is not null then
   update public.careers set coins=coins+cfg.league_coins[r.pos]+case when r.cup='champion' then cfg.cup_coins else 0 end
    where id=(select x.id from public.careers x where x.user_id=r.user_id order by (x.status='active') desc,x.created_at desc limit 1);
   insert into public.on_news(club_id,kind,text) values(r.club_id,'season',format('Fim de temporada: %sº lugar. Prêmio de $ %s e %s moedas na sua conta.',
    r.pos,cfg.league_prizes[r.pos],cfg.league_coins[r.pos]+case when r.cup='champion' then cfg.cup_coins else 0 end));
  end if;
 end loop;
 update public.on_seasons set status='closed',champion=v_champ,cup_champion=v_cup where id=p_season;

 -- limpeza: eventos e lances antigos (o placar e o histórico ficam)
 delete from public.on_match_events e using public.on_fixtures f where f.id=e.fixture_id and f.season_id=p_season;
 delete from public.on_match_players mp using public.on_fixtures f where f.id=mp.fixture_id and f.season_id=p_season;
 delete from public.on_bids b using public.on_lots l where l.id=b.lot_id and l.season_id=p_season;
 update public.on_lots set status='cancelled',settled_at=p_now where season_id=p_season and status='open';
 update public.on_clubs k set reserved=0 where k.season_id=p_season;
 delete from public.on_players where club_id is null and id not in(select player_id from public.on_lots where status='open');

 -- nova temporada: começa depois de um dia de descanso (sandbox: logo em seguida)
 v_start:=(p_now at time zone s.tz)::date+2;
 s.gap:=coalesce(s.gap,case when s.kind='sandbox' then interval '30 minutes' end);
 insert into public.on_seasons(kind,starts_on,seed,tz,slots,gap) values(s.kind,v_start,v_seed,s.tz,s.slots,s.gap) returning id into v_new;
 update public.on_clubs set season_id=v_new,coins_conv=0,train_used=0,train_day=null where season_id=p_season;
 insert into public.on_table(season_id,club_id) select v_new,id from public.on_clubs where season_id=v_new;

 -- idade +1; contratos vencidos viram lotes do sistema na abertura da nova temporada
 update public.on_players p set age=age+1,yellows=0,susp_round=null from public.on_clubs k where k.id=p.club_id and k.season_id=v_new;
 v_free:=array(select k.id from public.on_clubs k where k.season_id=v_new);
 for r in select p.id,p.club_id,p.name,p.ovr,p.age,p.pot from public.on_players p where p.club_id=any(v_free) and coalesce(p.contract_end,0)<=p_season
  and (select count(*) from public.on_players x where x.club_id=p.club_id)>16 order by p.club_id,p.ovr loop
  update public.on_players set club_id=null,contract_end=v_new+1 where id=r.id;
  insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end)
  values(v_new,r.id,greatest(500,round(public.on_value(r.ovr,r.age,r.pot)*.4))::bigint,
   (v_start+time '09:00') at time zone s.tz+i*interval '20 minutes',(v_start+time '09:10') at time zone s.tz+i*interval '20 minutes',
   (v_start+time '09:20') at time zone s.tz+i*interval '20 minutes');
  insert into public.on_news(club_id,kind,text) values(r.club_id,'contract',format('O contrato de %s acabou. Ele foi para o mercado.',r.name));
  i:=i+1;
 end loop;
 perform public.on_lineup_repair(x) from unnest(v_free) x;

 -- fila: quem esperava assume os clubes de bot pior colocados, com elenco novo e escolha dos 3 craques
 for q in select a.user_id from public.on_access a where a.state='queued' order by a.queued_at loop
  select h.club_id into v_seat from public.on_history h join public.on_clubs k on k.id=h.club_id and k.user_id is null
   where h.season_id=p_season order by h.pos desc limit 1;
  exit when v_seat is null;
  delete from public.on_lots where player_id in(select id from public.on_players where club_id=v_seat);
  delete from public.on_players where club_id=v_seat;
  delete from public.on_lineups where club_id=v_seat;
  update public.on_clubs k set user_id=q.user_id,draft_step=0,cash=150000,debt=0,reserved=0,
   name=coalesce((select 'FC '||c.nickname from public.careers c where c.user_id=q.user_id order by (c.status='active') desc,c.created_at desc limit 1),k.name)
  where k.id=v_seat;
  update public.on_clubs set short=upper(left(coalesce(nullif(regexp_replace(name,'^FC |[^A-Za-z0-9]','','g'),''),'CLB'),3)) where id=v_seat;
  perform public.on_gen_squad(v_seat,v_seed||':'||v_seat,62,v_new+1);
  update public.on_access set state='allowed' where user_id=q.user_id;
  insert into public.on_news(club_id,kind,text) values(v_seat,'season','Bem-vindo à liga! Escolha seus três craques para começar.');
  v_seat:=null;
 end loop;

 perform public.on_league_fixtures(v_new,v_start,s.gap,p_now);
 return v_new;
end $$;

-- Gancho de fim de partida: sorteia a próxima fase da copa e fecha a temporada quando tudo terminou.
create or replace function public.on_cup_hook(p_fixture bigint) returns void
language plpgsql security definer set search_path=public as $$
declare f public.on_fixtures;k int;
begin
 select * into f from public.on_fixtures where id=p_fixture;
 -- cada fase k sai quando a rodada de liga 5k terminou e a fase anterior também (o que acontecer por último)
 for k in 1..4 loop
  continue when exists(select 1 from public.on_fixtures x where x.season_id=f.season_id and x.comp='C' and x.round=k);
  exit when exists(select 1 from public.on_fixtures x where x.season_id=f.season_id and x.comp='L' and x.round<=5*k and x.status<>'done');
  perform public.on_cup_stage(f.season_id,k,greatest(now(),f.kickoff+interval '13 minutes'));
  exit;
 end loop;
 if not exists(select 1 from public.on_fixtures x where x.season_id=f.season_id and x.status<>'done') then
  perform public.on_season_end(f.season_id,greatest(now(),f.kickoff+interval '13 minutes'));
 end if;
end $$;

update public.on_config set finish_hooks=array(select distinct x from unnest(finish_hooks||'on_cup_hook'::text) x);

-- ─────────────────────────────────────────────────────────────────────────────
-- Leituras para o app
-- ─────────────────────────────────────────────────────────────────────────────

-- Chave da copa e histórico das temporadas.
create or replace function public.on_cup() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();
begin
 return jsonb_build_object('my_club',c.id,
  'byes',(select jsonb_agg(jsonb_build_object('id',k.id,'name',k.name,'short',k.short,'colors',k.colors) order by r.pos)
   from public.on_rank(c.season_id) r join public.on_clubs k on k.id=r.club_id
   where r.pos<=4 and exists(select 1 from public.on_fixtures f where f.season_id=c.season_id and f.comp='C' and f.round=1)
    and not exists(select 1 from public.on_fixtures f where f.season_id=c.season_id and f.comp='C' and f.round=2)),
  'rounds',coalesce((select jsonb_agg(jsonb_build_object('round',f.round,'stage',f.stage,'id',f.id,'kickoff',f.kickoff,'status',f.status,'hg',f.hg,'ag',f.ag,'pens',f.pens,
    'home',jsonb_build_object('id',h.id,'name',h.name,'short',h.short,'colors',h.colors),
    'away',jsonb_build_object('id',a.id,'name',a.name,'short',a.short,'colors',a.colors),
    'winner',case when f.status='done' then public.on_cup_winner(f) end) order by f.round,f.kickoff)
   from public.on_fixtures f join public.on_clubs h on h.id=f.home join public.on_clubs a on a.id=f.away
   where f.season_id=c.season_id and f.comp='C'),'[]'::jsonb),
  'history',coalesce((select jsonb_agg(jsonb_build_object('season',x.season_id,'champion',x.champ,'cup',x.cupw,'me',x.me) order by x.season_id desc) from(
    select h.season_id,max(h.name) filter(where h.pos=1) champ,max(h.name) filter(where h.cup='champion') cupw,
     max(jsonb_build_object('pos',h.pos,'pts',h.pts,'cup',h.cup)::text) filter(where h.user_id=auth.uid())::jsonb me
    from public.on_history h group by h.season_id) x),'[]'::jsonb));
end $$;

revoke all on function public.on_league_fixtures(smallint,date,interval,timestamptz),public.on_rank(smallint),public.on_cup_winner(public.on_fixtures),
 public.on_cup_stage(smallint,int,timestamptz),public.on_season_end(smallint,timestamptz),public.on_cup_hook(bigint)
 from public,anon,authenticated;
revoke all on function public.on_cup() from public,anon;
grant execute on function public.on_cup() to authenticated;
