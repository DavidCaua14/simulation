-- MODO ONLINE — Fase 2: partida ao vivo.
--
-- A partida dura 12 minutos reais e acontece no horário marcado (on_fixtures.kickoff). Os dois técnicos podem
-- mexer no time; quem não está presente é comandado pelo jogo (a mesma IA do modo Temporadas).
--
-- Motor: on_engine_run é uma cópia congelada de mgr_engine_run_v2, gerada aqui por substituições de texto
-- conferidas por contagem. Se o motor original mudar, a migration falha em vez de gerar algo errado.
-- Nenhuma função mgr_* ou cw_* é alterada; as puras (mgr_pick, mgr_card_chances, mgr_tactical_effect,
-- mgr_tactics_clean, mgr_ai_tactics, mgr_cond_factor) e o tipo mgr_ep são só lidos.
--
-- Custo: uma partida por horário (um jogo por clube por dia, seis horários). A tela consulta a cada 40 s e
-- recebe só os eventos novos; o cron (1 por minuto) normalmente faz uma consulta em índice e termina.

-- ─────────────────────────────────────────────────────────────────────────────
-- Colunas novas das tabelas da Fase 1
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.on_players add column if not exists yellows smallint not null default 0;
alter table public.on_lineups add column if not exists roles jsonb not null default '{}'::jsonb;
alter table public.on_seasons add column if not exists last_recovery date;
-- Ganchos das fases seguintes: funções chamadas pelo cron (p_now, p_new_day) e no fim de cada partida (p_fixture).
alter table public.on_config add column if not exists tick_hooks text[] not null default '{}';
alter table public.on_config add column if not exists finish_hooks text[] not null default '{}';

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabelas da partida: mesmas colunas de mgr_matches / mgr_match_players / mgr_match_events, sem ligação com o
-- catálogo sim_players. Nome, número e nota do jogador ficam copiados na linha.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.on_matches(
 fixture_id bigint primary key references public.on_fixtures(id) on delete cascade,
 season_id smallint not null references public.on_seasons(id) on delete cascade,
 status text not null default 'live' check (status in('live','finished')),
 minute smallint not null default 0,
 state jsonb not null default '{}'::jsonb,
 summary jsonb,
 seen_h timestamptz,
 seen_a timestamptz,
 reqs text[] not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.on_match_players(
 fixture_id bigint not null references public.on_matches(fixture_id) on delete cascade,
 player_id text not null,
 side char(1) not null check (side in('h','a')),
 club_id int not null,
 name text not null,
 number smallint,
 nat_pos text not null,
 ovr numeric(4,1) not null,
 agg smallint not null default 50,
 disc smallint not null default 60,
 slot text,
 pos text,
 status text not null,
 starter boolean not null default false,
 fit numeric(4,3) not null default 1,
 cond numeric(5,2) not null default 100,
 rhythm numeric(5,2) not null default 60,
 c_att numeric(5,2),c_cre numeric(5,2),c_def numeric(5,2),c_ctl numeric(5,2),c_gk numeric(5,2),c_fin numeric(5,2),
 c_head numeric(5,2),c_pace numeric(5,2),c_stam numeric(5,2),c_tack numeric(5,2),c_str numeric(5,2),
 minutes smallint not null default 0,
 entered_min smallint,
 left_min smallint,
 goals smallint not null default 0,
 assists smallint not null default 0,
 shots smallint not null default 0,
 sot smallint not null default 0,
 saves smallint not null default 0,
 fouls smallint not null default 0,
 yellow smallint not null default 0,
 red smallint not null default 0,
 injured boolean not null default false,
 rating numeric(4,2) not null default 6,
 primary key(fixture_id,player_id)
);
create index if not exists on_match_players_side on public.on_match_players(fixture_id,side);

create table if not exists public.on_match_events(
 fixture_id bigint not null references public.on_matches(fixture_id) on delete cascade,
 seq int not null,
 minute smallint not null,
 side char(1),
 kind text not null,
 player_id text,
 player2_id text,
 detail text,
 primary key(fixture_id,seq)
);

alter table public.on_matches enable row level security;
alter table public.on_match_players enable row level security;
alter table public.on_match_events enable row level security;
revoke all on public.on_matches,public.on_match_players,public.on_match_events from anon,authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Relógio: horário real → minuto de jogo
-- 7 s por minuto; 45 min = 315 s; intervalo de 90 s; fim em 720 s (12:00).
-- Com prorrogação (copa): pausa de 60 s depois dos 90 e mais 30 min (fim em 990 s).
-- Devolve -1 antes do pontapé.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_clock(p_kickoff timestamptz,p_now timestamptz,p_et boolean default false) returns int
language sql immutable set search_path=public as $$
 select case when s<0 then -1
  when s<315 then floor(s/7)::int
  when s<405 then 45
  when s<720 then 45+floor((s-405)/7)::int
  when not coalesce(p_et,false) or s<780 then 90
  when s<990 then 90+floor((s-780)/7)::int
  else 120 end
 from(select extract(epoch from p_now-p_kickoff)::float8 s) x
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Atributos do motor a partir da nota do jogador online.
-- Mesma relação nota→atributo do catálogo sim_players (regressão por posição, inclinação ~1):
-- atributo = nível + desvio da posição + variação própria do jogador (±3) + ganho de treino do grupo.
-- Grupos de treino g: 1 defesa (def, desarme, cabeceio), 2 passe (criação, controle), 3 ataque (ataque,
-- finalização), 4 físico (velocidade, resistência, força).
-- Ordem: att, cre, def, ctl, gk, fin, head, pace, stam, tack, str.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_comp(p_id text,p_pos text,p_level numeric,p_g smallint[]) returns numeric[]
language sql immutable set search_path=public as $$
 select array(
  select round(greatest(15,least(99,
    case when k.i=5 and p_pos<>'GOL' then .7*p_level-32 else p_level+o.d[k.i] end
    +(public.sim_hash01(p_id||':a'||k.i)-.5)*6
    +coalesce(p_g[(array[3,2,1,2,0,3,1,4,4,1,4])[k.i]],0)))::numeric,2)
  from generate_series(1,11) k(i)
  cross join(select case p_pos
   when 'ATA' then array[0.5,-12.4,-22.7,-11.6,0,4.7,-0.9,-3.3,-8.9,-25.7,-1.7]
   when 'GOL' then array[-43.7,-24.3,-39.2,-23.6,1.1,-51,-33.3,-29.5,-19.3,-42.7,-10.9]
   when 'LD' then array[-8.6,-4.9,-2.3,-3.3,0,-19.5,-10.8,4.1,3.4,0.7,-6.1]
   when 'LE' then array[-9.4,-3.7,-2.2,-2.1,0,-20.8,-8.9,2.3,4.9,0.4,-5.2]
   when 'MC' then array[-7.8,2.0,-5.0,2.0,0,-11.8,-10.0,-6.5,2.1,-3.8,-4.2]
   when 'MEI' then array[-5.5,2.0,-17.0,0.8,0,-9.1,-16.9,-8.9,-4.4,-16.1,-7.2]
   when 'PD' then array[-0.3,-5.2,-18.7,-4.0,0,-5.7,-15.4,3.7,-1.6,-18.4,-9.1]
   when 'PE' then array[-1.2,-4.2,-19.8,-3.0,0,-7.0,-15.6,3.6,-1.4,-19.3,-6.9]
   when 'VOL' then array[-14.5,-4.2,0.4,-3.1,0,-19.5,-4.5,-9.6,-0.4,2.6,1.5]
   else array[-22.5,-13.2,1.8,-11.3,0,-30.8,1.4,-10.1,-5.1,2.6,-0.1] end::numeric[] d) o
  order by k.i)
$$;

-- Encaixe do jogador online em uma posição (mesma regra de mgr_fit: tabela de encaixe ou posição secundária).
create or replace function public.on_fit(p_player text,p_pos text) returns numeric
language sql stable set search_path=public as $$
 select greatest(coalesce((select f.fit from public.sim_position_fit f where f.from_pos=p.pos and f.to_pos=p_pos),.5),
  case when p_pos=any(p.sec) then .97 else 0 end)
 from public.on_players p where p.id=p_player
$$;

-- Melhor reserva no banco para a posição (nota × encaixe × condição).
create or replace function public.on_best_bench(p_fixture bigint,p_side char,p_pos text) returns text
language sql stable set search_path=public as $$
 select mp.player_id from public.on_match_players mp
  left join public.sim_position_fit f on f.from_pos=mp.nat_pos and f.to_pos=p_pos
 where mp.fixture_id=p_fixture and mp.side=p_side and mp.status='bench'
 order by mp.ovr*coalesce(f.fit,.5)*public.mgr_cond_factor(mp.cond) desc,mp.player_id
 limit 1
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cópias geradas do modo Temporadas
-- ─────────────────────────────────────────────────────────────────────────────

-- Copia a função p_src trocando cada p_from[i] por p_to[i]; cada trecho precisa aparecer exatamente p_n[i] vezes.
-- Depois da troca, só podem sobrar referências mgr_ às funções puras e ao tipo mgr_ep.
create or replace function public.on_clone(p_src regprocedure,p_from text[],p_to text[],p_n int[]) returns void
language plpgsql set search_path=public as $$
declare v text:=pg_get_functiondef(p_src);i int;c int;r text;
begin
 for i in 1..cardinality(p_from) loop
  c:=(length(v)-length(replace(v,p_from[i],'')))/length(p_from[i]);
  if c<>p_n[i] then
   raise exception 'Motor do modo Temporadas mudou: "%" aparece % vez(es) em %, esperado %',p_from[i],c,p_src,p_n[i];
  end if;
  v:=replace(v,p_from[i],p_to[i]);
 end loop;
 for r in select distinct m[1] from regexp_matches(v,'(mgr_[a-z0-9_]+)','g') m loop
  if r not in('mgr_ep','mgr_pick','mgr_card_chances','mgr_tactical_effect','mgr_tactics_clean','mgr_cond_factor','mgr_ai_tactics') then
   raise exception 'Cópia de % ainda cita %',p_src,r;
  end if;
 end loop;
 execute v;
end $$;

do $$
declare t constant text[]:=array['public.mgr_matches','public.mgr_match_players','public.mgr_match_events','public.mgr_event(',
 'public.mgr_do_sub(','public.mgr_best_bench(','public.mgr_fit(','public.mgr_ai_manage('];
 o constant text[]:=array['public.on_matches','public.on_match_players','public.on_match_events','public.on_event(',
 'public.on_do_sub(','public.on_best_bench(','public.on_fit(','public.on_ai_manage('];
begin
 perform public.on_clone('public.mgr_event(bigint,integer,character,text,text,text,text)',
  array['public.mgr_event(',t[1],t[3]],array['public.on_event(',o[1],o[3]],array[1,1,1]);
 perform public.on_clone('public.mgr_do_sub(bigint,character,text,text,integer,boolean,text)',
  array['public.mgr_do_sub(',t[1],t[2],t[4],t[7]],array['public.on_do_sub(',o[1],o[2],o[4],o[7]],array[1,3,6,1,1]);
 perform public.on_clone('public.mgr_set_positions(bigint,character,jsonb,integer)',
  array['public.mgr_set_positions(',t[1],t[2],t[4],t[7]],array['public.on_set_positions(',o[1],o[2],o[4],o[7]],array[1,2,5,1,1]);
 perform public.on_clone('public.mgr_rate(bigint,boolean)',
  array['public.mgr_rate(',t[1],t[2]],array['public.on_rate(',o[1],o[2]],array[1,2,1]);
 perform public.on_clone('public.mgr_ai_manage_v2(bigint,character,integer)',
  array['public.mgr_ai_manage_v2(',t[1],t[2],t[5],t[6]],array['public.on_ai_manage(',o[1],o[2],o[5],o[6]],array[1,4,3,1,1]);
 -- Motor. p_interactive passa a ser texto com os lados presentes ('h', 'a', 'ha' ou ''); nulo = ninguém
 -- assistindo (menos eventos gravados). O relógio é real: expulsão e lesão não param a partida. O lado
 -- presente tem 8 minutos para trocar o lesionado (on_advance cuida disso); o ausente troca na hora.
 perform public.on_clone('public.mgr_engine_run_v2(bigint,integer,character)',
  array['public.mgr_engine_run_v2(p_fixture bigint, p_to integer, p_interactive character)',
   'a.player_id,jsonb_build_array(a.aggression,a.discipline)',' join public.sim_player_attrs a on a.player_id=mp.player_id',
   t[1],t[2],t[4],t[8],t[5],t[6],
   'p_interactive is distinct from ''h''','p_interactive is distinct from ''a''',
   'if p_interactive=v_oside then v_stop:=''red'';end if;','if p_interactive=v_side then v_stop:=''red'';end if;',
   'if p_interactive = v_side then v_inj_stop := true;'],
  array['public.on_engine_run(p_fixture bigint, p_to integer, p_interactive text)',
   'mp.player_id,jsonb_build_array(mp.agg,mp.disc)','',
   o[1],o[2],o[4],o[8],o[5],o[6],
   'strpos(coalesce(p_interactive,''''),''h'')=0','strpos(coalesce(p_interactive,''''),''a'')=0',
   '','',
   'if strpos(coalesce(p_interactive,''''),v_side)>0 then null;'],
  array[1,1,1,6,11,17,2,1,1,1,1,2,2,1]);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Escalação no pontapé
-- ─────────────────────────────────────────────────────────────────────────────

-- O jogador pode entrar nesta partida? (do clube, sem lesão, sem suspensão na rodada de liga)
create or replace function public.on_can_play(p public.on_players,p_club int,p_fx public.on_fixtures) returns boolean
language sql stable set search_path=public as $$
 select p.club_id=p_club and (p.inj_until is null or p.inj_until<=(p_fx.kickoff at time zone 'America/Sao_Paulo')::date)
  and not(p_fx.comp='L' and p.susp_round is not null and p.susp_round>=p_fx.round)
$$;

-- Monta a escalação do lado a partir da salva: vagas com problema (lesão, suspensão, vendido, vazia) recebem
-- o melhor reserva disponível; o resto da escolha do técnico fica como está. Devolve formação, vagas, banco,
-- táticas, funções e a lista de trocas feitas.
create or replace function public.on_kickoff_lineup(p_club int,p_fx public.on_fixtures) returns jsonb
language plpgsql security definer set search_path=public as $$
declare l public.on_lineups;f public.sim_formations;s jsonb;pid text;used text[]:='{}';v_slots jsonb:='{}';fixes jsonb:='[]';
 old text;v_bench text[];
begin
 select * into l from public.on_lineups where club_id=p_club;
 if l.club_id is null then perform public.on_auto_lineup(p_club);select * into l from public.on_lineups where club_id=p_club;end if;
 select * into f from public.sim_formations where id=l.formation;
 -- primeiro quem continua: titulares aptos ficam onde o técnico pôs
 for s in select e.value from jsonb_array_elements(f.slots) e loop
  old:=l.slots->>(s->>'slot');
  if old is not null and old<>all(used) and exists(select 1 from public.on_players p where p.id=old and public.on_can_play(p,p_club,p_fx)) then
   used:=used||old;v_slots:=v_slots||jsonb_build_object(s->>'slot',old);
  end if;
 end loop;
 -- depois as vagas com problema: melhor reserva (banco primeiro), pela nota no lugar e condição
 for s in select e.value from jsonb_array_elements(f.slots) e where not v_slots ? (e.value->>'slot') loop
  old:=l.slots->>(s->>'slot');
  select p.id into pid from public.on_players p
   left join public.sim_position_fit ft on ft.from_pos=p.pos and ft.to_pos=s->>'pos'
  where p.club_id=p_club and p.id<>all(used) and public.on_can_play(p,p_club,p_fx)
  order by p.id=any(l.bench) desc,
   p.ovr*greatest(coalesce(ft.fit,.5),case when s->>'pos'=any(p.sec) then .97 else 0 end)*(.7+.3*p.cond/100.0) desc,p.id
  limit 1;
  -- sem ninguém apto: entra quem estiver no elenco (melhor jogar com um lesionado do que não ter a partida)
  if pid is null then
   select p.id into pid from public.on_players p where p.club_id=p_club and p.id<>all(used) order by p.inj_until nulls first,p.ovr desc,p.id limit 1;
  end if;
  continue when pid is null; -- elenco com menos de 11: a vaga fica vazia
  used:=used||pid;v_slots:=v_slots||jsonb_build_object(s->>'slot',pid);
  fixes:=fixes||jsonb_build_object('slot',s->>'slot','out',old,'in',pid);
 end loop;
 v_bench:=array(select b from unnest(l.bench) with ordinality u(b,i) join public.on_players p on p.id=u.b
  where u.b<>all(used) and public.on_can_play(p,p_club,p_fx) order by u.i limit 12);
 return jsonb_build_object('formation',f.id,'slots',v_slots,'bench',to_jsonb(v_bench),'tactics',l.tactics,'roles',l.roles,'fixes',fixes);
end $$;

-- Copia o lado para on_match_players (titulares e banco), com nome, número, nota e atributos do motor.
create or replace function public.on_build_side(p_fixture bigint,p_side char,p_club int,p_l jsonb) returns void
language sql security definer set search_path=public as $$
 insert into public.on_match_players(fixture_id,player_id,side,club_id,name,number,nat_pos,ovr,agg,disc,slot,pos,status,starter,fit,cond,rhythm,
  c_att,c_cre,c_def,c_ctl,c_gk,c_fin,c_head,c_pace,c_stam,c_tack,c_str,entered_min)
 select p_fixture,p.id,p_side,p_club,p.name,p.number,p.pos,p.ovr,p.agg,p.disc,x.slot,coalesce(x.pos,p.pos),
  case when x.slot is null then 'bench' else 'on' end,x.slot is not null,
  case when x.slot is null then 1 else public.on_fit(p.id,x.pos) end,p.cond,p.rhythm,
  c[1],c[2],c[3],c[4],c[5],c[6],c[7],c[8],c[9],c[10],c[11],case when x.slot is null then null else 0 end
 from(select s->>'slot' slot,s->>'pos' pos,p_l->'slots'->>(s->>'slot') pid from public.sim_formations fm,jsonb_array_elements(fm.slots) s where fm.id=p_l->>'formation'
  union all select null,null,b from jsonb_array_elements_text(p_l->'bench') b) x
 join public.on_players p on p.id=x.pid
 cross join lateral(select public.on_comp(p.id,p.pos,p.level,p.g) c) k
 on conflict do nothing
$$;

-- Abre a partida no pontapé. Quem chama trava a linha do jogo (on_fixtures).
create or replace function public.on_match_open(p_fx public.on_fixtures) returns void
language plpgsql security definer set search_path=public as $$
declare lh jsonb;la jsonb;sh numeric;sa numeric;th jsonb;ta jsonb;bh boolean;ba boolean;v_dec boolean:=p_fx.comp='C';v_neut boolean:=p_fx.stage='final';
begin
 if exists(select 1 from public.on_matches where fixture_id=p_fx.id) then return;end if;
 select user_id is null into bh from public.on_clubs where id=p_fx.home;
 select user_id is null into ba from public.on_clubs where id=p_fx.away;
 if bh then perform public.on_auto_lineup(p_fx.home);end if;
 if ba then perform public.on_auto_lineup(p_fx.away);end if;
 lh:=public.on_kickoff_lineup(p_fx.home,p_fx);
 la:=public.on_kickoff_lineup(p_fx.away,p_fx);
 insert into public.on_matches(fixture_id,season_id,state) values(p_fx.id,p_fx.season_id,jsonb_build_object(
  'engine_version',2,'referee',round((0.80+random()*0.40)::numeric,3),'seq',0,'score',jsonb_build_array(0,0),'poss',jsonb_build_array(0,0),
  'corners',jsonb_build_array(0,0),'offsides',jsonb_build_array(0,0),
  'subs',jsonb_build_object('h',jsonb_build_object('used',0,'windows',0),'a',jsonb_build_object('used',0,'windows',0)),
  'max_subs',5,'max_windows',3,'neutral',v_neut,'decisive',v_dec,'agg',jsonb_build_array(0,0),
  'extra_time_rule',v_dec,'tie_rule','penalties','et',false,'comp',p_fx.comp,'stage',p_fx.stage,
  'form',jsonb_build_array(round((0.90+random()*0.20)::numeric,3),round((0.90+random()*0.20)::numeric,3)),
  'fixes',jsonb_build_object('h',lh->'fixes','a',la->'fixes'),'sp_bonus',jsonb_build_array(0,0),
  'pen_taker',jsonb_build_object('h',lh->'roles'->>'pen','a',la->'roles'->>'pen'),
  'fk_taker',jsonb_build_object('h',lh->'roles'->>'fk','a',la->'roles'->>'fk'),
  'ck_taker',jsonb_build_object('h',lh->'roles'->>'ck','a',la->'roles'->>'ck'),
  'captain',jsonb_build_object('h',lh->'roles'->>'captain','a',la->'roles'->>'captain')));
 perform public.on_build_side(p_fx.id,'h',p_fx.home,lh);
 perform public.on_build_side(p_fx.id,'a',p_fx.away,la);
 select avg(ovr*fit) filter(where side='h' and status='on'),avg(ovr*fit) filter(where side='a' and status='on') into sh,sa
  from public.on_match_players where fixture_id=p_fx.id;
 th:=public.mgr_tactics_clean(case when bh then public.mgr_ai_tactics(sh-sa,not v_neut) else lh->'tactics' end);
 ta:=public.mgr_tactics_clean(case when ba then public.mgr_ai_tactics(sa-sh,false) else la->'tactics' end);
 update public.on_matches set state=state||jsonb_build_object('tactics',jsonb_build_object('h',th,'a',ta),
  'base_mentality',jsonb_build_array((th->>'mentality')::int,(ta->>'mentality')::int),
  'formation',jsonb_build_array(lh->>'formation',la->>'formation'),'strength',jsonb_build_array(round(sh,1),round(sa,1)))
 where fixture_id=p_fx.id;
 update public.on_fixtures set status='live' where id=p_fx.id and status='sched';
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Pênaltis (mesma regra de mgr_shootout, com sorteio comum)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_shootout(p_fixture bigint,p_minute int) returns int[]
language plpgsql security definer set search_path=public as $$
declare tk text[][]:=array[array[]::text[],array[]::text[]];th text[];ta text[];fin jsonb;gk numeric[];gkp text[];sc int[]:=array[0,0];k int:=0;s int;pid text;done boolean:=false;
begin
 select array_agg(player_id order by c_fin desc,player_id) into th from public.on_match_players where fixture_id=p_fixture and side='h' and status='on' and pos<>'GOL';
 select array_agg(player_id order by c_fin desc,player_id) into ta from public.on_match_players where fixture_id=p_fixture and side='a' and status='on' and pos<>'GOL';
 select jsonb_object_agg(player_id,c_fin) into fin from public.on_match_players where fixture_id=p_fixture;
 select array[coalesce(max(c_gk) filter(where side='h' and pos='GOL' and status='on'),45),coalesce(max(c_gk) filter(where side='a' and pos='GOL' and status='on'),45)],
  array[max(player_id) filter(where side='h' and pos='GOL' and status='on'),max(player_id) filter(where side='a' and pos='GOL' and status='on')]
  into gk,gkp from public.on_match_players where fixture_id=p_fixture;
 th:=coalesce(th,array[gkp[1]]);ta:=coalesce(ta,array[gkp[2]]);
 while not done and k<30 loop
  k:=k+1;
  for s in 1..2 loop
   pid:=case when s=1 then th[1+(k-1)%cardinality(th)] else ta[1+(k-1)%cardinality(ta)] end;
   if random()<greatest(.55,least(.9,.74+.004*(coalesce((fin->>pid)::numeric,50)-gk[3-s]))) then
    sc[s]:=sc[s]+1;perform public.on_event(p_fixture,p_minute,case when s=1 then 'h' else 'a' end,'so_goal',pid);
   else perform public.on_event(p_fixture,p_minute,case when s=1 then 'h' else 'a' end,'so_miss',pid,gkp[3-s]);end if;
   if k<=5 and (sc[1]>sc[2]+(5-k)+case when s=1 then 1 else 0 end or sc[2]>sc[1]+(5-k)) then done:=true;exit;end if;
  end loop;
  if k>=5 and sc[1]<>sc[2] then done:=true;end if;
 end loop;
 return sc;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Fim da partida: placar, classificação, elenco
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_match_finish(p_fixture bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare m public.on_matches;f public.on_fixtures;v_hg int;v_ag int;v_pens int[];motm jsonb;v_sum jsonb;v_w int;v_hook text;
begin
 select * into m from public.on_matches where fixture_id=p_fixture for update;
 if m.summary is not null then return m.summary;end if;
 select * into f from public.on_fixtures where id=p_fixture for update;
 v_hg:=(m.state->'score'->>0)::int;v_ag:=(m.state->'score'->>1)::int;
 if coalesce((m.state->>'decisive')::boolean,false) and v_hg=v_ag then
  v_pens:=public.on_shootout(p_fixture,greatest(m.minute,90));
  update public.on_matches set state=state||jsonb_build_object('pens',to_jsonb(v_pens)) where fixture_id=p_fixture;
 end if;
 perform public.on_rate(p_fixture,true);
 select jsonb_build_object('id',mp.player_id,'name',mp.name,'side',mp.side,'rating',mp.rating,'goals',mp.goals,'assists',mp.assists) into motm
  from public.on_match_players mp where mp.fixture_id=p_fixture and mp.minutes>0 order by mp.rating desc,mp.goals desc,mp.player_id limit 1;
 v_w:=case when v_hg>v_ag or (v_pens is not null and v_pens[1]>v_pens[2]) then f.home when v_ag>v_hg or v_pens is not null then f.away end;
 v_sum:=jsonb_build_object('fixture_id',p_fixture,'home',f.home,'away',f.away,'home_goals',v_hg,'away_goals',v_ag,'pens',to_jsonb(v_pens),
  'winner',v_w,'motm',motm);
 update public.on_matches set status='finished',summary=v_sum,updated_at=now() where fixture_id=p_fixture;

 -- classificação: só na primeira vez que o jogo vira 'done' (terminar duas vezes não soma em dobro)
 update public.on_fixtures set status='done',hg=v_hg,ag=v_ag,pens=to_jsonb(v_pens) where id=p_fixture and status<>'done';
 if found and f.comp='L' then
  update public.on_table t set p=t.p+1,
   w=t.w+(x.gf>x.ga)::int,d=t.d+(x.gf=x.ga)::int,l=t.l+(x.gf<x.ga)::int,gf=t.gf+x.gf,ga=t.ga+x.ga,
   pts=t.pts+case when x.gf>x.ga then 3 when x.gf=x.ga then 1 else 0 end
  from(values(f.home,v_hg,v_ag),(f.away,v_ag,v_hg)) x(club,gf,ga)
  where t.season_id=f.season_id and t.club_id=x.club;
 end if;

 -- condição, ritmo, cartões e lesões voltam para o elenco em uma instrução.
 -- Suspensão: vermelho ou 3º amarelo acumulado barra o jogador na próxima rodada de liga do clube.
 update public.on_players p set
  cond=round(mp.cond)::smallint,
  rhythm=least(100,p.rhythm+case when mp.minutes>=45 then 10 when mp.minutes>0 then 5 else 0 end),
  yellows=case when mp.red>0 or (mp.yellow>0 and (p.yellows+mp.yellow)%3=0) then 0 else p.yellows+mp.yellow end,
  susp_round=case when mp.red>0 or (mp.yellow>0 and mp.red=0 and (p.yellows+mp.yellow)%3=0)
   then (select min(o.round) from public.on_fixtures o where o.season_id=f.season_id and o.comp='L' and o.kickoff>f.kickoff and (o.home=mp.club_id or o.away=mp.club_id))
   else p.susp_round end,
  inj_until=case when mp.injured then (now() at time zone 'America/Sao_Paulo')::date+1+floor(random()*5)::int else p.inj_until end
 from public.on_match_players mp
 where mp.fixture_id=p_fixture and p.id=mp.player_id and p.club_id=mp.club_id and mp.status<>'bench';
 -- fases seguintes (bilheteria, copa...)
 for v_hook in select unnest(finish_hooks) from public.on_config loop
  execute format('select public.%I($1)',v_hook) using p_fixture;
 end loop;
 return v_sum;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Avanço do motor até o relógio
-- p_inter: lados presentes ('h','a','ha','') ou nulo (ninguém assistindo: cálculo com menos eventos).
-- Quem chama trava a linha de on_matches.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_advance(p_fixture bigint,p_now timestamptz,p_inter text) returns void
language plpgsql security definer set search_path=public as $$
declare m public.on_matches;k timestamptz;tgt int;v_stop text;r record;err text;v_first boolean;n int:=0;
begin
 select kickoff into k from public.on_fixtures where id=p_fixture;
 loop
  select * into m from public.on_matches where fixture_id=p_fixture;
  exit when m.status<>'live';
  n:=n+1;exit when n>8;
  tgt:=public.on_clock(k,p_now,coalesce((m.state->>'et')::boolean,false));
  -- lesionado sem troca: o assistente troca se o lado está ausente ou se o técnico não trocou em 8 minutos
  for r in select player_id,pos,side,left_min from public.on_match_players
   where fixture_id=p_fixture and status='injured_off' and slot is not null loop
   if strpos(coalesce(p_inter,''),r.side)=0 or m.minute>=r.left_min+8 then
    err:=public.on_do_sub(p_fixture,r.side,r.player_id,public.on_best_bench(p_fixture,r.side,r.pos),m.minute,true,'troca do auxiliar');
    if err is not null then update public.on_match_players set slot=null where fixture_id=p_fixture and player_id=r.player_id;end if;
   end if;
  end loop;
  if m.minute>=tgt then
   -- fim do tempo normal ou da prorrogação
   if m.minute>=90 and tgt>=90 and not coalesce((m.state->>'et')::boolean,false)
    and coalesce((m.state->>'extra_time_rule')::boolean,false)
    and (m.state->'score'->>0)::int=(m.state->'score'->>1)::int then
    update public.on_matches set state=state||'{"et":true}' where fixture_id=p_fixture;
    perform public.on_event(p_fixture,90,null,'et');
    continue;
   end if;
   if m.minute>=(case when coalesce((m.state->>'et')::boolean,false) then 120 else 90 end) then
    perform public.on_event(p_fixture,m.minute,null,'ft');
    perform public.on_match_finish(p_fixture);
   end if;
   exit;
  end if;
  v_stop:=public.on_engine_run(p_fixture,tgt,p_inter);
  if v_stop='ht' and not coalesce((select (state->>'ht')::boolean from public.on_matches where fixture_id=p_fixture),false) then
   update public.on_matches set state=state||'{"ht":true}' where fixture_id=p_fixture;
   perform public.on_event(p_fixture,45,null,'ht');
  end if;
  perform public.on_rate(p_fixture);
 end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Resposta para a tela
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_match_payload(p_fixture bigint,p_after_seq int,p_side char) returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('server_now',now(),'fixture_id',f.id,'kickoff',f.kickoff,'comp',f.comp,'round',f.round,'stage',f.stage,
  'status',coalesce(m.status,case when f.status='done' then 'finished' else 'sched' end),'minute',coalesce(m.minute,0),'my_side',p_side,
  'home',jsonb_build_object('id',h.id,'name',h.name,'short',h.short,'colors',h.colors,'bot',h.user_id is null),
  'away',jsonb_build_object('id',a.id,'name',a.name,'short',a.short,'colors',a.colors,'bot',a.user_id is null),
  'present',jsonb_build_object('h',m.seen_h>now()-interval '90 seconds','a',m.seen_a>now()-interval '90 seconds'),
  'score',m.state->'score','et',coalesce(m.state->'et','false'),'pens',m.state->'pens','decisive',m.state->'decisive',
  'tactics',m.state->'tactics','formation',m.state->'formation','subs',m.state->'subs','max_subs',m.state->'max_subs',
  'max_windows',m.state->'max_windows','fixes',case when p_side is null then null else m.state->'fixes'->p_side end,
  'events',coalesce((select jsonb_agg(jsonb_build_object('seq',e.seq,'minute',e.minute,'side',e.side,'kind',e.kind,'player',e.player_id,
    'player_name',p1.name,'player2',e.player2_id,'player2_name',p2.name,'detail',e.detail) order by e.seq)
   from public.on_match_events e
   left join public.on_match_players p1 on p1.fixture_id=e.fixture_id and p1.player_id=e.player_id
   left join public.on_match_players p2 on p2.fixture_id=e.fixture_id and p2.player_id=e.player2_id
   where e.fixture_id=f.id and e.seq>coalesce(p_after_seq,0)),'[]'::jsonb),
  'stats',case when m.fixture_id is null then null else(select jsonb_build_object(
   'poss',jsonb_build_array(round(100.0*(m.state->'poss'->>0)::int/greatest((m.state->'poss'->>0)::int+(m.state->'poss'->>1)::int,1)),
    100-round(100.0*(m.state->'poss'->>0)::int/greatest((m.state->'poss'->>0)::int+(m.state->'poss'->>1)::int,1))),
   'fouls',jsonb_build_array(coalesce(sum(fouls) filter(where side='h'),0),coalesce(sum(fouls) filter(where side='a'),0)),
   'saves',jsonb_build_array(coalesce(sum(saves) filter(where side='h'),0),coalesce(sum(saves) filter(where side='a'),0)),
   'corners',m.state->'corners','offsides',m.state->'offsides')
   from public.on_match_players where fixture_id=f.id) end,
  'players',coalesce((select jsonb_agg(jsonb_build_object('id',mp.player_id,'name',mp.name,'number',mp.number,'side',mp.side,'club_id',mp.club_id,
    'slot',mp.slot,'pos',mp.pos,'natural',mp.nat_pos,'status',mp.status,'starter',mp.starter,'fit',mp.fit,'cond',round(mp.cond),
    'rating',mp.rating,'goals',mp.goals,'assists',mp.assists,'yellow',mp.yellow,'red',mp.red,'injured',mp.injured,'minutes',mp.minutes,
    'overall',round(mp.ovr*mp.fit),'ovr',mp.ovr) order by mp.side,(mp.status='on') desc,mp.slot,mp.number)
   from public.on_match_players mp where mp.fixture_id=f.id),'[]'::jsonb),
  'summary',m.summary)
 from public.on_fixtures f
 join public.on_clubs h on h.id=f.home join public.on_clubs a on a.id=f.away
 left join public.on_matches m on m.fixture_id=f.id
 where f.id=p_fixture
$$;

-- Lado do clube na partida ('h', 'a' ou nulo para espectador).
create or replace function public.on_side_of(p_fx public.on_fixtures,p_club int) returns char
language sql immutable as $$ select case when p_fx.home=p_club then 'h' when p_fx.away=p_club then 'a' end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Funções chamadas pelo app
-- ─────────────────────────────────────────────────────────────────────────────

-- Chamada pela tela a cada 40 s. Abre a partida se o horário chegou, marca o técnico como presente, avança o
-- motor até o minuto do relógio e devolve só os eventos novos. Sem p_fixture: a partida atual do clube.
-- Não espera por trava: se outra chamada está avançando a partida, devolve a leitura e tenta de novo depois.
create or replace function public.on_match_poll(p_fixture bigint default null,p_after_seq int default 0) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();f public.on_fixtures;m public.on_matches;sd char;v_inter text;v_id bigint;
begin
 if p_fixture is null then
  select * into f from public.on_fixtures x where x.season_id=c.season_id and (x.home=c.id or x.away=c.id)
   and (x.status='live' or (x.status='sched' and x.kickoff<=now())) order by x.kickoff limit 1;
  if f.id is null then
   select * into f from public.on_fixtures x where x.season_id=c.season_id and (x.home=c.id or x.away=c.id) and x.status<>'done' order by x.kickoff limit 1;
  end if;
  if f.id is null then raise exception 'Sem partida para mostrar';end if;
 else
  select * into f from public.on_fixtures x where x.id=p_fixture and x.season_id=c.season_id;
  if f.id is null then raise exception 'Partida não encontrada';end if;
 end if;
 sd:=public.on_side_of(f,c.id);v_id:=f.id;
 if f.kickoff>now() or f.status='done' then return public.on_match_payload(f.id,p_after_seq,sd);end if;

 if not exists(select 1 from public.on_matches where fixture_id=f.id) then
  select * into f from public.on_fixtures where id=f.id for update skip locked;
  if f.id is null then return public.on_match_payload(v_id,p_after_seq,sd)||'{"busy":true}';end if;
  perform public.on_match_open(f);
 end if;
 select * into m from public.on_matches where fixture_id=f.id for update skip locked;
 if m.fixture_id is null then return public.on_match_payload(f.id,p_after_seq,sd)||'{"busy":true}';end if;
 if m.status='live' then
  if sd='h' then update public.on_matches set seen_h=now() where fixture_id=f.id;m.seen_h:=now();
  elsif sd='a' then update public.on_matches set seen_a=now() where fixture_id=f.id;m.seen_a:=now();end if;
  v_inter:=case when m.seen_h>now()-interval '90 seconds' then 'h' else '' end||case when m.seen_a>now()-interval '90 seconds' then 'a' else '' end;
  perform public.on_advance(f.id,now(),v_inter);
 end if;
 return public.on_match_payload(f.id,p_after_seq,sd);
end $$;

-- Mudanças do técnico (táticas, formação, substituições, posições). Entram no minuto em que o servidor está.
-- p_req identifica o envio: o mesmo p_req duas vezes (duplo clique, rede) é ignorado na segunda.
-- A trava na linha da partida põe dois envios simultâneos em fila; nenhum se perde.
create or replace function public.on_match_act(p_fixture bigint,p_req text,p_changes jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();f public.on_fixtures;m public.on_matches;sd char;t jsonb;err text;sub jsonb;first boolean:=true;
begin
 if p_req is null or char_length(p_req) not between 8 and 64 then raise exception 'Envio sem identificador';end if;
 select * into f from public.on_fixtures where id=p_fixture and season_id=c.season_id;
 sd:=public.on_side_of(f,c.id);
 if sd is null then raise exception 'Você não joga esta partida';end if;
 select * into m from public.on_matches where fixture_id=p_fixture for update;
 if m.fixture_id is null then raise exception 'A partida ainda não começou';end if;
 if p_req=any(m.reqs) then return public.on_match_payload(p_fixture,0,sd)||jsonb_build_object('applied_at',m.minute,'repeated',true);end if;
 if m.status<>'live' then raise exception 'A partida já terminou';end if;
 if sd='h' then update public.on_matches set seen_h=now() where fixture_id=p_fixture;
 else update public.on_matches set seen_a=now() where fixture_id=p_fixture;end if;
 perform public.on_advance(p_fixture,now(),
  case when sd='h' or m.seen_h>now()-interval '90 seconds' then 'h' else '' end||case when sd='a' or m.seen_a>now()-interval '90 seconds' then 'a' else '' end);
 select * into m from public.on_matches where fixture_id=p_fixture;
 if m.status<>'live' then raise exception 'A partida já terminou';end if;

 if p_changes ? 'tactics' then
  t:=public.mgr_tactics_clean(coalesce(m.state->'tactics'->sd,'{}'::jsonb)||(p_changes->'tactics'));
  update public.on_matches set state=jsonb_set(jsonb_set(state,array['tactics',sd],t),array['base_mentality',case when sd='h' then '0' else '1' end],
   to_jsonb((t->>'mentality')::int)) where fixture_id=p_fixture;
  perform public.on_event(p_fixture,m.minute,sd,'tactic',null,null,'Ajuste tático');
 end if;
 if p_changes ? 'formation' and p_changes->>'formation' is distinct from (m.state->'formation'->>(case when sd='h' then 0 else 1 end)) then
  err:=public.on_change_formation(p_fixture,sd,p_changes->>'formation',m.minute);
  if err is not null then raise exception '%',err;end if;
 end if;
 for sub in select * from jsonb_array_elements(coalesce(p_changes->'subs','[]'::jsonb)) loop
  err:=public.on_do_sub(p_fixture,sd,sub->>'out',sub->>'in',m.minute,first);
  if err is not null then raise exception '%',err;end if;
  first:=false;
 end loop;
 if p_changes ? 'slots' then
  err:=public.on_set_positions(p_fixture,sd,p_changes->'slots',m.minute);
  if err is not null then raise exception '%',err;end if;
 end if;
 perform public.on_rate(p_fixture);
 update public.on_matches set reqs=(reqs||p_req)[greatest(1,cardinality(reqs)-38):] where fixture_id=p_fixture;
 return public.on_match_payload(p_fixture,0,sd)||jsonb_build_object('applied_at',m.minute);
end $$;

-- Troca de formação durante o jogo: cada um vai para a vaga onde rende mais (mesma ideia de mgr_change_formation).
create or replace function public.on_change_formation(p_fixture bigint,p_side char,p_form text,p_minute int) returns text
language plpgsql security definer set search_path=public as $$
declare v_slots jsonb;v_n int;r record;v_pid text;v_used text[]:='{}';v_k int:=0;
begin
 select slots into v_slots from public.sim_formations where id=p_form;
 if v_slots is null then return 'Formação inválida.';end if;
 select count(*) into v_n from public.on_match_players where fixture_id=p_fixture and side=p_side and status='on';
 update public.on_match_players set slot=null where fixture_id=p_fixture and side=p_side and status='on';
 for r in select s->>'slot' slot,s->>'pos' pos from jsonb_array_elements(v_slots) s
  order by case s->>'pos' when 'GOL' then 1 when 'ZAG' then 2 when 'VOL' then 3 when 'LD' then 4 when 'LE' then 4 when 'MC' then 5 when 'MEI' then 6 when 'ATA' then 7 else 8 end loop
  exit when v_k>=v_n;
  select mp.player_id into v_pid from public.on_match_players mp left join public.sim_position_fit ft on ft.from_pos=mp.nat_pos and ft.to_pos=r.pos
   where mp.fixture_id=p_fixture and mp.side=p_side and mp.status='on' and mp.player_id<>all(v_used)
   order by mp.ovr*coalesce(ft.fit,.5) desc,mp.player_id limit 1;
  exit when v_pid is null;
  update public.on_match_players set slot=r.slot,pos=r.pos,fit=public.on_fit(v_pid,r.pos) where fixture_id=p_fixture and player_id=v_pid;
  v_used:=v_used||v_pid;v_k:=v_k+1;v_pid:=null;
 end loop;
 update public.on_matches set state=jsonb_set(state,array['formation',case when p_side='h' then '0' else '1' end],to_jsonb(p_form)) where fixture_id=p_fixture;
 perform public.on_event(p_fixture,p_minute,p_side,'tactic',null,null,'Formação '||p_form);
 return null;
end $$;

-- Capitão e cobradores (pênalti, falta, escanteio). Valem a partir da próxima partida.
create or replace function public.on_roles_save(p_roles jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);v jsonb:='{}';k text;
begin
 foreach k in array array['captain','pen','fk','ck'] loop
  if p_roles->>k is not null then
   if not exists(select 1 from public.on_players where id=p_roles->>k and club_id=c.id) then raise exception 'Jogador fora do seu elenco';end if;
   v:=v||jsonb_build_object(k,p_roles->>k);
  end if;
 end loop;
 update public.on_lineups set roles=v,updated_at=now() where club_id=c.id;
 return public.on_squad();
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cron (1 por minuto)
-- Na maior parte das vezes faz uma consulta em índice e sai. Recupera a condição uma vez por dia; abre jogos
-- que ninguém abriu e termina, em blocos de 45 minutos de jogo, as partidas que ninguém está assistindo.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_tick(p_now timestamptz default now()) returns int
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
   -- recuperação diária: sem ela o elenco desgasta e nunca recupera
   update public.on_players p set cond=least(100,p.cond+35),rhythm=greatest(30,p.rhythm-2)
    from public.on_clubs k where k.season_id=s.id and p.club_id=k.id and (p.cond<100 or p.rhythm>30);
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Leituras da Fase 1 com o que a Fase 2 precisa
-- ─────────────────────────────────────────────────────────────────────────────

-- Elenco: suspensão e cartões; partida ao vivo do clube (a tela avisa que mexer aqui não muda o jogo).
create or replace function public.on_squad() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();v_next public.on_fixtures;
begin
 select * into v_next from public.on_fixtures x where x.season_id=c.season_id and (x.home=c.id or x.away=c.id) and x.status<>'done' order by x.kickoff limit 1;
 return jsonb_build_object(
  'club',jsonb_build_object('id',c.id,'name',c.name,'short',c.short,'colors',c.colors,'cash',c.cash,'reserved',c.reserved),
  'live_fixture',case when v_next.kickoff<=now() then v_next.id end,
  'next',case when v_next.id is null then null else jsonb_build_object('id',v_next.id,'comp',v_next.comp,'round',v_next.round,'kickoff',v_next.kickoff) end,
  'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'sec',p.sec,'age',p.age,'ovr',p.ovr,'pot',p.pot,
    'cond',p.cond,'rhythm',p.rhythm,'number',p.number,'wage',p.wage,'contract_end',p.contract_end,'star',p.star,'g',p.g,'xp',p.xp,'yellows',p.yellows,
    'injured',p.inj_until is not null and p.inj_until>(now() at time zone 'America/Sao_Paulo')::date,'inj_until',p.inj_until,
    'suspended',v_next.comp='L' and p.susp_round is not null and p.susp_round>=v_next.round,
    'value',public.on_value(p.ovr,p.age,p.pot)) order by sp.sort,p.ovr desc,p.id)
   from public.on_players p join public.sim_positions sp on sp.code=p.pos where p.club_id=c.id),'[]'::jsonb),
  'lineup',(select jsonb_build_object('formation',l.formation,'slots',l.slots,'bench',l.bench,'tactics',l.tactics,'roles',l.roles)
   from public.on_lineups l where l.club_id=c.id));
end $$;

-- Status: o próximo jogo diz se já está ao vivo.
create or replace function public.on_status() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_uid uuid:=auth.uid();s public.on_seasons;c public.on_clubs;a text;
begin
 if v_uid is null then raise exception 'Entre na sua conta para jogar';end if;
 if not public.on_gate() then
  return jsonb_build_object('server_now',now(),'access','unavailable','season',null,'club',null,'next',null);
 end if;
 select x.* into s from public.on_seasons x where x.status='live';
 select x.state into a from public.on_access x where x.user_id=v_uid;
 if s.id is not null then select k.* into c from public.on_clubs k where k.season_id=s.id and k.user_id=v_uid;end if;
 return jsonb_build_object('server_now',now(),
  'access',case when c.id is not null then 'playing' when a is not null then 'queued' else 'none' end,
  'season',case when s.id is null then null else jsonb_build_object('id',s.id,'kind',s.kind,'starts_on',s.starts_on) end,
  'club',case when c.id is null then null else jsonb_build_object('id',c.id,'name',c.name,'short',c.short,'colors',c.colors,
   'cash',c.cash,'reserved',c.reserved,'draft_step',c.draft_step) end,
  'position',case when c.id is null then null else(select x.pos from(select t.club_id,row_number() over(order by t.pts desc,t.gf-t.ga desc,t.gf desc,k.name) pos
    from public.on_table t join public.on_clubs k on k.id=t.club_id where t.season_id=s.id) x where x.club_id=c.id) end,
  'next',case when c.id is null then null else(select jsonb_build_object('id',f.id,'comp',f.comp,'round',f.round,'stage',f.stage,'kickoff',f.kickoff,
    'status',f.status,'live',f.kickoff<=now(),'at_home',f.home=c.id,'opp',jsonb_build_object('id',o.id,'name',o.name,'short',o.short,'colors',o.colors,'bot',o.user_id is null))
   from public.on_fixtures f join public.on_clubs o on o.id=case when f.home=c.id then f.away else f.home end
   where f.season_id=s.id and f.status<>'done' and (f.home=c.id or f.away=c.id) order by f.kickoff limit 1) end,
  -- sem jogo hoje (eliminado ou de folga na copa), mas há jogos no dia: a tela mostra "sem jogo hoje"
  'rest_today',c.id is not null
   and not exists(select 1 from public.on_fixtures f where f.season_id=s.id and c.id in(f.home,f.away) and (f.kickoff at time zone s.tz)::date=(now() at time zone s.tz)::date)
   and exists(select 1 from public.on_fixtures f where f.season_id=s.id and (f.kickoff at time zone s.tz)::date=(now() at time zone s.tz)::date),
  'last',case when c.id is null then null else(select jsonb_build_object('id',f.id,'hg',f.hg,'ag',f.ag,'at_home',f.home=c.id,
    'opp',jsonb_build_object('name',o.name,'short',o.short,'colors',o.colors))
   from public.on_fixtures f join public.on_clubs o on o.id=case when f.home=c.id then f.away else f.home end
   where f.season_id=s.id and f.status='done' and (f.home=c.id or f.away=c.id) order by f.kickoff desc limit 1) end);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Permissões
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on function public.on_clock(timestamptz,timestamptz,boolean),public.on_comp(text,text,numeric,smallint[]),public.on_fit(text,text),
 public.on_best_bench(bigint,char,text),public.on_clone(regprocedure,text[],text[],int[]),public.on_event(bigint,integer,character,text,text,text,text),
 public.on_do_sub(bigint,character,text,text,integer,boolean,text),public.on_set_positions(bigint,character,jsonb,integer),public.on_rate(bigint,boolean),
 public.on_ai_manage(bigint,character,integer),public.on_engine_run(bigint,integer,text),public.on_can_play(public.on_players,int,public.on_fixtures),
 public.on_kickoff_lineup(int,public.on_fixtures),public.on_build_side(bigint,char,int,jsonb),public.on_match_open(public.on_fixtures),
 public.on_shootout(bigint,int),public.on_match_finish(bigint),public.on_advance(bigint,timestamptz,text),public.on_match_payload(bigint,int,char),
 public.on_side_of(public.on_fixtures,int),public.on_change_formation(bigint,char,text,int),public.on_tick(timestamptz)
 from public,anon,authenticated;
revoke all on function public.on_match_poll(bigint,int),public.on_match_act(bigint,text,jsonb),public.on_roles_save(jsonb) from public,anon;
grant execute on function public.on_match_poll(bigint,int),public.on_match_act(bigint,text,jsonb),public.on_roles_save(jsonb) to authenticated;

-- Agenda o cron (só onde existe pg_cron; o banco de testes não tem).
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.unschedule(jobid) from cron.job where jobname='on_tick';
  perform cron.schedule('on_tick','* * * * *','select public.on_tick()');
 end if;
end $$;
