-- Pacote de publicação do modo online, fases 2 a 5 (gerado de supabase/online/02..05).
-- Rodar inteiro no SQL Editor ou pela API, como administrador. Tudo ou nada.
begin;

-- ===== supabase/online/02_match.sql =====
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

-- ===== supabase/online/03_market.sql =====
-- MODO ONLINE — Fase 3: mercado de leilões.
--
-- Lista rotativa de jogadores do sistema (24 por dia, cada leilão de 5 a 10 minutos) mais os jogadores que os
-- técnicos colocam à venda. Todos veem os lances. O lance fica reservado no caixa do clube (on_clubs.reserved)
-- e é liberado quando outro clube cobre. Cada lance novo garante pelo menos 30 s até o fim, até um limite.
--
-- Travas: sempre o lote primeiro e depois os clubes envolvidos em ordem de id (dois lances no mesmo segundo
-- nunca esperam um pelo outro para sempre). Custo: a tela consulta a cada 5 s só perto do fim de um lote.

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabelas
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.on_clubs add column if not exists debt bigint not null default 0 check (debt>=0);
alter table public.on_config add column if not exists lot_minutes int[] not null default array[5,10]; -- duração dos lotes do sistema
alter table public.on_config add column if not exists lot_extend_max interval not null default interval '10 minutes'; -- prorrogação máxima
alter table public.on_config add column if not exists user_lot_minutes int not null default 10;

create table if not exists public.on_lots(
 id bigint generated by default as identity primary key,
 season_id smallint not null references public.on_seasons(id) on delete cascade,
 player_id text not null references public.on_players(id) on delete cascade,
 seller int references public.on_clubs(id) on delete set null, -- nulo = lote do sistema
 start_price bigint not null check (start_price>0),
 best_bid bigint,
 best_club int references public.on_clubs(id) on delete set null,
 bids smallint not null default 0,
 opens_at timestamptz not null,
 ends_at timestamptz not null,
 hard_end timestamptz not null,
 status text not null default 'open' check (status in('open','sold','unsold','cancelled')),
 settled_at timestamptz
);
create index if not exists on_lots_open on public.on_lots(season_id,ends_at) where status='open';
create unique index if not exists on_lots_one_open on public.on_lots(player_id) where status='open';

create table if not exists public.on_bids(
 id bigint generated by default as identity primary key,
 lot_id bigint not null references public.on_lots(id) on delete cascade,
 club_id int not null references public.on_clubs(id) on delete cascade,
 amount bigint not null,
 at timestamptz not null default now()
);
create index if not exists on_bids_lot on public.on_bids(lot_id,id desc);

-- Extrato do caixa: toda entrada e saída de dinheiro do clube.
create table if not exists public.on_ledger(
 id bigint generated by default as identity primary key,
 club_id int not null references public.on_clubs(id) on delete cascade,
 kind text not null,
 amount bigint not null,
 note text,
 at timestamptz not null default now()
);
create index if not exists on_ledger_club on public.on_ledger(club_id,id desc);

-- Avisos para o técnico (vendeu, comprou, vaga preenchida, salário atrasado...).
create table if not exists public.on_news(
 id bigint generated by default as identity primary key,
 club_id int not null references public.on_clubs(id) on delete cascade,
 kind text not null,
 text text not null,
 at timestamptz not null default now()
);
create index if not exists on_news_club on public.on_news(club_id,id desc);

alter table public.on_lots enable row level security;
alter table public.on_bids enable row level security;
alter table public.on_ledger enable row level security;
alter table public.on_news enable row level security;
revoke all on public.on_lots,public.on_bids,public.on_ledger,public.on_news from anon,authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Dinheiro
-- ─────────────────────────────────────────────────────────────────────────────

-- Movimenta o caixa e grava o extrato. Entrada paga primeiro a dívida. Saída usa só o dinheiro livre
-- (caixa menos lances reservados); com p_allow_debt o que faltar vira dívida, senão a operação é recusada.
-- O caixa nunca fica negativo. Quem chama já travou a linha do clube.
create or replace function public.on_money(p_club int,p_amount bigint,p_kind text,p_note text default null,p_allow_debt boolean default false) returns bigint
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs;pay bigint;v_short bigint:=0;
begin
 select * into c from public.on_clubs where id=p_club;
 if p_amount>=0 then
  pay:=least(c.debt,p_amount);
  update public.on_clubs set debt=debt-pay,cash=cash+p_amount-pay where id=p_club;
  if pay>0 then insert into public.on_news(club_id,kind,text) values(p_club,'debt',format('Dívida reduzida em $ %s.',pay));end if;
 else
  if c.cash-c.reserved< -p_amount then
   if not p_allow_debt then raise exception 'Caixa insuficiente';end if;
   v_short:=-p_amount-greatest(0,c.cash-c.reserved);
  end if;
  update public.on_clubs set cash=cash+p_amount+v_short,debt=debt+v_short where id=p_club;
 end if;
 insert into public.on_ledger(club_id,kind,amount,note) values(p_club,p_kind,p_amount,p_note);
 return v_short;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Regras de elenco
-- ─────────────────────────────────────────────────────────────────────────────

-- O jogador está numa partida ao vivo agora?
create or replace function public.on_in_live(p_player text) returns boolean
language sql stable set search_path=public as $$
 select exists(select 1 from public.on_match_players mp join public.on_matches m on m.fixture_id=mp.fixture_id and m.status='live'
  where mp.player_id=p_player)
$$;

-- Tira da escalação salva quem não é mais do clube e preenche a vaga com o melhor disponível.
-- Devolve os nomes de quem entrou (para o aviso ao técnico).
create or replace function public.on_lineup_repair(p_club int) returns text[]
language plpgsql security definer set search_path=public as $$
declare l public.on_lineups;f public.sim_formations;s jsonb;pid text;used text[];v_slots jsonb:='{}';v_in text[]:='{}';
begin
 select * into l from public.on_lineups where club_id=p_club for update;
 if l.club_id is null then return v_in;end if;
 select * into f from public.sim_formations where id=l.formation;
 used:=array(select e.value from jsonb_each_text(l.slots) e join public.on_players p on p.id=e.value and p.club_id=p_club);
 for s in select e.value from jsonb_array_elements(f.slots) e loop
  pid:=l.slots->>(s->>'slot');
  if pid is null or not exists(select 1 from public.on_players where id=pid and club_id=p_club) then
   select p.id into pid from public.on_players p left join public.sim_position_fit ft on ft.from_pos=p.pos and ft.to_pos=s->>'pos'
    where p.club_id=p_club and p.id<>all(used)
    order by p.id=any(l.bench) desc,p.ovr*greatest(coalesce(ft.fit,.5),case when s->>'pos'=any(p.sec) then .97 else 0 end) desc,p.id limit 1;
   if pid is null then continue;end if;
   used:=used||pid;
   v_in:=v_in||(select name from public.on_players where id=pid);
  end if;
  v_slots:=v_slots||jsonb_build_object(s->>'slot',pid);
 end loop;
 update public.on_lineups set slots=v_slots,
  bench=array(select b from unnest(l.bench) with ordinality u(b,i) join public.on_players p on p.id=u.b and p.club_id=p_club
   where u.b<>all(used) order by u.i limit 12),updated_at=now()
 where club_id=p_club;
 return v_in;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Lances
-- ─────────────────────────────────────────────────────────────────────────────

-- Passo mínimo: 5% do lance atual, no mínimo $ 500.
create or replace function public.on_min_bid(l public.on_lots) returns bigint
language sql immutable as $$
 select case when l.best_bid is null then l.start_price else l.best_bid+greatest(500,ceil(l.best_bid*.05))::bigint end
$$;

-- Lance de um clube (humano ou bot). Trava o lote e depois os clubes em ordem de id.
create or replace function public.on_bid_as(p_club int,p_lot bigint,p_amount bigint,p_now timestamptz default now()) returns void
language plpgsql security definer set search_path=public as $$
declare l public.on_lots;c public.on_clubs;v_prev int;v_extra bigint;v_roster int;
begin
 select * into l from public.on_lots where id=p_lot for update;
 if l.id is null or l.status<>'open' or p_now<l.opens_at or p_now>=l.ends_at then raise exception 'Leilão encerrado';end if;
 if l.seller=p_club then raise exception 'Você não pode dar lance no seu próprio jogador';end if;
 if p_amount is null or p_amount<public.on_min_bid(l) then raise exception 'O lance mínimo agora é $ %',public.on_min_bid(l);end if;
 v_prev:=l.best_club;
 perform 1 from public.on_clubs where id in(p_club,coalesce(v_prev,p_club)) order by id for update;
 select * into c from public.on_clubs where id=p_club;
 if c.debt>0 then raise exception 'Clube com dívida não pode dar lances. Pague a dívida primeiro.';end if;
 select count(*)+(select count(*) from public.on_lots x where x.best_club=p_club and x.status='open' and x.id<>l.id) into v_roster
  from public.on_players where club_id=p_club;
 if v_roster>=28 then raise exception 'Elenco cheio: com 28 jogadores (contando lances na frente) não dá para comprar';end if;
 v_extra:=p_amount-case when v_prev=p_club then l.best_bid else 0 end;
 if c.cash-c.reserved<v_extra then raise exception 'Caixa livre insuficiente para esse lance';end if;
 if v_prev is not null and v_prev<>p_club then
  update public.on_clubs set reserved=reserved-l.best_bid where id=v_prev;
 end if;
 update public.on_clubs set reserved=reserved+v_extra where id=p_club;
 update public.on_lots set best_bid=p_amount,best_club=p_club,bids=bids+1,
  ends_at=least(hard_end,greatest(ends_at,p_now+interval '30 seconds')) where id=l.id;
 insert into public.on_bids(lot_id,club_id,amount,at) values(l.id,p_club,p_amount,p_now);
end $$;

-- Fecha um lote vencido: entrega o jogador e o dinheiro, ou devolve/encerra sem venda.
-- Jogador em partida ao vivo só é entregue depois do apito final (o lote espera).
create or replace function public.on_lot_settle(p_lot bigint,p_now timestamptz default now()) returns text
language plpgsql security definer set search_path=public as $$
declare l public.on_lots;p public.on_players;v_buyer int;v_price bigint;v_in text[];v_value bigint;
begin
 select * into l from public.on_lots where id=p_lot for update skip locked;
 if l.id is null or l.status<>'open' or l.ends_at>p_now then return null;end if;
 select * into p from public.on_players where id=l.player_id for update;
 if public.on_in_live(p.id) then return 'wait';end if;
 v_buyer:=l.best_club;v_price:=l.best_bid;
 -- jogador de técnico sem lances: um bot compra por 60% a 75% do valor
 if v_buyer is null and l.seller is not null then
  v_value:=public.on_value(p.ovr,p.age,p.pot);
  v_price:=greatest(l.start_price/2,round(v_value*(.60+random()*.15)))::bigint;
  select k.id into v_buyer from public.on_clubs k where k.season_id=l.season_id and k.user_id is null and k.cash-k.reserved>=v_price
   and (select count(*) from public.on_players x where x.club_id=k.id)<28 order by random() limit 1;
  if v_buyer is not null then
   perform 1 from public.on_clubs where id in(v_buyer,l.seller) order by id for update;
   update public.on_clubs set reserved=reserved+v_price where id=v_buyer;
  end if;
 end if;
 if v_buyer is null then
  update public.on_lots set status='unsold',settled_at=p_now where id=l.id;
  if l.seller is null then update public.on_players set club_id=null where id=p.id and club_id is null;
  else insert into public.on_news(club_id,kind,text) values(l.seller,'market',format('%s não recebeu lances e continua no elenco.',p.name));end if;
  return 'unsold';
 end if;
 perform 1 from public.on_clubs where id in(v_buyer,coalesce(l.seller,v_buyer)) order by id for update;
 -- comprador: o valor reservado sai do caixa
 update public.on_clubs set reserved=reserved-v_price where id=v_buyer;
 perform public.on_money(v_buyer,-v_price,'buy',p.name);
 if l.seller is not null then
  perform public.on_money(l.seller,v_price,'sell',p.name);
  if p.club_id<>l.seller then raise exception 'Jogador mudou de clube durante o leilão';end if;
 end if;
 -- entra no elenco do comprador fora da escalação, com número livre
 update public.on_players set club_id=v_buyer,
  number=(select min(n) from generate_series(1,99) n where n not in(select coalesce(x.number,0) from public.on_players x where x.club_id=v_buyer)),
  susp_round=null,yellows=0
 where id=p.id;
 update public.on_lots set status='sold',settled_at=p_now,best_club=v_buyer,best_bid=v_price where id=l.id;
 insert into public.on_news(club_id,kind,text) values(v_buyer,'market',format('%s chegou ao clube por $ %s. Ele ficou fora da escalação.',p.name,v_price));
 if l.seller is not null then
  v_in:=public.on_lineup_repair(l.seller);
  insert into public.on_news(club_id,kind,text) values(l.seller,'market',format('%s foi vendido por $ %s.%s',p.name,v_price,
   case when cardinality(v_in)>0 then ' '||array_to_string(v_in,', ')||' entrou na vaga dele.' else '' end));
 end if;
 return 'sold';
end $$;

-- Jogador novo do sistema para leilão (sem clube).
create or replace function public.on_gen_free(p_seed text) returns text
language sql security definer set search_path=public as $$
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end,agg,disc)
 select null,public.cw_regen_name('BRA',p_seed),(array['GOL','LD','ZAG','ZAG','LE','VOL','MC','MEI','PD','PE','ATA','ATA'])[1+floor(public.sim_hash01(p_seed||':p')*12)::int],
  a.age,a.lvl,least(94,a.lvl+floor(public.sim_hash01(p_seed||':pot')*case when a.age<23 then 14 else 5 end)::int),a.lvl,public.on_wage(a.lvl),
  (select max(id) from public.on_seasons)+1+floor(public.sim_hash01(p_seed||':ct')*2)::int,
  35+floor(public.sim_hash01(p_seed||':agg')*40)::int,40+floor(public.sim_hash01(p_seed||':disc')*45)::int
 from(select 18+floor(public.sim_hash01(p_seed||':age')*15)::int age,
  60+floor(power(public.sim_hash01(p_seed||':lvl'),1.6)*22)::int lvl) a
 returning id
$$;

-- Gancho do cron: lotes do dia, lances dos bots e fechamento dos lotes vencidos.
create or replace function public.on_market_tick(p_now timestamptz,p_new_day boolean) returns void
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;r record;i int;pid text;dur int;k int;v_bid bigint;v_day timestamptz;mins int[];
begin
 select * into s from public.on_seasons where status='live';
 if s.id is null then return;end if;
 -- 24 lotes por dia, das 08:00 às 23:30 (horário da temporada), com duração de 5 a 10 minutos
 if p_new_day then
  select lot_minutes into mins from public.on_config;
  v_day:=((p_now at time zone s.tz)::date+time '08:00') at time zone s.tz;
  for i in 0..23 loop
   pid:=public.on_gen_free(s.seed||':lot:'||(p_now at time zone s.tz)::date||':'||i);
   dur:=mins[1]+floor(random()*(mins[2]-mins[1]+1))::int;
   insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end)
   select s.id,pid,greatest(500,round(public.on_value(p.ovr,p.age,p.pot)*.4))::bigint,
    v_day+i*interval '40 minutes',v_day+i*interval '40 minutes'+dur*interval '1 minute',
    v_day+i*interval '40 minutes'+dur*interval '1 minute'+(select lot_extend_max from public.on_config)
   from public.on_players p where p.id=pid;
  end loop;
 end if;
 -- bots: lances modestos (até ~80% do valor) nos lotes que estão no fim
 for r in select l.*,public.on_value(p.ovr,p.age,p.pot) v from public.on_lots l join public.on_players p on p.id=l.player_id
  where l.season_id=s.id and l.status='open' and l.opens_at<=p_now and l.ends_at>p_now and l.ends_at<=p_now+interval '2 minutes'
   and random()<.35 loop
  v_bid:=case when r.best_bid is null then r.start_price else r.best_bid+greatest(500,ceil(r.best_bid*.05))::bigint end;
  continue when v_bid>r.v*.8;
  select c.id into k from public.on_clubs c where c.season_id=s.id and c.user_id is null and c.id is distinct from r.best_club
   and c.id is distinct from r.seller and c.debt=0 and c.cash-c.reserved>=v_bid and (select count(*) from public.on_players x where x.club_id=c.id)<26
   order by random() limit 1;
  continue when k is null;
  begin perform public.on_bid_as(k,r.id,v_bid,p_now);exception when others then null;end;
 end loop;
 -- fechamento
 for r in select l.id from public.on_lots l where l.season_id=s.id and l.status='open' and l.ends_at<=p_now order by l.ends_at limit 10 loop
  perform public.on_lot_settle(r.id,p_now);
 end loop;
end $$;

update public.on_config set tick_hooks=array(select distinct x from unnest(tick_hooks||'on_market_tick'::text) x);

-- ─────────────────────────────────────────────────────────────────────────────
-- Funções chamadas pelo app
-- ─────────────────────────────────────────────────────────────────────────────

-- Mercado: lotes abertos (e os próximos), meus lotes, últimos negócios e o caixa.
create or replace function public.on_market() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();
begin
 return jsonb_build_object('server_now',now(),'my_club',c.id,
  'club',jsonb_build_object('cash',c.cash,'reserved',c.reserved,'debt',c.debt,'roster',(select count(*) from public.on_players where club_id=c.id)),
  'lots',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.status<>'open',l.ends_at) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='open' and x.opens_at<=now()+interval '2 hours') l),'[]'::jsonb),
  'recent',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.settled_at desc) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='sold' order by x.settled_at desc limit 8) l),'[]'::jsonb));
end $$;

create or replace function public.on_lot_json(l public.on_lots,p_me int) returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('id',l.id,'status',l.status,'opens_at',l.opens_at,'ends_at',l.ends_at,'start_price',l.start_price,
  'best_bid',l.best_bid,'bids',l.bids,'min_bid',public.on_min_bid(l),'mine',l.seller=p_me,'leading',l.best_club=p_me,
  'player',jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'sec',p.sec,'age',p.age,'ovr',p.ovr,'pot',p.pot,'star',p.star,'cond',p.cond,
   'wage',p.wage,'value',public.on_value(p.ovr,p.age,p.pot),'number',p.number),
  'seller',case when s.id is null then null else jsonb_build_object('id',s.id,'name',s.name,'short',s.short,'colors',s.colors) end,
  'best_club',case when b.id is null then null else jsonb_build_object('id',b.id,'name',b.name,'short',b.short,'colors',b.colors) end)
 from public.on_players p left join public.on_clubs s on s.id=l.seller left join public.on_clubs b on b.id=l.best_club
 where p.id=l.player_id
$$;

create or replace function public.on_bid(p_lot bigint,p_amount bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();
begin
 if not exists(select 1 from public.on_lots where id=p_lot and season_id=c.season_id) then raise exception 'Leilão não encontrado';end if;
 perform public.on_bid_as(c.id,p_lot,p_amount);
 return public.on_market();
end $$;

-- Coloca um jogador do elenco à venda. Elenco com menos de 16 não vende; quem está jogando agora não entra.
create or replace function public.on_lot_create(p_player text,p_price bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);p public.on_players;v_value bigint;v_min int;
begin
 select * into p from public.on_players where id=p_player and club_id=c.id for update;
 if p.id is null then raise exception 'Jogador fora do seu elenco';end if;
 if (select count(*) from public.on_players where club_id=c.id)-(select count(*) from public.on_lots where seller=c.id and status='open')<=16 then
  raise exception 'Elenco com 16 jogadores: não dá para vender mais';
 end if;
 if public.on_in_live(p.id) then raise exception 'Ele está jogando agora. Coloque à venda depois do apito final.';end if;
 if exists(select 1 from public.on_lots where player_id=p.id and status='open') then raise exception 'Esse jogador já está à venda';end if;
 v_value:=public.on_value(p.ovr,p.age,p.pot);
 if p_price is null or p_price<greatest(500,v_value*.3) or p_price>v_value*3 then
  raise exception 'Preço inicial entre $ % e $ %',greatest(500,round(v_value*.3)),round(v_value*3);
 end if;
 select user_lot_minutes into v_min from public.on_config;
 insert into public.on_lots(season_id,player_id,seller,start_price,opens_at,ends_at,hard_end)
 values(c.season_id,p.id,c.id,p_price,now(),now()+v_min*interval '1 minute',now()+v_min*interval '1 minute'+(select lot_extend_max from public.on_config));
 return public.on_market();
end $$;

-- Retira um jogador da venda (só sem lances).
create or replace function public.on_lot_cancel(p_lot bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();l public.on_lots;
begin
 select * into l from public.on_lots where id=p_lot and seller=c.id for update;
 if l.id is null or l.status<>'open' then raise exception 'Leilão não encontrado';end if;
 if l.best_club is not null then raise exception 'Já tem lance: não dá para retirar';end if;
 update public.on_lots set status='cancelled',settled_at=now() where id=l.id;
 return public.on_market();
end $$;

-- Extrato e avisos do clube.
create or replace function public.on_finance() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();
begin
 return jsonb_build_object('cash',c.cash,'reserved',c.reserved,'debt',c.debt,
  'wages',(select coalesce(sum(wage),0) from public.on_players where club_id=c.id),
  'ledger',coalesce((select jsonb_agg(jsonb_build_object('kind',x.kind,'amount',x.amount,'note',x.note,'at',x.at) order by x.id desc)
   from(select * from public.on_ledger where club_id=c.id order by id desc limit 30) x),'[]'::jsonb),
  'news',coalesce((select jsonb_agg(jsonb_build_object('kind',x.kind,'text',x.text,'at',x.at) order by x.id desc)
   from(select * from public.on_news where club_id=c.id order by id desc limit 20) x),'[]'::jsonb));
end $$;

revoke all on function public.on_money(int,bigint,text,text,boolean),public.on_in_live(text),public.on_lineup_repair(int),
 public.on_min_bid(public.on_lots),public.on_bid_as(int,bigint,bigint,timestamptz),public.on_lot_settle(bigint,timestamptz),
 public.on_gen_free(text),public.on_market_tick(timestamptz,boolean),public.on_lot_json(public.on_lots,int)
 from public,anon,authenticated;
revoke all on function public.on_market(),public.on_bid(bigint,bigint),public.on_lot_create(text,bigint),public.on_lot_cancel(bigint),public.on_finance() from public,anon;
grant execute on function public.on_market(),public.on_bid(bigint,bigint),public.on_lot_create(text,bigint),public.on_lot_cancel(bigint),public.on_finance() to authenticated;

-- ===== supabase/online/04_club.sql =====
-- MODO ONLINE — Fase 4: treino, estrutura, contratos e finanças.
--
-- Decisões (configuráveis em on_config):
--  • Treino gasta condição física: 6 pontos por sessão (train_cond). A tela avisa no dia de jogo.
--  • Caixa nunca negativo: salário que não cabe no dinheiro livre vira dívida; dívida bloqueia lances e as
--    próximas receitas pagam a dívida primeiro (on_money, Fase 3).
--  • Moedas da conta: 1 moeda = $ 1.000 (coin_rate), até 300 moedas por temporada (coin_cap).

alter table public.on_config add column if not exists train_cond smallint not null default 6;
alter table public.on_config add column if not exists train_sessions smallint not null default 3;
alter table public.on_config add column if not exists coin_rate int not null default 1000;
alter table public.on_config add column if not exists coin_cap int not null default 300;
alter table public.on_clubs add column if not exists lv jsonb not null default '{"stadium":0,"training":0,"medical":0,"youth":0}'::jsonb;
alter table public.on_clubs add column if not exists build_kind text;
alter table public.on_clubs add column if not exists build_until timestamptz;

-- Sessões de treino: o resultado do mini-game (0 a 1) vira experiência para o grupo do jogo.
create table if not exists public.on_train(
 id bigint generated by default as identity primary key,
 club_id int not null references public.on_clubs(id) on delete cascade,
 game text not null check (game in('reaction','passing','aim','timing')),
 players text[] not null,
 seed text not null,
 started_at timestamptz not null default now(),
 finished_at timestamptz,
 score numeric(4,3)
);
create index if not exists on_train_club on public.on_train(club_id,id desc);
alter table public.on_train enable row level security;
revoke all on public.on_train from anon,authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Regras
-- ─────────────────────────────────────────────────────────────────────────────

-- Grupo de atributos de cada mini-game (índice de on_players.g): 1 defesa, 2 passe, 3 ataque, 4 físico.
create or replace function public.on_train_group(p_game text) returns int
language sql immutable as $$ select case p_game when 'reaction' then 1 when 'passing' then 2 when 'aim' then 3 else 4 end $$;

-- Nota a partir do nível e dos ganhos de treino: +0,5 por ponto de grupo, nunca acima do potencial.
create or replace function public.on_ovr(p_level numeric,p_pot numeric,p_g smallint[]) returns numeric
language sql immutable as $$ select least(greatest(p_pot,p_level),p_level+.5*(select coalesce(sum(x),0) from unnest(p_g) x))::numeric(4,1) $$;

-- Experiência ganha numa sessão: cai perto do potencial e com a idade; o centro de treinamento ajuda.
create or replace function public.on_train_gain(p_score numeric,p_age int,p_ovr numeric,p_pot numeric,p_lv int) returns int
language sql immutable as $$
 select round(greatest(0,least(1,p_score))*45
  *case when p_age<21 then 1.3 when p_age<24 then 1.15 when p_age<28 then 1 when p_age<31 then .7 else .45 end
  *greatest(0,least(1,(p_pot-p_ovr)/5.0))
  *(1+.1*coalesce(p_lv,0)))::int
$$;

-- Estrutura: custo e tempo do próximo nível (0 a 5).
create or replace function public.on_build_cost(p_level int) returns bigint
language sql immutable as $$ select (25000*power(p_level+1,1.5))::bigint $$;
create or replace function public.on_build_time(p_level int,p_sandbox boolean) returns interval
language sql immutable as $$ select case when p_sandbox then (p_level+1)*interval '5 minutes' else (p_level+1)*interval '12 hours' end $$;

-- Aplica a obra concluída (chamado nas leituras e no cron).
create or replace function public.on_build_done(p_club int,p_now timestamptz default now()) returns void
language sql security definer set search_path=public as $$
 with d as(update public.on_clubs set lv=jsonb_set(lv,array[build_kind],to_jsonb(coalesce((lv->>build_kind)::int,0)+1)),build_kind=null,build_until=null
  where id=p_club and build_until<=p_now returning id,lv)
 insert into public.on_news(club_id,kind,text) select d.id,'build','Obra concluída: a estrutura do clube subiu de nível.' from d
$$;

-- Bilheteria do jogo em casa (gancho de fim de partida): $ 8.000 + $ 3.000 por nível do estádio.
create or replace function public.on_gate_income(p_fixture bigint) returns void
language plpgsql security definer set search_path=public as $$
declare f public.on_fixtures;v bigint;
begin
 select * into f from public.on_fixtures where id=p_fixture;
 if f.stage='final' then return;end if; -- final em campo neutro
 select (8000+3000*coalesce((lv->>'stadium')::int,0))*case when f.comp='C' then 1.5 else 1 end into v from public.on_clubs where id=f.home for update;
 perform public.on_money(f.home,v,'gate','Bilheteria');
end $$;

-- Gancho do cron: salários na virada do dia, obras prontas, base (revelações), recuperação extra do departamento médico.
create or replace function public.on_club_tick(p_now timestamptz,p_new_day boolean) returns void
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;r record;v bigint;pid text;
begin
 select * into s from public.on_seasons where status='live';
 if s.id is null then return;end if;
 for r in select id from public.on_clubs where season_id=s.id and build_until<=p_now loop perform public.on_build_done(r.id,p_now);end loop;
 if not p_new_day then return;end if;
 for r in select k.id,k.lv,(select coalesce(sum(wage),0) from public.on_players p where p.club_id=k.id) w from public.on_clubs k where k.season_id=s.id order by k.id for update of k loop
  if r.w>0 and public.on_money(r.id,-r.w,'wage','Salários do dia',true)>0 then
   insert into public.on_news(club_id,kind,text) values(r.id,'debt','O caixa não cobriu os salários: a diferença virou dívida. Com dívida não dá para dar lances.');
  end if;
  -- departamento médico: +5 de condição por nível (além da recuperação diária)
  if (r.lv->>'medical')::int>0 then
   update public.on_players set cond=least(100,cond+5*(r.lv->>'medical')::int) where club_id=r.id and cond<100;
  end if;
  -- base: chance de revelar um jovem (4% por nível ao dia) se houver vaga no elenco
  if random()<.04*coalesce((r.lv->>'youth')::int,0) and (select count(*) from public.on_players where club_id=r.id)<28 then
   insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end,number)
   select r.id,public.cw_regen_name('BRA',s.seed||':youth:'||r.id||':'||p_now::date),
    (array['ZAG','LD','LE','VOL','MC','MEI','PD','PE','ATA','GOL'])[1+floor(random()*10)::int],17,l,least(94,l+14+3*(r.lv->>'youth')::int),l,public.on_wage(l),s.id+3,
    (select min(n) from generate_series(1,99) n where n not in(select coalesce(x.number,0) from public.on_players x where x.club_id=r.id))
   from(select 56+floor(random()*6)::int l) z returning name into pid;
   insert into public.on_news(club_id,kind,text) values(r.id,'youth',format('A base revelou %s, 17 anos. Ele já está no elenco.',pid));
  end if;
 end loop;
end $$;

update public.on_config set tick_hooks=array(select distinct x from unnest(tick_hooks||'on_club_tick'::text) x),
 finish_hooks=array(select distinct x from unnest(finish_hooks||'on_gate_income'::text) x);

-- ─────────────────────────────────────────────────────────────────────────────
-- Funções chamadas pelo app
-- ─────────────────────────────────────────────────────────────────────────────

-- Clube: estrutura, obra em andamento, treino do dia, moedas e próximo jogo (para o aviso do treino).
create or replace function public.on_club() returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();cfg public.on_config;v_today date;v_sb boolean;v_coins int;
begin
 perform public.on_build_done(c.id);
 select * into c from public.on_clubs where id=c.id;
 select * into cfg from public.on_config;
 select s.kind='sandbox',(now() at time zone s.tz)::date into v_sb,v_today from public.on_seasons s where s.id=c.season_id;
 select x.coins into v_coins from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1;
 return jsonb_build_object('server_now',now(),'cash',c.cash,'reserved',c.reserved,'debt',c.debt,
  'levels',c.lv,'build',case when c.build_kind is null then null else jsonb_build_object('kind',c.build_kind,'until',c.build_until) end,
  'costs',(select jsonb_object_agg(k,jsonb_build_object('cost',public.on_build_cost((c.lv->>k)::int),'time',extract(epoch from public.on_build_time((c.lv->>k)::int,v_sb))))
   from unnest(array['stadium','training','medical','youth']) k),
  'train',jsonb_build_object('used',case when c.train_day=v_today then c.train_used else 0 end,'max',cfg.train_sessions,'cond_cost',cfg.train_cond),
  'coins',jsonb_build_object('wallet',v_coins,'converted',c.coins_conv,'cap',cfg.coin_cap,'rate',cfg.coin_rate),
  'match_today',exists(select 1 from public.on_fixtures f where f.season_id=c.season_id and (f.home=c.id or f.away=c.id) and f.status<>'done'
   and (f.kickoff at time zone 'America/Sao_Paulo')::date=v_today),
  'wages',(select coalesce(sum(wage),0) from public.on_players where club_id=c.id));
end $$;

-- Começa uma obra (uma por vez). O custo sai do caixa livre na hora.
create or replace function public.on_build(p_kind text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);v_lv int;v_sb boolean;
begin
 if p_kind not in('stadium','training','medical','youth') then raise exception 'Estrutura inválida';end if;
 perform public.on_build_done(c.id);
 select * into c from public.on_clubs where id=c.id;
 if c.build_kind is not null then raise exception 'Já existe uma obra em andamento';end if;
 v_lv:=coalesce((c.lv->>p_kind)::int,0);
 if v_lv>=5 then raise exception 'Nível máximo';end if;
 select kind='sandbox' into v_sb from public.on_seasons where id=c.season_id;
 perform public.on_money(c.id,-public.on_build_cost(v_lv),'build',p_kind);
 update public.on_clubs set build_kind=p_kind,build_until=now()+public.on_build_time(v_lv,v_sb) where id=c.id;
 return public.on_club();
end $$;

-- Começa uma sessão de treino: até 6 jogadores, 3 sessões por dia. A condição cai na hora.
create or replace function public.on_train_start(p_game text,p_players text[]) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;v_today date;v_id bigint;v_seed text:=md5(gen_random_uuid()::text);
begin
 select * into cfg from public.on_config;
 if p_game not in('reaction','passing','aim','timing') then raise exception 'Treino inválido';end if;
 if coalesce(cardinality(p_players),0) not between 1 and 6 or cardinality(p_players)<>(select count(distinct x) from unnest(p_players) x) then
  raise exception 'Escolha de 1 a 6 jogadores';
 end if;
 select (now() at time zone tz)::date into v_today from public.on_seasons where id=c.season_id;
 if c.train_day is distinct from v_today then c.train_used:=0;end if;
 if c.train_used>=cfg.train_sessions then raise exception 'Limite de % treinos por dia atingido',cfg.train_sessions;end if;
 if exists(select 1 from unnest(p_players) x where not exists(select 1 from public.on_players p where p.id=x and p.club_id=c.id
   and (p.inj_until is null or p.inj_until<=v_today) and p.cond>=30)) then
  raise exception 'Só treinam jogadores do elenco, sem lesão e com pelo menos 30%% de condição';
 end if;
 if exists(select 1 from unnest(p_players) x where public.on_in_live(x)) then raise exception 'Quem está jogando agora não treina';end if;
 update public.on_clubs set train_day=v_today,train_used=c.train_used+1 where id=c.id;
 update public.on_players set cond=greatest(0,cond-cfg.train_cond) where id=any(p_players);
 insert into public.on_train(club_id,game,players,seed) values(c.id,p_game,p_players,v_seed) returning id into v_id;
 return jsonb_build_object('session',v_id,'game',p_game,'seed',v_seed,'started_at',now());
end $$;

-- Termina a sessão com o resultado do mini-game (limitado entre 0 e 1). 100 pontos sobem o grupo e a nota.
create or replace function public.on_train_finish(p_session bigint,p_score numeric) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);t public.on_train;v numeric:=greatest(0,least(1,coalesce(p_score,0)));gi int;out jsonb;
begin
 select * into t from public.on_train where id=p_session and club_id=c.id for update;
 if t.id is null then raise exception 'Treino não encontrado';end if;
 if t.finished_at is not null then raise exception 'Esse treino já terminou';end if;
 if now()-t.started_at<interval '8 seconds' then raise exception 'Treino curto demais';end if;
 if now()-t.started_at>interval '10 minutes' then v:=0;end if; -- sessão abandonada não rende
 gi:=public.on_train_group(t.game);
 update public.on_train set finished_at=now(),score=v where id=t.id;
 with g as(
  select p.id,public.on_train_gain(v,p.age,p.ovr,p.pot,(c.lv->>'training')::int) gain from public.on_players p where p.id=any(t.players) and p.club_id=c.id),
 u as(update public.on_players p set
   g[gi]=p.g[gi]+(p.xp[gi]+g.gain)/100,
   xp[gi]=(p.xp[gi]+g.gain)%100,
   ovr=public.on_ovr(p.level,p.pot,(select array_agg(case when i=gi then p.g[i]+(p.xp[gi]+g.gain)/100 else p.g[i] end order by i) from generate_series(1,4) i)::smallint[])
  from g where p.id=g.id returning p.id,p.name,p.ovr,g.gain,(p.xp[gi]) xp)
 select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'gain',u.gain,'ovr',u.ovr,'xp',u.xp)) into out from u;
 return jsonb_build_object('score',v,'group',gi,'players',coalesce(out,'[]'::jsonb));
end $$;

-- Renovação: luva (8 salários novos por temporada) e salário novo pela nota atual. Até 3 temporadas à frente.
create or replace function public.on_renew(p_player text,p_years int) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);p public.on_players;v_wage int;v_fee bigint;
begin
 select * into p from public.on_players where id=p_player and club_id=c.id for update;
 if p.id is null then raise exception 'Jogador fora do seu elenco';end if;
 if p_years not between 1 and 3 then raise exception 'Renovação de 1 a 3 temporadas';end if;
 if coalesce(p.contract_end,0)>=c.season_id+3 then raise exception 'Contrato já vai até o limite';end if;
 v_wage:=ceil(public.on_wage(p.ovr)*case when p.age<24 then 1.1 when p.age>=31 then .9 else 1 end);
 v_fee:=v_wage*8*p_years;
 perform public.on_money(c.id,-v_fee,'renew',p.name);
 update public.on_players set wage=v_wage,contract_end=least(c.season_id+3,greatest(coalesce(contract_end,c.season_id),c.season_id)+p_years) where id=p.id;
 return public.on_squad();
end $$;

-- Converte moedas da conta (carteira do modo Temporadas) em caixa do clube, com teto por temporada.
-- Sem prefixo on_ de propósito: o app trata como escrita e atualiza o saldo de moedas nas outras telas.
create or replace function public.online_coins_convert(p_coins int) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;k public.careers;
begin
 select * into cfg from public.on_config;
 if p_coins is null or p_coins<1 then raise exception 'Quantidade inválida';end if;
 if c.coins_conv+p_coins>cfg.coin_cap then raise exception 'Teto da temporada: ainda dá para converter % moedas',cfg.coin_cap-c.coins_conv;end if;
 select x.* into k from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1 for update;
 if k.id is null or k.coins<p_coins then raise exception 'Moedas insuficientes';end if;
 update public.careers set coins=coins-p_coins where id=k.id;
 perform public.on_money(c.id,p_coins::bigint*cfg.coin_rate,'coins',format('%s moedas',p_coins));
 update public.on_clubs set coins_conv=coins_conv+p_coins where id=c.id;
 return public.on_club();
end $$;

revoke all on function public.on_train_group(text),public.on_ovr(numeric,numeric,smallint[]),public.on_train_gain(numeric,int,numeric,numeric,int),
 public.on_build_cost(int),public.on_build_time(int,boolean),public.on_build_done(int,timestamptz),public.on_gate_income(bigint),
 public.on_club_tick(timestamptz,boolean) from public,anon,authenticated;
revoke all on function public.on_club(),public.on_build(text),public.on_train_start(text,text[]),public.on_train_finish(bigint,numeric),
 public.on_renew(text,int),public.online_coins_convert(int) from public,anon;
grant execute on function public.on_club(),public.on_build(text),public.on_train_start(text,text[]),public.on_train_finish(bigint,numeric),
 public.on_renew(text,int),public.online_coins_convert(int) to authenticated;

-- ===== supabase/online/05_cup_season.sql =====
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

insert into supabase_migrations.schema_migrations(version,name) values
 ('20261110180000','online_phase2_match'),('20261110190000','online_phase3_market'),
 ('20261110200000','online_phase4_club'),('20261110210000','online_phase5_cup_season')
on conflict do nothing;
commit;
