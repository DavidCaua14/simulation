-- MODO ONLINE — Fase 11: ranking geral pelo online, mercado em horário fixo, rodadas a cada 7 horas.
--
--  • Ranking geral: só o modo online pontua (on_ranking). Vitórias, empates, gols, jogo sem sofrer gol, vitória sobre
--    outro técnico, preparação completa, colocação final na liga e campanha na copa.
--  • Moedas por vitória e empate na conta do técnico.
--  • Mercado aberto só entre market_open e market_close (08:00 às 23:00). Fora disso: sem lances e sem anúncios.
--  • Destaque e lenda trocam a cada special_every horas (08, 13 e 18 h): ficam à mostra travados e abrem na reta final.
--  • Bots não dão lance em destaque nem em lenda; no pontapé escalam a formação e os onze que rendem mais.
--  • Técnico pode leiloar jogador do próprio elenco (1 hora, preço mínimo de 50% do valor).
--  • Rodadas a cada round_gap (7 horas), jogos da rodada espaçados em match_stagger; a condição física recupera por hora.
--  • Força do clube = média de titulares e reservas relacionados.
--  • Idade não sobe na virada de temporada.

alter table public.on_config add column if not exists market_open smallint not null default 8;
alter table public.on_config add column if not exists market_close smallint not null default 23;
alter table public.on_config add column if not exists special_every smallint not null default 5;
alter table public.on_config add column if not exists round_gap interval not null default '7 hours';
alter table public.on_config add column if not exists match_stagger interval not null default '10 minutes';
alter table public.on_config add column if not exists win_coins int not null default 15;
alter table public.on_config add column if not exists draw_coins int not null default 5;
alter table public.on_config add column if not exists rank_rules jsonb not null default
 '{"win":30,"draw":10,"goal":2,"goal_cap":5,"clean":5,"human":10,"prep":5,
   "league":[1000,600,400,250,150,100,50,50],"cup":{"champion":400,"final":200,"sf":80}}'::jsonb;
alter table public.on_seasons add column if not exists last_hourly timestamptz;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ranking geral
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.on_ranking(
 user_id uuid primary key,
 points int not null default 0,
 matches int not null default 0,wins int not null default 0,draws int not null default 0,losses int not null default 0,
 gf int not null default 0,ga int not null default 0,clean int not null default 0,human_wins int not null default 0,
 prep int not null default 0,league_titles int not null default 0,cups int not null default 0,seasons int not null default 0,
 pts_match int not null default 0,pts_goals int not null default 0,pts_prep int not null default 0,pts_season int not null default 0,
 updated_at timestamptz not null default now());
alter table public.on_ranking enable row level security;
revoke all on public.on_ranking from anon,authenticated;

create or replace function public.on_career_of(p_user uuid) returns uuid
language sql stable security definer set search_path=public as $$
 select x.id from public.careers x where x.user_id=p_user order by (x.status='active') desc,x.created_at desc limit 1
$$;

-- Fim de cada partida: pontos e moedas dos técnicos em campo (gancho de on_match_finish; roda uma vez por jogo).
create or replace function public.on_rank_hook(p_fixture bigint) returns void
language plpgsql security definer set search_path=public as $$
declare f public.on_fixtures;m public.on_matches;cfg public.on_config;rr jsonb;c public.on_clubs;o public.on_clubs;i int;
 gf int;ga int;v_pens jsonb;v_shoot boolean;won boolean;drew boolean;v_prep boolean;pm int;pg int;pp int;v_coins int;
begin
 select * into f from public.on_fixtures where id=p_fixture;
 select * into m from public.on_matches where fixture_id=p_fixture;
 select * into cfg from public.on_config;
 rr:=cfg.rank_rules;v_pens:=m.state->'pens';v_shoot:=coalesce(jsonb_typeof(v_pens)='array',false);
 for i in 0..1 loop
  select * into c from public.on_clubs where id=case when i=0 then f.home else f.away end;
  select * into o from public.on_clubs where id=case when i=0 then f.away else f.home end;
  continue when c.user_id is null;
  gf:=case when i=0 then f.hg else f.ag end;ga:=case when i=0 then f.ag else f.hg end;
  won:=gf>ga or (gf=ga and v_shoot and (v_pens->>i)::int>(v_pens->>(1-i))::int);
  drew:=gf=ga and not v_shoot;
  v_prep:=coalesce((m.state->'prep'->i->>'score')::int,0)>=100;
  pm:=case when won then (rr->>'win')::int+case when o.user_id is not null then (rr->>'human')::int else 0 end
   when drew then (rr->>'draw')::int else 0 end;
  pg:=least(gf,(rr->>'goal_cap')::int)*(rr->>'goal')::int+case when ga=0 then (rr->>'clean')::int else 0 end;
  pp:=case when v_prep then (rr->>'prep')::int else 0 end;
  insert into public.on_ranking as r(user_id,points,matches,wins,draws,losses,gf,ga,clean,human_wins,prep,pts_match,pts_goals,pts_prep)
  values(c.user_id,pm+pg+pp,1,won::int,drew::int,(not won and not drew)::int,gf,ga,(ga=0)::int,(won and o.user_id is not null)::int,v_prep::int,pm,pg,pp)
  on conflict(user_id) do update set points=r.points+excluded.points,matches=r.matches+1,wins=r.wins+excluded.wins,draws=r.draws+excluded.draws,
   losses=r.losses+excluded.losses,gf=r.gf+excluded.gf,ga=r.ga+excluded.ga,clean=r.clean+excluded.clean,human_wins=r.human_wins+excluded.human_wins,
   prep=r.prep+excluded.prep,pts_match=r.pts_match+excluded.pts_match,pts_goals=r.pts_goals+excluded.pts_goals,pts_prep=r.pts_prep+excluded.pts_prep,
   updated_at=now();
  v_coins:=case when won then cfg.win_coins when drew then cfg.draw_coins else 0 end;
  if v_coins>0 then
   perform set_config('econ.reason','online_match_reward',true);
   update public.careers set coins=coins+v_coins where id=public.on_career_of(c.user_id);
   perform set_config('econ.reason','',true);
   insert into public.on_news(club_id,kind,text) values(c.id,'prize',format('%s: +%s moedas na sua conta.',case when won then 'Vitória' else 'Empate' end,v_coins));
  end if;
 end loop;
end $$;

-- Fim de temporada: colocação na liga e campanha na copa (chamada por on_season_end, depois de gravar on_history).
create or replace function public.on_rank_season(p_season smallint) returns void
language plpgsql security definer set search_path=public as $$
declare rr jsonb:=(select rank_rules from public.on_config);h record;v int;
begin
 for h in select * from public.on_history where season_id=p_season and user_id is not null loop
  v:=coalesce((rr->'league'->>(h.pos-1))::int,0)+coalesce((rr->'cup'->>h.cup)::int,0);
  insert into public.on_ranking as r(user_id,points,pts_season,league_titles,cups,seasons)
  values(h.user_id,v,v,(h.pos=1)::int,coalesce(h.cup='champion',false)::int,1)
  on conflict(user_id) do update set points=r.points+excluded.points,pts_season=r.pts_season+excluded.pts_season,
   league_titles=r.league_titles+excluded.league_titles,cups=r.cups+excluded.cups,seasons=r.seasons+1,updated_at=now();
 end loop;
end $$;

update public.on_config set finish_hooks=finish_hooks||array['on_rank_hook'] where not 'on_rank_hook'=any(finish_hooks);

-- Ranking geral do app: mesma assinatura de antes, agora só com o modo online.
create or replace function public.ranking_scores()
returns table(career_id uuid,nickname text,photo_id text,level integer,club_id text,titles integer,wins integer,draws integer,losses integer,
 reputation numeric,events integer,fired integer,points bigint,created_at timestamptz,xp integer,avatar text,has_photo boolean)
language sql stable security definer set search_path=public as $$
 select c.id,c.nickname,c.photo_id,c.level,null::text,
  coalesce(r.league_titles+r.cups,0),coalesce(r.wins,0),coalesce(r.draws,0),coalesce(r.losses,0),0::numeric,0,0,
  coalesce(r.points,0)::bigint,c.created_at,coalesce(c.xp,0),
  case when pp.avatar_data like 'data:%' then null else pp.avatar_data end,coalesce(pp.avatar_data like 'data:%',false)
 from public.careers c
 left join public.on_ranking r on r.user_id=c.user_id
 left join public.player_profiles pp on pp.career_id=c.id
 where c.status='active'
$$;

create or replace function public.ranking_overall(p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare me uuid:=public.cw_current_career();rr jsonb:=(select rank_rules from public.on_config);
begin
 return(with ranked as(
   select s.*,cr.user_id,row_number() over(order by s.points desc,s.wins desc,s.level desc,s.created_at,s.career_id) as position
   from public.ranking_scores() s join public.careers cr on cr.id=s.career_id),
  full_ as(select r.*,k.name club_name,k.short club_short,k.colors club_colors,
    coalesce(g.matches,0) matches,coalesce(g.gf,0) gf,coalesce(g.ga,0) ga,coalesce(g.clean,0) clean,coalesce(g.human_wins,0) human_wins,
    coalesce(g.prep,0) prep,coalesce(g.league_titles,0) league_titles,coalesce(g.cups,0) cups,
    coalesce(g.pts_match,0) pts_match,coalesce(g.pts_goals,0) pts_goals,coalesce(g.pts_prep,0) pts_prep,coalesce(g.pts_season,0) pts_season
   from ranked r left join public.on_ranking g on g.user_id=r.user_id
   left join lateral(select x.name,x.short,x.colors from public.on_clubs x join public.on_seasons s on s.id=x.season_id and s.status='live'
     where x.user_id=r.user_id limit 1) k on true)
  select jsonb_build_object(
   'entries',coalesce((select jsonb_agg(jsonb_build_object('position',r.position,'nickname',r.nickname,'photo_id',r.photo_id,'avatar',r.avatar,'has_photo',r.has_photo,
     'level',r.level,'club_name',r.club_name,'club_short',r.club_short,'club_colors',r.club_colors,'titles',r.titles,'wins',r.wins,'draws',r.draws,'losses',r.losses,
     'matches',r.matches,'points',r.points,'is_me',r.career_id=me) order by r.position)
    from full_ r where r.position<=least(greatest(coalesce(p_limit,50),1),100)),'[]'::jsonb),
   'me',(select jsonb_build_object('position',r.position,'nickname',r.nickname,'photo_id',r.photo_id,'avatar',r.avatar,'has_photo',r.has_photo,'level',r.level,'xp',r.xp,
     'club_name',r.club_name,'club_short',r.club_short,'club_colors',r.club_colors,'titles',r.titles,'league_titles',r.league_titles,'cups',r.cups,
     'wins',r.wins,'draws',r.draws,'losses',r.losses,'matches',r.matches,'gf',r.gf,'ga',r.ga,'clean',r.clean,'human_wins',r.human_wins,'prep',r.prep,
     'pts_match',r.pts_match,'pts_goals',r.pts_goals,'pts_prep',r.pts_prep,'pts_season',r.pts_season,'points',r.points)
    from full_ r where r.career_id=me),
   'rules',rr,'online',true,
   'total',(select count(*) from ranked)));
end $$;
revoke all on function public.on_rank_hook(bigint),public.on_rank_season(smallint),public.on_career_of(uuid) from public,anon,authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Horário do mercado
-- ─────────────────────────────────────────────────────────────────────────────
-- Situação do mercado em p_now: aberto?, quando fecha hoje e quando abre de novo.
create or replace function public.on_market_hours(p_now timestamptz default now()) returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('open',h.hr>=cfg.market_open and h.hr<cfg.market_close,
  'open_hour',cfg.market_open,'close_hour',cfg.market_close,
  'closes_at',(h.d+make_time(cfg.market_close%24,0,0)+case when cfg.market_close>=24 then interval '1 day' else interval '0' end) at time zone h.tz,
  'opens_at',(case when h.hr<cfg.market_open then h.d else h.d+1 end+make_time(cfg.market_open,0,0)) at time zone h.tz)
 from public.on_config cfg
 cross join lateral(select coalesce((select s.tz from public.on_seasons s where s.status='live'),'America/Sao_Paulo') tz) z
 cross join lateral(select extract(hour from p_now at time zone z.tz)::int hr,(p_now at time zone z.tz)::date d,z.tz) h
$$;
create or replace function public.on_market_open(p_now timestamptz default now()) returns boolean
language sql stable security definer set search_path=public as $$ select (public.on_market_hours(p_now)->>'open')::boolean $$;

-- lance: só com o mercado aberto; bot nunca disputa destaque ou lenda
do $$ begin
 perform public.on_patch('public.on_bid_as(integer,bigint,bigint,timestamp with time zone)',
  ' if l.seller=p_club then raise exception ''Você não pode dar lance no seu próprio jogador'';end if;',
  ' if l.seller=p_club then raise exception ''Você não pode dar lance no seu próprio jogador'';end if;'||chr(10)||
  ' if not public.on_market_open(p_now) then raise exception ''Mercado fechado. Reabre às %h.'',lpad((select market_open from public.on_config)::text,2,''0'');end if;'||chr(10)||
  ' if l.featured>=8 and exists(select 1 from public.on_clubs b where b.id=p_club and b.user_id is null) then raise exception ''Destaque e lenda são só para técnicos'';end if;');
end $$;

-- Leilão de jogador do próprio elenco: uma hora, lance inicial entre 50% e 300% do valor.
create or replace function public.on_lot_create(p_player text,p_price bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);p public.on_players;v_value bigint;v_min int;v_floor bigint;h jsonb:=public.on_market_hours();
begin
 if not (h->>'open')::boolean then raise exception 'Mercado fechado. Reabre às %h.',lpad(h->>'open_hour',2,'0');end if;
 select * into p from public.on_players where id=p_player and club_id=c.id for update;
 if p.id is null then raise exception 'Jogador fora do seu elenco';end if;
 if (select count(*) from public.on_players where club_id=c.id)-(select count(*) from public.on_lots where seller=c.id and status='open')<=16 then
  raise exception 'Elenco com 16 jogadores: não dá para vender mais';
 end if;
 if public.on_in_live(p.id) then raise exception 'Ele está jogando agora. Coloque à venda depois do apito final.';end if;
 if exists(select 1 from public.on_lots where player_id=p.id and status='open') then raise exception 'Esse jogador já está à venda';end if;
 v_value:=public.on_value(p.ovr,p.age,p.pot);
 v_floor:=greatest(500,round(v_value*.5));
 if p_price is null or p_price<v_floor or p_price>v_value*3 then
  raise exception 'Lance inicial entre $ % e $ %',v_floor,round(v_value*3);
 end if;
 select user_lot_minutes into v_min from public.on_config;
 if now()+v_min*interval '1 minute'>(h->>'closes_at')::timestamptz then
  raise exception 'O mercado fecha às %h: anuncie com pelo menos % minutos de antecedência',lpad(h->>'close_hour',2,'0'),v_min;
 end if;
 insert into public.on_lots(season_id,player_id,seller,start_price,opens_at,ends_at,hard_end)
 values(c.season_id,p.id,c.id,p_price,now(),now()+v_min*interval '1 minute',now()+v_min*interval '1 minute'+(select lot_extend_max from public.on_config));
 return public.on_market();
end $$;
-- faixa de preço para a tela de venda
create or replace function public.on_lot_range(p_player text) returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('value',v.v,'min',greatest(500,round(v.v*.5)),'max',round(v.v*3),'minutes',(select user_lot_minutes from public.on_config),
  'market',public.on_market_hours())
 from public.on_players p cross join lateral(select public.on_value(p.ovr,p.age,p.pot) v) v
 where p.id=p_player and p.club_id=(public.on_me()).id
$$;

-- Sem lances, um bot só fica com o jogador se o preço pedido for razoável (até 80% do valor) e paga o preço pedido.
-- Antes o bot pagava ao menos metade do preço pedido, o que rendia dinheiro fácil com preço inflado.
do $$ begin
 perform public.on_patch('public.on_lot_settle(bigint,timestamp with time zone)',
  '  v_price:=greatest(l.start_price/2,round(v_value*(.60+random()*.15)))::bigint;',
  '  v_price:=l.start_price; -- o bot paga o preço pedido');
 perform public.on_patch('public.on_lot_settle(bigint,timestamp with time zone)',
  '  select k.id into v_buyer from public.on_clubs k where k.season_id=l.season_id and k.user_id is null and k.cash-k.reserved>=v_price',
  '  select k.id into v_buyer from public.on_clubs k where k.season_id=l.season_id and k.user_id is null and k.cash-k.reserved>=v_price and v_price<=v_value*.8');
end $$;

-- Mercado: lotes abertos (especiais aparecem travados antes de abrir) e o horário de funcionamento.
create or replace function public.on_market() returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();cfg public.on_config;
begin
 select * into cfg from public.on_config;
 return jsonb_build_object('server_now',now(),'my_club',c.id,'hours',public.on_market_hours(),
  'club',jsonb_build_object('cash',c.cash,'reserved',c.reserved,'debt',c.debt,'roster',(select count(*) from public.on_players where club_id=c.id)),
  'coins',jsonb_build_object('wallet',coalesce(public.on_wallet(),0),'rate',cfg.coin_rate,'bid_rate',cfg.coin_bid_rate,'converted',c.coins_conv,'cap',c.coins_conv+coalesce(public.on_wallet(),0),'unlimited',true),
  'lots',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.opens_at,l.featured desc) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='open' and x.featured>=8) l),'[]'::jsonb)
   ||coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.featured=0,l.featured,l.ends_at) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='open' and x.featured<8 and x.opens_at<=now()) l),'[]'::jsonb),
  'recent',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.settled_at desc) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='sold' order by x.settled_at desc limit 8) l),'[]'::jsonb));
end $$;

-- Relógio do mercado. Leilões comuns de hora em hora dentro do horário; especiais por janela de special_every horas.
create or replace function public.on_market_tick(p_now timestamptz,p_new_day boolean) returns void
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;cfg public.on_config;r record;t int;pid text;k int;v_bid bigint;v_end timestamptz;v_day date;v_hour int;
 v_open timestamptz;v_close timestamptz;v_win int;v_ws timestamptz;sp record;
begin
 select * into s from public.on_seasons where status='live';
 if s.id is null then return;end if;
 select * into cfg from public.on_config;
 v_day:=(p_now at time zone s.tz)::date;
 v_hour:=extract(hour from p_now at time zone s.tz);
 v_close:=(v_day+make_time(cfg.market_close%24,0,0)+case when cfg.market_close>=24 then interval '1 day' else interval '0' end) at time zone s.tz;
 for r in select l.id from public.on_lots l where l.season_id=s.id and l.status='open' and l.ends_at<=p_now order by l.ends_at limit 10 loop
  perform public.on_lot_settle(r.id,p_now);
 end loop;
 if v_hour<cfg.market_open or v_hour>=cfg.market_close then return;end if; -- mercado fechado
 for t in 1..least(cfg.featured_count,4) loop
  continue when exists(select 1 from public.on_lots x where x.season_id=s.id and x.status='open' and x.featured=t);
  v_end:=case when cfg.featured_minutes=60 then date_trunc('hour',p_now+interval '15 minutes')+interval '1 hour'
   else p_now+cfg.featured_minutes*interval '1 minute' end;
  continue when v_end>v_close;
  pid:=public.on_gen_featured(s.seed||':f:'||t||':'||floor(extract(epoch from p_now))::bigint,t);
  insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
  select s.id,pid,public.on_start_price(p),p_now,v_end,v_end+cfg.lot_extend_max,t from public.on_players p where p.id=pid;
 end loop;
 -- especiais da janela atual: destaque abre na penúltima hora da janela e a lenda na última; cada um dura uma hora
 v_win:=(v_hour-cfg.market_open)/cfg.special_every;
 v_ws:=(v_day+make_time(cfg.market_open+v_win*cfg.special_every,0,0)) at time zone s.tz;
 if v_ws+cfg.special_every*interval '1 hour'<=v_close then
  for sp in select * from(values(9,false,2),(8,true,1)) v(feat,legend,before) loop
   v_open:=v_ws+(cfg.special_every-sp.before)*interval '1 hour';
   continue when p_now>=v_open; -- janela pega pela metade: não cria leilão já em andamento
   continue when exists(select 1 from public.on_lots x where x.season_id=s.id and x.featured=sp.feat and x.opens_at=v_open);
   pid:=public.on_gen_special(s.seed||':special:'||sp.feat||':'||v_day||':'||v_win,sp.legend);
   continue when pid is null;
   insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
   select s.id,pid,public.on_start_price(p),v_open,v_open+interval '1 hour',v_open+interval '1 hour'+cfg.lot_extend_max,sp.feat
   from public.on_players p where p.id=pid;
  end loop;
 end if;
 -- bots: entram na disputa só quando um técnico já deu lance, nos últimos 3 minutos, até 70% a 90% do valor.
 -- Destaque e lenda ficam fora (featured>=8).
 for r in select l.*,public.on_value(p.ovr,p.age,p.pot) v from public.on_lots l join public.on_players p on p.id=l.player_id
  where l.season_id=s.id and l.status='open' and l.featured<8 and l.opens_at<=p_now and l.ends_at>p_now and l.ends_at<=p_now+interval '3 minutes'
   and l.best_club is not null and exists(select 1 from public.on_clubs h where h.id=l.best_club and h.user_id is not null)
   and random()<.5 loop
  v_bid:=r.best_bid+greatest(500,ceil(r.best_bid*.05))::bigint;
  continue when v_bid>r.v*(.7+.2*public.sim_hash01('botcap:'||r.id));
  select c.id into k from public.on_clubs c where c.season_id=s.id and c.user_id is null and c.id is distinct from r.best_club
   and c.id is distinct from r.seller and c.debt=0 and c.cash-c.reserved>=v_bid and (select count(*) from public.on_players x where x.club_id=c.id)<26
   order by random() limit 1;
  continue when k is null;
  begin perform public.on_bid_as(k,r.id,v_bid,p_now);exception when others then null;end;
 end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Bots: melhor formação e melhores onze
-- ─────────────────────────────────────────────────────────────────────────────
-- Testa cada formação do catálogo e fica com a que soma mais nota em campo (nota x encaixe na vaga x condição).
create or replace function public.on_bot_lineup(p_club int) returns void
language plpgsql security definer set search_path=public as $$
declare f record;v_best text;v_score numeric;v_top numeric:=-1;
begin
 for f in select id,slots from public.sim_formations order by sort,id loop
  begin
   perform public.on_auto_lineup(p_club,f.id);
  exception when others then continue;
  end;
  select sum(p.ovr*greatest(coalesce(ft.fit,.5),case when s.value->>'pos'=any(p.sec) then .97 else 0 end)*(.7+.3*p.cond/100.0)) into v_score
  from public.on_lineups l cross join jsonb_array_elements(f.slots) s
  join public.on_players p on p.id=l.slots->>(s.value->>'slot')
  left join public.sim_position_fit ft on ft.from_pos=p.pos and ft.to_pos=s.value->>'pos'
  where l.club_id=p_club;
  if coalesce(v_score,0)>v_top then v_top:=v_score;v_best:=f.id;end if;
 end loop;
 if v_best is not null then perform public.on_auto_lineup(p_club,v_best);end if;
end $$;
do $$ begin
 perform public.on_patch('public.on_match_open(public.on_fixtures)',' if bh then perform public.on_auto_lineup(p_fx.home);end if;',' if bh then perform public.on_bot_lineup(p_fx.home);end if;');
 perform public.on_patch('public.on_match_open(public.on_fixtures)',' if ba then perform public.on_auto_lineup(p_fx.away);end if;',' if ba then perform public.on_bot_lineup(p_fx.away);end if;');
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Rodadas a cada round_gap
-- ─────────────────────────────────────────────────────────────────────────────
-- Liga: a rodada N começa em (dia de início, primeiro horário) + (N-1) x round_gap; os seis jogos saem espaçados.
create or replace function public.on_league_fixtures(p_season smallint,p_start date,p_gap interval,p_now timestamptz) returns void
language plpgsql security definer set search_path=public as $$
declare v_tz text;v_slots time[];cfg public.on_config;v_t0 timestamptz;
begin
 select tz,slots into v_tz,v_slots from public.on_seasons where id=p_season;
 select * into cfg from public.on_config;
 v_t0:=(p_start+coalesce(v_slots[1],time '09:00'))::timestamp at time zone v_tz;
 insert into public.on_fixtures(season_id,comp,round,home,away,kickoff)
 select p_season,'L',q.rnd,ch.id,ca.id,
  case when p_gap is not null then p_now+((q.rnd-1)*6+q.i+1)*p_gap
   else v_t0+(q.rnd-1)*cfg.round_gap+q.i*cfg.match_stagger end
 from(select r0.r+1+lg.leg*11 rnd,i0.i,
   case when ((r0.r+i0.i)%2=0)=(lg.leg=0) then p.sa else p.sb end sh,
   case when ((r0.r+i0.i)%2=0)=(lg.leg=0) then p.sb else p.sa end sw
  from generate_series(0,10) r0(r) cross join generate_series(0,5) i0(i) cross join generate_series(0,1) lg(leg)
  cross join lateral(select case when i0.i=0 then 11 else (r0.r+i0.i)%11 end sa,
   case when i0.i=0 then r0.r else (r0.r-i0.i+11)%11 end sb) p) q
 join public.on_clubs ch on ch.season_id=p_season and ch.seat=q.sh+1
 join public.on_clubs ca on ca.season_id=p_season and ca.seat=q.sw+1;
end $$;

-- Copa: a fase K entra no meio do intervalo depois da rodada 5K da liga (metade de round_gap depois dela).
do $$ begin
 perform public.on_patch('public.on_cup_stage(smallint,integer,timestamp with time zone)',
  '    else (v_day+s.slots[1+(i+p_round)%6])::timestamp at time zone s.tz end);',
  '    else greatest(p_now+interval ''20 minutes'',(select min(g.kickoff) from public.on_fixtures g where g.season_id=p_season and g.comp=''L'' and g.round=5*p_round)
      +(select round_gap/2 from public.on_config))+(i-1)*(select match_stagger from public.on_config) end);');
 -- lesão em jogos (com rodadas a cada 7 horas, dias de calendário deixaram de ser a medida): 1 ou 2 dias
 perform public.on_patch('public.on_match_finish(bigint)','::date+1+floor(random()*5)::int else p.inj_until end','::date+1+floor(random()*2)::int else p.inj_until end');
 -- idade não sobe na virada de temporada; ranking recebe a colocação final
 perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',' update public.on_players p set age=age+1,yellows=0,susp_round=null from',' update public.on_players p set yellows=0,susp_round=null from');
 perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',
  ' for r in select h.* from public.on_history h where h.season_id=p_season order by h.club_id loop',
  ' perform public.on_rank_season(p_season);'||chr(10)||' for r in select h.* from public.on_history h where h.season_id=p_season order by h.club_id loop');
 -- preparação: com mais jogos por dia, um treino desde o último jogo já vale os 30 pontos
 perform public.on_patch('public.on_prep_json(public.on_clubs,public.on_fixtures)','select least(2,count(*)) into v_train','select least(1,count(*)) into v_train');
 perform public.on_patch('public.on_prep_json(public.on_clubs,public.on_fixtures)','+15*v_train+','+30*v_train+');
 perform public.on_patch('public.on_prep_json(public.on_clubs,public.on_fixtures)','''train'',v_train,''train_max'',2,','''train'',v_train,''train_max'',1,');
 -- início do modo: força = média de titulares e reservas relacionados; "dia" vira a rodada da liga
 perform public.on_patch('public.on_status()',
  '''strength'',(select round(avg(x.ovr),1) from(select p.ovr from public.on_players p where p.club_id=c.id order by p.ovr desc limit 11) x)),',
  '''strength'',public.on_strength(c.id)),');
 perform public.on_patch('public.on_status()',
  '''day'',jsonb_build_object(''n'',greatest(1,v_today-s.starts_on+1),''of'',26),',
  '''day'',jsonb_build_object(''n'',coalesce((select min(f.round) from public.on_fixtures f where f.season_id=s.id and f.comp=''L'' and f.status<>''done''),22),''of'',22,''round'',true),');
end $$;

-- Força do clube: média de quem está relacionado (11 titulares + banco). Sem escalação salva: os 23 melhores.
create or replace function public.on_strength(p_club int) returns numeric
language sql stable security definer set search_path=public as $$
 select round(avg(p.ovr),1) from public.on_players p where p.club_id=p_club and p.id in(
  select e.value from public.on_lineups l,jsonb_each_text(l.slots) e where l.club_id=p_club
  union all select unnest(l.bench) from public.on_lineups l where l.club_id=p_club
  union all select q.id from(select x.id from public.on_players x where x.club_id=p_club
   and not exists(select 1 from public.on_lineups l where l.club_id=p_club) order by x.ovr desc limit 23) q)
$$;

-- Relógio: a condição física recupera por hora (5 pontos, 35 a cada rodada) em vez de uma vez por dia.
create or replace function public.on_tick(p_now timestamptz default now()) returns integer
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;r record;f public.on_fixtures;m public.on_matches;v_today date;n int:=0;v_new_day boolean:=false;v_hook text;
begin
 select x.* into s from public.on_seasons x where x.status='live';
 if s.id is null then return 0;end if;
 v_today:=(p_now at time zone s.tz)::date;
 if s.last_recovery is distinct from v_today then
  update public.on_seasons set last_recovery=v_today where id=s.id and last_recovery is distinct from v_today;
  if found then
   v_new_day:=true;
   update public.on_players p set rhythm=greatest(30,p.rhythm-2)
    from public.on_clubs k where k.season_id=s.id and p.club_id=k.id and p.rhythm>30;
  end if;
 end if;
 if s.last_hourly is null or p_now>=s.last_hourly+interval '1 hour' then
  update public.on_seasons set last_hourly=p_now where id=s.id and (last_hourly is null or p_now>=last_hourly+interval '1 hour');
  if found then
   update public.on_players p set cond=least(100,p.cond+5)
    from public.on_clubs k where k.season_id=s.id and p.club_id=k.id and p.cond<100 and not public.on_in_live(p.id);
  end if;
 end if;
 for r in select x.id from public.on_fixtures x where x.season_id=s.id and x.status<>'done' and x.kickoff<=p_now order by x.kickoff limit 3 loop
  begin
   if not exists(select 1 from public.on_matches where fixture_id=r.id) then
    select * into f from public.on_fixtures where id=r.id for update skip locked;
    continue when f.id is null;
    perform public.on_match_open(f);
   end if;
   select * into m from public.on_matches where fixture_id=r.id for update skip locked;
   continue when m.fixture_id is null or m.status<>'live';
   select * into f from public.on_fixtures where id=r.id;
   -- alguém assistindo: a tela conduz a partida
   continue when m.seen_h>p_now-interval '90 seconds' or m.seen_a>p_now-interval '90 seconds';
   -- ninguém assistindo: só depois do apito final do relógio, em blocos de 45 minutos
   continue when public.on_clock(f.kickoff,p_now,coalesce((m.state->>'et')::boolean,false))<case when coalesce((m.state->>'et')::boolean,false) then 120 else 90 end;
   if m.minute<45 then perform public.on_advance(r.id,f.kickoff+interval '315 seconds',null);
   else perform public.on_advance(r.id,f.kickoff+interval '1 day',null);end if;
   n:=n+1;
  exception when others then raise warning 'on_tick jogo %: %',r.id,sqlerrm;
  end;
 end loop;
 -- fases seguintes (mercado, finanças, copa...): cada gancho em sua própria subtransação
 for v_hook in select unnest(tick_hooks) from public.on_config loop
  begin
   execute format('select public.%I($1,$2)',v_hook) using p_now,v_new_day;
  exception when others then raise warning 'on_tick %: %',v_hook,sqlerrm;
  end;
 end loop;
 return n;
end $$;

revoke all on function public.on_market_hours(timestamptz),public.on_market_open(timestamptz),public.on_bot_lineup(int),public.on_strength(int) from public,anon,authenticated;
revoke all on function public.on_lot_create(text,bigint),public.on_lot_range(text),public.on_lot_cancel(bigint),public.ranking_overall(integer) from public,anon;
grant execute on function public.on_lot_create(text,bigint),public.on_lot_range(text),public.on_lot_cancel(bigint),public.ranking_overall(integer) to authenticated;
revoke all on function public.ranking_scores() from public,anon,authenticated;
