-- Pacote de publicação do modo online, fase 9 (gerado de supabase/online/09_market_legends.sql e 10_legends_data.sql).
-- Rodar inteiro no SQL Editor ou pela API, como administrador. Tudo ou nada.
-- Depois: supabase/releases/online_reiniciar.sql.
begin;

-- MODO ONLINE — Fase 9: lendas, jogador especial do dia, energia de treino em estoque e preleção do intervalo.
--
--  • Catálogo do modo (on_pool): jogadores reais com nota-base, os reais que só têm nível (attr_level) e as
--    cartas lenda (on_legends, aposentados). Só leitura do catálogo do jogo.
--  • Tipos de carta: normal (até 80), especial (81 ou mais) e lenda.
--  • Mercado: três leilões comuns, sempre até 80 de nota. Um jogador especial por dia (a cada três dias, uma
--    lenda) aparece assim que o dia começa, travado, com o horário de abertura (special_hour, 19:00); na hora
--    o relógio de uma hora começa. Lance inicial acima de $ 400 mil para especiais e de $ 600 mil para lendas.
--  • Energia de treino: os treinos do dia são grátis; cada treino além deles gasta 1 de energia do estoque
--    (on_clubs.train_energy), comprada com moedas (uma) ou diamantes (pacotes, energy_packs).
--  • Melhor time: escolhe os 11 pela melhor dupla jogador-vaga, não pela ordem das vagas.
--  • Preleção do intervalo (on_match_talk): seis conversas; o efeito na forma do segundo tempo depende do
--    placar e de quem é o favorito. Pode ajudar ou atrapalhar.

create table if not exists public.on_legends(
 id text primary key check (id like 'lg-%'),
 name text not null,
 pos text not null references public.sim_positions(code),
 sec text[] not null default '{}',
 nat text not null,
 rating smallint not null check (rating between 80 and 99)
);
alter table public.on_legends enable row level security;
revoke all on public.on_legends from anon,authenticated;

alter table public.on_players add column if not exists legend boolean not null default false;
alter table public.on_clubs add column if not exists train_energy int not null default 0 check (train_energy>=0);
alter table public.on_config add column if not exists special_hour smallint not null default 19;
alter table public.on_config add column if not exists energy_packs jsonb not null default '{"d5":[5,15],"d20":[20,50],"d50":[50,100]}'::jsonb; -- pacote: [energia, diamantes]
update public.on_config set coin_cap=5000 where coin_cap=1000;
alter table public.on_config alter column coin_cap set default 5000;

-- ─────────────────────────────────────────────────────────────────────────────
-- Catálogo do modo
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view public.on_pool as
 select p.id,coalesce(nullif(p.short_name,''),p.full_name) name,p.position pos,coalesce(p.secondary_positions,'{}') sec,
  coalesce(p.nationality,'BRA') nat,coalesce(b.rating,p.attr_level)::numeric rating,
  coalesce(b.age0,p.age,25)::int age,coalesce(b.potential,p.attr_level+2)::int pot,false legend
 from public.sim_players p left join public.sim_player_base b on b.player_id=p.id
 where p.career_id is null and p.active and coalesce(b.rating,p.attr_level) is not null
 union all
 select l.id,l.name,l.pos,l.sec,l.nat,l.rating::numeric,30,l.rating::int,true from public.on_legends l;
revoke all on public.on_pool from anon,authenticated;

-- Jogador livre do catálogo (em nenhum clube, leilão ou reserva). p_legend escolhe entre lendas ou jogadores comuns.
drop function if exists public.on_real_pick(text,numeric,numeric,text);
create or replace function public.on_real_pick(p_pos text,p_lo numeric,p_hi numeric,p_seed text,p_legend boolean default false) returns text
language sql stable security definer set search_path=public as $$
 select p.id from public.on_pool p
 where p.legend=p_legend and (p_pos is null or p.pos=p_pos) and p.rating>=p_lo and p.rating<p_hi
  and not exists(select 1 from public.on_players o where o.src=p.id)
 order by public.sim_hash01(p_seed||':'||p.id) limit 1
$$;

create or replace function public.on_real_insert(p_src text,p_club int,p_number int,p_contract_end int,p_star boolean default false,
 p_hold int default null,p_hold_slot int default null) returns text
language sql security definer set search_path=public as $$
 insert into public.on_players(club_id,src,name,pos,sec,nat,age,level,pot,ovr,number,wage,contract_end,agg,disc,star,hold,hold_slot,legend)
 select p_club,p.id,p.name,p.pos,
  array(select x from unnest(p.sec) x where x in(select code from public.sim_positions) and x<>p.pos),
  p.nat,a.age,a.lvl,greatest(a.lvl,least(95,p.pot))::smallint,a.lvl,p_number,public.on_wage(a.lvl),p_contract_end,
  35+floor(public.sim_hash01(p.id||':agg')*40)::int,40+floor(public.sim_hash01(p.id||':disc')*45)::int,p_star or p.legend,p_hold,p_hold_slot,p.legend
 from public.on_pool p
 cross join lateral(select greatest(16,least(40,p.age))::smallint age,round(p.rating)::smallint lvl) a
 where p.id=p_src
 returning id
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Mercado
-- ─────────────────────────────────────────────────────────────────────────────

-- Lance inicial: comum 40% do valor; especial (81+) acima de $ 400 mil; lenda acima de $ 600 mil.
create or replace function public.on_start_price(p public.on_players) returns bigint
language sql immutable set search_path=public as $$
 select case when p.legend then 600000+greatest(0,p.level-85)*50000
  when p.level>=81 then 400000+(p.level-80)*40000
  else greatest(500,round(public.on_value(p.ovr,p.age,p.pot)*.4)) end::bigint
$$;

-- Leilões comuns: nunca acima de 80. Faixa 1: 74 a 80; 2: 68 a 74; 3: 62 a 68.
create or replace function public.on_gen_featured(p_seed text,p_tier int) returns text
language plpgsql security definer set search_path=public as $$
declare v_lo numeric:=(array[74,68,62])[p_tier];v_hi numeric:=(array[80.5,74,68])[p_tier];v_src text;v_id text;
 v_pos text:=(array['GOL','LD','ZAG','ZAG','LE','VOL','MC','MEI','PD','PE','ATA','ATA'])[1+floor(public.sim_hash01(p_seed||':p')*12)::int];
 v_end int:=(select max(id) from public.on_seasons)+1+floor(public.sim_hash01(p_seed||':ct')*2)::int;
begin
 v_src:=coalesce(public.on_real_pick(v_pos,v_lo,v_hi,p_seed),public.on_real_pick(null,v_lo,v_hi,p_seed));
 if v_src is not null then return public.on_real_insert(v_src,null,null,v_end);end if;
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end,agg,disc)
 select null,public.cw_regen_name('BRA',p_seed),v_pos,a.age,a.lvl,least(94,a.lvl+floor(public.sim_hash01(p_seed||':pot')*case when a.age<23 then 12 else 5 end)::int),
  a.lvl,public.on_wage(a.lvl),v_end,35+floor(public.sim_hash01(p_seed||':agg')*40)::int,40+floor(public.sim_hash01(p_seed||':disc')*45)::int
 from(select 18+floor(public.sim_hash01(p_seed||':age')*15)::int age,floor(v_lo+public.sim_hash01(p_seed||':lvl')*(v_hi-v_lo))::int lvl) a
 returning id into v_id;
 return v_id;
end $$;

-- Jogador especial do dia: lenda (p_legend) ou jogador de 81 para cima. Nulo se não houver nenhum livre.
create or replace function public.on_gen_special(p_seed text,p_legend boolean) returns text
language plpgsql security definer set search_path=public as $$
declare v_src text;v_id text;v_end int:=(select max(id) from public.on_seasons)+2;
begin
 v_src:=case when p_legend then public.on_real_pick(null,80,100,p_seed,true) end;
 if v_src is null then v_src:=public.on_real_pick(null,80.5,100,p_seed,false);end if;
 if v_src is null then v_src:=public.on_real_pick(null,80,100,p_seed,true);end if;
 if v_src is null then return null;end if;
 v_id:=public.on_real_insert(v_src,null,null,v_end,true);
 return v_id;
end $$;

-- Gancho do cron: fecha lotes vencidos, mantém os três leilões comuns, cria o especial do dia e move os bots.
create or replace function public.on_market_tick(p_now timestamptz,p_new_day boolean) returns void
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;cfg public.on_config;r record;t int;pid text;k int;v_bid bigint;v_end timestamptz;v_day date;v_hour int;v_open timestamptz;
begin
 select * into s from public.on_seasons where status='live';
 if s.id is null then return;end if;
 select * into cfg from public.on_config;
 v_day:=(p_now at time zone s.tz)::date;
 v_hour:=extract(hour from p_now at time zone s.tz);
 for r in select l.id from public.on_lots l where l.season_id=s.id and l.status='open' and l.ends_at<=p_now order by l.ends_at limit 10 loop
  perform public.on_lot_settle(r.id,p_now);
 end loop;
 -- comuns: um por faixa, das 08:00 às 22:59; cada um fica até a virada da hora
 if v_hour between 8 and 22 then
  for t in 1..cfg.featured_count loop
   continue when exists(select 1 from public.on_lots x where x.season_id=s.id and x.status='open' and x.featured=t);
   pid:=public.on_gen_featured(s.seed||':f:'||t||':'||floor(extract(epoch from p_now))::bigint,t);
   v_end:=case when cfg.featured_minutes=60 then date_trunc('hour',p_now+interval '15 minutes')+interval '1 hour'
    else p_now+cfg.featured_minutes*interval '1 minute' end;
   insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
   select s.id,pid,public.on_start_price(p),p_now,v_end,v_end+cfg.lot_extend_max,t from public.on_players p where p.id=pid;
  end loop;
 end if;
 -- especial do dia: aparece cedo e travado; abre às special_hour e fica uma hora (lenda a cada três dias)
 if v_hour<cfg.special_hour and not exists(select 1 from public.on_lots x where x.season_id=s.id and x.featured=9
   and (x.opens_at at time zone s.tz)::date=v_day) then
  pid:=public.on_gen_special(s.seed||':special:'||v_day,(v_day-s.starts_on)%3=2);
  if pid is not null then
   v_open:=(v_day+make_time(cfg.special_hour,0,0)) at time zone s.tz;
   insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
   select s.id,pid,public.on_start_price(p),v_open,v_open+interval '1 hour',v_open+interval '1 hour'+cfg.lot_extend_max,9
   from public.on_players p where p.id=pid;
  end if;
 end if;
 -- bots: entram na disputa só quando um técnico já deu lance, nos últimos 3 minutos, até 70% a 90% do valor
 for r in select l.*,public.on_value(p.ovr,p.age,p.pot) v from public.on_lots l join public.on_players p on p.id=l.player_id
  where l.season_id=s.id and l.status='open' and l.featured<>9 and l.opens_at<=p_now and l.ends_at>p_now and l.ends_at<=p_now+interval '3 minutes'
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

-- Mercado: os leilões abertos e o especial do dia (mesmo antes de abrir).
create or replace function public.on_market() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();cfg public.on_config;
begin
 select * into cfg from public.on_config;
 return jsonb_build_object('server_now',now(),'my_club',c.id,
  'club',jsonb_build_object('cash',c.cash,'reserved',c.reserved,'debt',c.debt,'roster',(select count(*) from public.on_players where club_id=c.id)),
  'coins',jsonb_build_object('wallet',coalesce(public.on_wallet(),0),'rate',cfg.coin_rate,'bid_rate',cfg.coin_bid_rate,'converted',c.coins_conv,'cap',cfg.coin_cap),
  'lots',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.featured<>9,l.featured=0,l.featured,l.ends_at) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='open' and (x.featured=9 or x.opens_at<=now())) l),'[]'::jsonb),
  'recent',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.settled_at desc) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='sold' order by x.settled_at desc limit 8) l),'[]'::jsonb));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Melhor time: a cada passo entra a dupla jogador-vaga de maior rendimento (nota × encaixe × condição),
-- começando por quem joga na própria posição: o melhor de cada posição fica com a vaga dela.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_auto_lineup(p_club int,p_formation text default null) returns void
language plpgsql security definer set search_path=public as $$
declare f public.sim_formations;used text[]:='{}';taken text[]:='{}';v_slots jsonb:='{}';r record;n int;
begin
 select fm.* into f from public.sim_formations fm
  where fm.id=coalesce(p_formation,(select l.formation from public.on_lineups l where l.club_id=p_club),'4-3-3');
 if f.id is null then raise exception 'Formação inválida';end if;
 n:=jsonb_array_length(f.slots);
 for i in 1..n loop
  select s.value->>'slot' slot,p.id into r
  from jsonb_array_elements(f.slots) s
  cross join public.on_players p
  left join public.sim_position_fit ft on ft.from_pos=p.pos and ft.to_pos=s.value->>'pos'
  where p.club_id=p_club and p.id<>all(used) and (s.value->>'slot')<>all(taken)
  order by (p.inj_until is not null and p.inj_until>current_date),
   -- goleiro só no gol e o gol só com goleiro, enquanto houver um
   ((p.pos='GOL')<>(s.value->>'pos'='GOL')),
   -- primeiro quem joga na própria posição (natural ou secundária); as vagas que sobram vão para o melhor encaixe
   (greatest(coalesce(ft.fit,.5),case when s.value->>'pos'=any(p.sec) then .97 else 0 end)>=.97) desc,
   p.ovr*greatest(coalesce(ft.fit,.5),case when s.value->>'pos'=any(p.sec) then .97 else 0 end)*(.7+.3*p.cond/100.0) desc,p.id
  limit 1;
  if r.id is null then raise exception 'Elenco insuficiente para escalar';end if;
  used:=used||r.id;taken:=taken||r.slot;
  v_slots:=v_slots||jsonb_build_object(r.slot,r.id);
 end loop;
 insert into public.on_lineups(club_id,formation,slots,bench,tactics)
 values(p_club,f.id,v_slots,array(select p.id from public.on_players p where p.club_id=p_club and p.id<>all(used)
   order by (p.inj_until is not null and p.inj_until>current_date),p.ovr desc,p.id limit 12),'{}')
 on conflict(club_id) do update set formation=excluded.formation,slots=excluded.slots,bench=excluded.bench,updated_at=now();
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Energia de treino em estoque
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_train_max(c public.on_clubs,p_today date) returns int
language sql stable set search_path=public as $$ select train_sessions::int from public.on_config $$;

create or replace function public.on_train_start(p_game text,p_players text[]) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;v_today date;v_id bigint;v_seed text:=md5(gen_random_uuid()::text);v_spend int:=0;
begin
 select * into cfg from public.on_config;
 if p_game not in('reaction','passing','aim','timing','tackle','dribble','penalty') then raise exception 'Treino inválido';end if;
 if coalesce(cardinality(p_players),0) not between 1 and 11 or cardinality(p_players)<>(select count(distinct x) from unnest(p_players) x) then
  raise exception 'Escolha de 1 a 11 jogadores';
 end if;
 if p_game='penalty' and cardinality(p_players)<>1 then raise exception 'O treino de pênaltis é individual';end if;
 select (now() at time zone tz)::date into v_today from public.on_seasons where id=c.season_id;
 if c.train_day is distinct from v_today then c.train_used:=0;end if;
 if c.train_used>=cfg.train_sessions then
  if c.train_energy<=0 then raise exception 'Sem energia de treino';end if;
  v_spend:=1;
 end if;
 if exists(select 1 from unnest(p_players) x where not exists(select 1 from public.on_players p where p.id=x and p.club_id=c.id
   and (p.inj_until is null or p.inj_until<=v_today) and p.cond>=30)) then
  raise exception 'Só treinam jogadores do elenco, sem lesão e com pelo menos 30%% de condição';
 end if;
 if exists(select 1 from unnest(p_players) x where public.on_in_live(x)) then raise exception 'Quem está jogando agora não treina';end if;
 update public.on_clubs set train_day=v_today,train_used=c.train_used+1,train_energy=train_energy-v_spend where id=c.id;
 update public.on_players set cond=greatest(0,cond-cfg.train_cond) where id=any(p_players);
 insert into public.on_train(club_id,game,players,seed) values(c.id,p_game,p_players,v_seed) returning id into v_id;
 return jsonb_build_object('session',v_id,'game',p_game,'seed',v_seed,'started_at',now());
end $$;

-- Compra energia de treino: 'coin' (1 de energia por train_energy_cost moedas) ou um pacote de diamantes de energy_packs.
drop function if exists public.online_train_energy_buy();
create or replace function public.online_train_energy_buy(p_pack text default 'coin') returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;k public.careers;v_energy int;v_price int;
begin
 select * into cfg from public.on_config;
 select x.* into k from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1 for update;
 if k.id is null then raise exception 'Conta sem carreira';end if;
 if p_pack='coin' then
  if k.coins<cfg.train_energy_cost then raise exception 'Moedas insuficientes';end if;
  update public.careers set coins=coins-cfg.train_energy_cost where id=k.id;
  v_energy:=1;
 else
  if not cfg.energy_packs ? p_pack then raise exception 'Pacote inválido';end if;
  v_energy:=(cfg.energy_packs->p_pack->>0)::int;v_price:=(cfg.energy_packs->p_pack->>1)::int;
  if k.diamonds<v_price then raise exception 'Diamantes insuficientes';end if;
  update public.careers set diamonds=diamonds-v_price where id=k.id;
 end if;
 update public.on_clubs set train_energy=train_energy+v_energy where id=c.id;
 return public.on_club();
end $$;

-- Clube: estrutura, treino do dia, energia de treino e carteira.
create or replace function public.on_club() returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();cfg public.on_config;v_today date;v_sb boolean;k public.careers;v_used int;
begin
 perform public.on_build_done(c.id);
 select * into c from public.on_clubs where id=c.id;
 select * into cfg from public.on_config;
 select s.kind='sandbox',(now() at time zone s.tz)::date into v_sb,v_today from public.on_seasons s where s.id=c.season_id;
 select x.* into k from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1;
 v_used:=case when c.train_day=v_today then c.train_used else 0 end;
 return jsonb_build_object('server_now',now(),'cash',c.cash,'reserved',c.reserved,'debt',c.debt,
  'levels',c.lv,'build',case when c.build_kind is null then null else jsonb_build_object('kind',c.build_kind,'until',c.build_until) end,
  'costs',(select jsonb_object_agg(x,jsonb_build_object('cost',public.on_build_cost((c.lv->>x)::int),'time',extract(epoch from public.on_build_time((c.lv->>x)::int,v_sb))))
   from unnest(array['stadium','training','medical','youth']) x),
  'train',jsonb_build_object('used',v_used,'max',cfg.train_sessions,'free_left',greatest(0,cfg.train_sessions-v_used),'energy',c.train_energy,
   'cond_cost',cfg.train_cond,'coin_cost',cfg.train_energy_cost,'packs',cfg.energy_packs),
  'coins',jsonb_build_object('wallet',k.coins,'diamonds',k.diamonds,'converted',c.coins_conv,'cap',cfg.coin_cap,'rate',cfg.coin_rate),
  'match_today',exists(select 1 from public.on_fixtures f where f.season_id=c.season_id and (f.home=c.id or f.away=c.id) and f.status<>'done'
   and (f.kickoff at time zone 'America/Sao_Paulo')::date=v_today),
  'wages',(select coalesce(sum(wage),0) from public.on_players where club_id=c.id));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Preleção do intervalo
-- p_talk: praise (elogiar), focus (não relaxar), demand (cobrar mais), encourage (incentivar), calm (tranquilizar),
-- angry (dar bronca). d = saldo no intervalo; adv = diferença de força para o adversário.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_talk_effect(p_talk text,d int,adv numeric) returns numeric
language sql immutable as $$
 select case p_talk
  when 'praise' then case when d>=2 then .01 when d=1 then .025 when d=0 and adv<-2 then .025 when d=0 then -.01 else -.035 end
  when 'focus' then case when d>=1 then .03 when d=0 then .01 else -.015 end
  when 'demand' then case when d>=2 then -.03 when d=1 then -.01 when d=0 and adv>2 then .035 when d=0 then .015 when d=-1 then .03 when d=-2 then .01 else -.03 end
  when 'encourage' then case when d>=1 then 0 when d=0 then .02 when d>=-2 then .035 else .015 end
  when 'calm' then case when d<=-3 then .03 when d<0 and adv<-2 then .03 when d<0 then .005 when d=0 and adv>2 then -.02 when d=0 then .01 else -.01 end
  when 'angry' then case when d<=-2 and adv>=-2 then .05 when d<=-2 then .01 when d=-1 and adv>2 then .04 when d=-1 then .015 when d=0 and adv>2 then .02 when d=0 then -.02 else -.045 end
 end
$$;

create or replace function public.on_match_talk(p_fixture bigint,p_talk text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();f public.on_fixtures;m public.on_matches;sd char;i int;d int;adv numeric;e numeric;v_react text;
begin
 if p_talk not in('praise','focus','demand','encourage','calm','angry') then raise exception 'Preleção inválida';end if;
 select * into f from public.on_fixtures where id=p_fixture and season_id=c.season_id;
 sd:=public.on_side_of(f,c.id);
 if sd is null then raise exception 'Você não joga esta partida';end if;
 select * into m from public.on_matches where fixture_id=p_fixture for update;
 if m.fixture_id is null or m.status<>'live' or not coalesce((m.state->>'ht')::boolean,false) or m.minute>55 then
  raise exception 'A preleção acontece no intervalo';
 end if;
 if m.state->'ht_talk'->sd is not null then raise exception 'Você já falou com o time';end if;
 i:=case when sd='h' then 0 else 1 end;
 d:=(m.state->'score'->>i)::int-(m.state->'score'->>(1-i))::int;
 adv:=coalesce((m.state->'strength'->>i)::numeric-(m.state->'strength'->>(1-i))::numeric,0);
 e:=public.on_talk_effect(p_talk,d,adv)+(random()-.5)*.016;
 v_react:=case when e>=.03 then 'fired' when e>=.01 then 'good' when e>-.01 then 'flat' else 'upset' end;
 update public.on_matches set state=jsonb_set(state,array['form',i::text],to_jsonb(round((state->'form'->>i)::numeric*(1+e),3)))
  ||jsonb_build_object('ht_talk',coalesce(state->'ht_talk','{}'::jsonb)||jsonb_build_object(sd,jsonb_build_object('talk',p_talk,'react',v_react,'effect',round(e*100,1))))
 where fixture_id=p_fixture;
 perform public.on_event(p_fixture,m.minute,sd,'tactic',null,null,'Preleção no intervalo: '||case v_react
  when 'fired' then 'o time voltou inflamado' when 'good' then 'o time reagiu bem' when 'flat' then 'pouco efeito' else 'o time não gostou' end);
 return public.on_match_payload(p_fixture,0,sd);
end $$;

-- Relatório do adversário. p_mark falso (vestiário) só lê, sem contar como tarefa de preparação.
drop function if exists public.on_scout();
create or replace function public.on_scout(p_mark boolean default true) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);f public.on_fixtures;o public.on_clubs;v_sec jsonb;
begin
 f:=public.on_next_fixture(c.id);
 if f.id is null then raise exception 'Sem jogo pela frente';end if;
 select * into o from public.on_clubs where id=case when f.home=c.id then f.away else f.home end;
 if coalesce(p_mark,true) then perform public.on_prep_mark(c.id,'scout');end if;
 select * into c from public.on_clubs where id=c.id;
 select jsonb_object_agg(x.who,x.lines) into v_sec from(
  select k.who,jsonb_object_agg(z.line,z.avg) lines from(values('me',c.id),('opp',o.id)) k(who,club)
  cross join lateral(
   select sp.line,round(avg(p.ovr),1) avg from public.on_players p join public.sim_positions sp on sp.code=p.pos
   where p.club_id=k.club and p.id in(
    select e.value from public.on_lineups l,jsonb_each_text(l.slots) e where l.club_id=k.club
    union all
    select q.id from(select p2.id from public.on_players p2 where p2.club_id=k.club and not exists(select 1 from public.on_lineups l where l.club_id=k.club)
     order by p2.ovr desc limit 11) q)
   group by sp.line) z
  group by k.who) x;
 return jsonb_build_object('fixture',f.id,'kickoff',f.kickoff,'at_home',f.home=c.id,'comp',f.comp,'round',f.round,
  'me',jsonb_build_object('position',(select r.pos from public.on_rank(c.season_id) r where r.club_id=c.id),
   'formation',(select l.formation from public.on_lineups l where l.club_id=c.id),
   'stars',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'nat',p.nat,'ovr',p.ovr,'age',p.age,'star',p.star,'legend',p.legend,
      'card',public.on_card(p.id,p.pos,p.level,p.g)) order by p.ovr desc)
    from(select * from public.on_players q where q.club_id=c.id order by q.ovr desc,q.id limit 3) p),'[]'::jsonb)),
  'opp',jsonb_build_object('id',o.id,'name',o.name,'short',o.short,'colors',o.colors,'bot',o.user_id is null,
   'position',(select r.pos from public.on_rank(c.season_id) r where r.club_id=o.id),
   'formation',(select l.formation from public.on_lineups l where l.club_id=o.id),
   'style',coalesce((select l.tactics->>'style' from public.on_lineups l where l.club_id=o.id),'neutral'),
   'form',coalesce((select jsonb_agg(x.r order by x.kickoff) from(
     select g.kickoff,case when g.hg=g.ag then 'D' when (g.hg>g.ag)=(g.home=o.id) then 'W' else 'L' end r
     from public.on_fixtures g where g.season_id=c.season_id and g.status='done' and o.id in(g.home,g.away) order by g.kickoff desc limit 5) x),'[]'::jsonb),
   'goals',(select jsonb_build_object('gf',t.gf,'ga',t.ga,'p',t.p) from public.on_table t where t.season_id=c.season_id and t.club_id=o.id),
   'stars',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'nat',p.nat,'ovr',p.ovr,'age',p.age,'star',p.star,'legend',p.legend,
      'card',public.on_card(p.id,p.pos,p.level,p.g)) order by p.ovr desc)
    from(select * from public.on_players q where q.club_id=o.id order by q.ovr desc,q.id limit 3) p),'[]'::jsonb)),
  'sectors',v_sec,'prep',public.on_prep_json(c,f));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Campos novos nas leituras das fases anteriores (on_patch, Fase 7)
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
 perform public.on_patch('public.on_squad()','''nat'',p.nat,''sell''','''nat'',p.nat,''legend'',p.legend,''sell''');
 perform public.on_patch('public.on_lot_json(public.on_lots,int)','''nat'',p.nat,''card''','''nat'',p.nat,''legend'',p.legend,''card''');
 perform public.on_patch('public.on_status()','''max'',public.on_train_max(c,v_today))','''max'',public.on_train_max(c,v_today),''energy'',c.train_energy)');
 perform public.on_patch('public.on_match_payload(bigint,int,char)','''prep'',m.state->''prep'')','''prep'',m.state->''prep'',''ht_talk'',m.state->''ht_talk'')');
end $$;

revoke all on function public.on_real_pick(text,numeric,numeric,text,boolean),public.on_real_insert(text,int,int,int,boolean,int,int),
 public.on_start_price(public.on_players),public.on_gen_featured(text,int),public.on_gen_special(text,boolean),public.on_market_tick(timestamptz,boolean),
 public.on_auto_lineup(int,text),public.on_train_max(public.on_clubs,date),public.on_talk_effect(text,int,numeric)
 from public,anon,authenticated;
revoke all on function public.on_market(),public.on_train_start(text,text[]),public.online_train_energy_buy(text),public.on_club(),
 public.on_match_talk(bigint,text),public.on_scout(boolean) from public,anon;
grant execute on function public.on_market(),public.on_train_start(text,text[]),public.online_train_energy_buy(text),public.on_club(),
 public.on_match_talk(bigint,text),public.on_scout(boolean) to authenticated;

-- MODO ONLINE — Fase 9 (dados): cartas lenda. Jogadores aposentados, lista escrita à mão; a nota é a do auge.
-- Para acrescentar lendas, inclua linhas aqui (id 'lg-…' único) e copie para a migration.
insert into public.on_legends(id,name,pos,sec,nat,rating) values
('lg-pele','Pelé','ATA','{MEI}','BRA',97),
('lg-diego-maradona','Diego Maradona','MEI','{ATA}','ARG',97),
('lg-johan-cruyff','Johan Cruyff','ATA','{MEI}','NED',95),
('lg-franz-beckenbauer','Franz Beckenbauer','ZAG','{VOL}','GER',95),
('lg-zinedine-zidane','Zinédine Zidane','MEI','{MC}','FRA',95),
('lg-ronaldo-nazario','Ronaldo Nazário','ATA','{}','BRA',96),
('lg-ronaldinho-gaucho','Ronaldinho Gaúcho','MEI','{PE}','BRA',94),
('lg-alfredo-di-stefano','Alfredo Di Stéfano','ATA','{MEI}','ARG',95),
('lg-ferenc-puskas','Ferenc Puskás','ATA','{}','HUN',94),
('lg-michel-platini','Michel Platini','MEI','{}','FRA',94),
('lg-garrincha','Garrincha','PD','{}','BRA',94),
('lg-zico','Zico','MEI','{}','BRA',93),
('lg-romario','Romário','ATA','{}','BRA',94),
('lg-rivaldo','Rivaldo','MEI','{PE}','BRA',92),
('lg-kaka','Kaká','MEI','{}','BRA',91),
('lg-roberto-carlos','Roberto Carlos','LE','{}','BRA',91),
('lg-cafu','Cafu','LD','{}','BRA',91),
('lg-socrates','Sócrates','MC','{MEI}','BRA',91),
('lg-falcao','Falcão','VOL','{MC}','BRA',90),
('lg-carlos-alberto-torres','Carlos Alberto Torres','LD','{}','BRA',90),
('lg-rivellino','Rivellino','MEI','{PE}','BRA',91),
('lg-tostao','Tostão','ATA','{MEI}','BRA',90),
('lg-jairzinho','Jairzinho','PD','{ATA}','BRA',90),
('lg-didi','Didi','MC','{}','BRA',91),
('lg-nilton-santos','Nilton Santos','LE','{}','BRA',91),
('lg-djalma-santos','Djalma Santos','LD','{}','BRA',90),
('lg-gerson','Gérson','MC','{}','BRA',90),
('lg-bebeto','Bebeto','ATA','{}','BRA',88),
('lg-careca','Careca','ATA','{}','BRA',89),
('lg-junior','Júnior','LE','{MC}','BRA',89),
('lg-leandro','Leandro','LD','{}','BRA',88),
('lg-claudio-taffarel','Cláudio Taffarel','GOL','{}','BRA',88),
('lg-dida','Dida','GOL','{}','BRA',87),
('lg-gilmar','Gilmar','GOL','{}','BRA',89),
('lg-lucio','Lúcio','ZAG','{}','BRA',88),
('lg-aldair','Aldair','ZAG','{}','BRA',88),
('lg-dunga','Dunga','VOL','{}','BRA',87),
('lg-mauro-silva','Mauro Silva','VOL','{}','BRA',87),
('lg-juninho-pernambucano','Juninho Pernambucano','MC','{MEI}','BRA',88),
('lg-adriano-imperador','Adriano Imperador','ATA','{}','BRA',89),
('lg-robinho','Robinho','PE','{ATA}','BRA',86),
('lg-djalminha','Djalminha','MEI','{}','BRA',86),
('lg-alex','Alex','MEI','{}','BRA',87),
('lg-marcos','Marcos','GOL','{}','BRA',87),
('lg-rogerio-ceni','Rogério Ceni','GOL','{}','BRA',87),
('lg-edmundo','Edmundo','ATA','{}','BRA',86),
('lg-rai','Raí','MEI','{}','BRA',87),
('lg-zagallo','Zagallo','PE','{}','BRA',87),
('lg-ademir-da-guia','Ademir da Guia','MEI','{}','BRA',88),
('lg-reinaldo','Reinaldo','ATA','{}','BRA',87),
('lg-roberto-dinamite','Roberto Dinamite','ATA','{}','BRA',88),
('lg-leonidas-da-silva','Leônidas da Silva','ATA','{}','BRA',90),
('lg-zizinho','Zizinho','MEI','{}','BRA',90),
('lg-vava','Vavá','ATA','{}','BRA',88),
('lg-gilberto-silva','Gilberto Silva','VOL','{}','BRA',86),
('lg-juan','Juan','ZAG','{}','BRA',85),
('lg-ze-roberto','Zé Roberto','MC','{LE}','BRA',86),
('lg-elano','Elano','MC','{}','BRA',84),
('lg-diego-ribas','Diego Ribas','MEI','{}','BRA',85),
('lg-fred','Fred','ATA','{}','BRA',85),
('lg-luis-fabiano','Luís Fabiano','ATA','{}','BRA',86),
('lg-maicon','Maicon','LD','{}','BRA',87),
('lg-julio-cesar','Júlio César','GOL','{}','BRA',88),
('lg-gabriel-batistuta','Gabriel Batistuta','ATA','{}','ARG',92),
('lg-daniel-passarella','Daniel Passarella','ZAG','{}','ARG',91),
('lg-mario-kempes','Mario Kempes','ATA','{}','ARG',91),
('lg-juan-roman-riquelme','Juan Román Riquelme','MEI','{}','ARG',90),
('lg-javier-zanetti','Javier Zanetti','LD','{VOL}','ARG',90),
('lg-fernando-redondo','Fernando Redondo','VOL','{}','ARG',90),
('lg-hernan-crespo','Hernán Crespo','ATA','{}','ARG',89),
('lg-carlos-tevez','Carlos Tevez','ATA','{}','ARG',88),
('lg-javier-mascherano','Javier Mascherano','VOL','{ZAG}','ARG',88),
('lg-diego-simeone','Diego Simeone','VOL','{}','ARG',87),
('lg-roberto-ayala','Roberto Ayala','ZAG','{}','ARG',88),
('lg-juan-sebastian-veron','Juan Sebastián Verón','MC','{}','ARG',88),
('lg-pablo-aimar','Pablo Aimar','MEI','{}','ARG',87),
('lg-ariel-ortega','Ariel Ortega','MEI','{PD}','ARG',86),
('lg-claudio-caniggia','Claudio Caniggia','ATA','{PD}','ARG',87),
('lg-jorge-burruchaga','Jorge Burruchaga','MEI','{}','ARG',87),
('lg-ubaldo-fillol','Ubaldo Fillol','GOL','{}','ARG',89),
('lg-oscar-ruggeri','Oscar Ruggeri','ZAG','{}','ARG',87),
('lg-ricardo-bochini','Ricardo Bochini','MEI','{}','ARG',88),
('lg-omar-sivori','Omar Sívori','ATA','{}','ARG',91),
('lg-esteban-cambiasso','Esteban Cambiasso','VOL','{}','ARG',86),
('lg-walter-samuel','Walter Samuel','ZAG','{}','ARG',87),
('lg-diego-milito','Diego Milito','ATA','{}','ARG',87),
('lg-sergio-aguero','Sergio Agüero','ATA','{}','ARG',91),
('lg-gonzalo-higuain','Gonzalo Higuaín','ATA','{}','ARG',88),
('lg-javier-saviola','Javier Saviola','ATA','{}','ARG',85),
('lg-martin-palermo','Martín Palermo','ATA','{}','ARG',85),
('lg-enzo-francescoli','Enzo Francescoli','MEI','{ATA}','URU',91),
('lg-diego-forlan','Diego Forlán','ATA','{}','URU',89),
('lg-obdulio-varela','Obdulio Varela','VOL','{}','URU',90),
('lg-juan-alberto-schiaffino','Juan Alberto Schiaffino','MEI','{}','URU',92),
('lg-jose-nasazzi','José Nasazzi','ZAG','{}','URU',89),
('lg-alvaro-recoba','Álvaro Recoba','MEI','{ATA}','URU',87),
('lg-diego-lugano','Diego Lugano','ZAG','{}','URU',85),
('lg-diego-godin','Diego Godín','ZAG','{}','URU',89),
('lg-paolo-montero','Paolo Montero','ZAG','{}','URU',86),
('lg-carlos-valderrama','Carlos Valderrama','MEI','{}','COL',89),
('lg-faustino-asprilla','Faustino Asprilla','ATA','{}','COL',87),
('lg-rene-higuita','René Higuita','GOL','{}','COL',85),
('lg-freddy-rincon','Freddy Rincón','MC','{}','COL',86),
('lg-ivan-cordoba','Iván Córdoba','ZAG','{}','COL',86),
('lg-elias-figueroa','Elías Figueroa','ZAG','{}','CHI',91),
('lg-ivan-zamorano','Iván Zamorano','ATA','{}','CHI',88),
('lg-marcelo-salas','Marcelo Salas','ATA','{}','CHI',88),
('lg-jose-luis-chilavert','José Luis Chilavert','GOL','{}','PAR',89),
('lg-roque-santa-cruz','Roque Santa Cruz','ATA','{}','PAR',84),
('lg-carlos-gamarra','Carlos Gamarra','ZAG','{}','PAR',87),
('lg-teofilo-cubillas','Teófilo Cubillas','MEI','{}','PER',90),
('lg-claudio-pizarro','Claudio Pizarro','ATA','{}','PER',85),
('lg-hugo-sanchez','Hugo Sánchez','ATA','{}','MEX',90),
('lg-rafael-marquez','Rafael Márquez','ZAG','{VOL}','MEX',87),
('lg-cuauhtemoc-blanco','Cuauhtémoc Blanco','MEI','{ATA}','MEX',86),
('lg-jorge-campos','Jorge Campos','GOL','{}','MEX',84),
('lg-marco-van-basten','Marco van Basten','ATA','{}','NED',94),
('lg-ruud-gullit','Ruud Gullit','MEI','{ATA}','NED',93),
('lg-frank-rijkaard','Frank Rijkaard','VOL','{ZAG}','NED',92),
('lg-dennis-bergkamp','Dennis Bergkamp','ATA','{MEI}','NED',91),
('lg-ronald-koeman','Ronald Koeman','ZAG','{}','NED',90),
('lg-clarence-seedorf','Clarence Seedorf','MC','{}','NED',90),
('lg-edgar-davids','Edgar Davids','VOL','{}','NED',89),
('lg-patrick-kluivert','Patrick Kluivert','ATA','{}','NED',88),
('lg-ruud-van-nistelrooy','Ruud van Nistelrooy','ATA','{}','NED',90),
('lg-arjen-robben','Arjen Robben','PD','{}','NED',91),
('lg-wesley-sneijder','Wesley Sneijder','MEI','{}','NED',89),
('lg-robin-van-persie','Robin van Persie','ATA','{}','NED',90),
('lg-edwin-van-der-sar','Edwin van der Sar','GOL','{}','NED',90),
('lg-johan-neeskens','Johan Neeskens','MC','{}','NED',91),
('lg-ruud-krol','Ruud Krol','ZAG','{LE}','NED',90),
('lg-marc-overmars','Marc Overmars','PE','{}','NED',87),
('lg-frank-de-boer','Frank de Boer','ZAG','{}','NED',88),
('lg-jaap-stam','Jaap Stam','ZAG','{}','NED',88),
('lg-gerd-muller','Gerd Müller','ATA','{}','GER',94),
('lg-lothar-matthaus','Lothar Matthäus','MC','{ZAG}','GER',93),
('lg-karl-heinz-rummenigge','Karl-Heinz Rummenigge','ATA','{}','GER',92),
('lg-paul-breitner','Paul Breitner','LE','{MC}','GER',91),
('lg-sepp-maier','Sepp Maier','GOL','{}','GER',91),
('lg-oliver-kahn','Oliver Kahn','GOL','{}','GER',91),
('lg-philipp-lahm','Philipp Lahm','LD','{LE}','GER',91),
('lg-bastian-schweinsteiger','Bastian Schweinsteiger','MC','{VOL}','GER',90),
('lg-miroslav-klose','Miroslav Klose','ATA','{}','GER',89),
('lg-michael-ballack','Michael Ballack','MC','{}','GER',90),
('lg-jurgen-klinsmann','Jürgen Klinsmann','ATA','{}','GER',90),
('lg-rudi-voller','Rudi Völler','ATA','{}','GER',88),
('lg-andreas-brehme','Andreas Brehme','LE','{}','GER',89),
('lg-matthias-sammer','Matthias Sammer','ZAG','{VOL}','GER',90),
('lg-uwe-seeler','Uwe Seeler','ATA','{}','GER',90),
('lg-gunter-netzer','Günter Netzer','MEI','{}','GER',90),
('lg-fritz-walter','Fritz Walter','MEI','{}','GER',90),
('lg-mesut-ozil','Mesut Özil','MEI','{}','GER',88),
('lg-per-mertesacker','Per Mertesacker','ZAG','{}','GER',85),
('lg-paolo-maldini','Paolo Maldini','LE','{ZAG}','ITA',94),
('lg-franco-baresi','Franco Baresi','ZAG','{}','ITA',94),
('lg-roberto-baggio','Roberto Baggio','MEI','{ATA}','ITA',93),
('lg-alessandro-del-piero','Alessandro Del Piero','ATA','{MEI}','ITA',91),
('lg-francesco-totti','Francesco Totti','MEI','{ATA}','ITA',91),
('lg-andrea-pirlo','Andrea Pirlo','MC','{VOL}','ITA',92),
('lg-gianluigi-buffon','Gianluigi Buffon','GOL','{}','ITA',93),
('lg-fabio-cannavaro','Fabio Cannavaro','ZAG','{}','ITA',91),
('lg-alessandro-nesta','Alessandro Nesta','ZAG','{}','ITA',92),
('lg-dino-zoff','Dino Zoff','GOL','{}','ITA',92),
('lg-gaetano-scirea','Gaetano Scirea','ZAG','{}','ITA',92),
('lg-giuseppe-meazza','Giuseppe Meazza','ATA','{}','ITA',92),
('lg-gianni-rivera','Gianni Rivera','MEI','{}','ITA',91),
('lg-luigi-riva','Luigi Riva','ATA','{}','ITA',91),
('lg-paolo-rossi','Paolo Rossi','ATA','{}','ITA',90),
('lg-giacinto-facchetti','Giacinto Facchetti','LE','{}','ITA',91),
('lg-marco-tardelli','Marco Tardelli','MC','{}','ITA',88),
('lg-gennaro-gattuso','Gennaro Gattuso','VOL','{}','ITA',87),
('lg-christian-vieri','Christian Vieri','ATA','{}','ITA',89),
('lg-filippo-inzaghi','Filippo Inzaghi','ATA','{}','ITA',87),
('lg-gianfranco-zola','Gianfranco Zola','MEI','{ATA}','ITA',88),
('lg-daniele-de-rossi','Daniele De Rossi','VOL','{}','ITA',88),
('lg-giorgio-chiellini','Giorgio Chiellini','ZAG','{}','ITA',90),
('lg-andrea-barzagli','Andrea Barzagli','ZAG','{}','ITA',87),
('lg-gianluca-zambrotta','Gianluca Zambrotta','LD','{LE}','ITA',88),
('lg-luca-toni','Luca Toni','ATA','{}','ITA',86),
('lg-bobby-charlton','Bobby Charlton','MEI','{}','ENG',92),
('lg-bobby-moore','Bobby Moore','ZAG','{}','ENG',92),
('lg-gordon-banks','Gordon Banks','GOL','{}','ENG',91),
('lg-gary-lineker','Gary Lineker','ATA','{}','ENG',89),
('lg-alan-shearer','Alan Shearer','ATA','{}','ENG',90),
('lg-david-beckham','David Beckham','PD','{MC}','ENG',89),
('lg-steven-gerrard','Steven Gerrard','MC','{}','ENG',90),
('lg-frank-lampard','Frank Lampard','MC','{}','ENG',89),
('lg-paul-scholes','Paul Scholes','MC','{}','ENG',90),
('lg-wayne-rooney','Wayne Rooney','ATA','{}','ENG',90),
('lg-rio-ferdinand','Rio Ferdinand','ZAG','{}','ENG',89),
('lg-john-terry','John Terry','ZAG','{}','ENG',89),
('lg-ashley-cole','Ashley Cole','LE','{}','ENG',88),
('lg-michael-owen','Michael Owen','ATA','{}','ENG',88),
('lg-paul-gascoigne','Paul Gascoigne','MEI','{}','ENG',88),
('lg-kevin-keegan','Kevin Keegan','ATA','{}','ENG',89),
('lg-stanley-matthews','Stanley Matthews','PD','{}','ENG',91),
('lg-jimmy-greaves','Jimmy Greaves','ATA','{}','ENG',90),
('lg-peter-shilton','Peter Shilton','GOL','{}','ENG',89),
('lg-david-seaman','David Seaman','GOL','{}','ENG',87),
('lg-tony-adams','Tony Adams','ZAG','{}','ENG',87),
('lg-sol-campbell','Sol Campbell','ZAG','{}','ENG',87),
('lg-george-best','George Best','PE','{PD}','NIR',93),
('lg-kenny-dalglish','Kenny Dalglish','ATA','{}','SCO',90),
('lg-denis-law','Denis Law','ATA','{}','SCO',90),
('lg-ryan-giggs','Ryan Giggs','PE','{}','WAL',89),
('lg-ian-rush','Ian Rush','ATA','{}','WAL',88),
('lg-gareth-bale','Gareth Bale','PD','{PE}','WAL',89),
('lg-roy-keane','Roy Keane','VOL','{}','IRL',89),
('lg-thierry-henry','Thierry Henry','ATA','{PE}','FRA',93),
('lg-just-fontaine','Just Fontaine','ATA','{}','FRA',90),
('lg-raymond-kopa','Raymond Kopa','MEI','{}','FRA',91),
('lg-patrick-vieira','Patrick Vieira','VOL','{MC}','FRA',90),
('lg-lilian-thuram','Lilian Thuram','LD','{ZAG}','FRA',90),
('lg-marcel-desailly','Marcel Desailly','ZAG','{VOL}','FRA',90),
('lg-laurent-blanc','Laurent Blanc','ZAG','{}','FRA',89),
('lg-didier-deschamps','Didier Deschamps','VOL','{}','FRA',88),
('lg-claude-makelele','Claude Makélélé','VOL','{}','FRA',88),
('lg-franck-ribery','Franck Ribéry','PE','{}','FRA',90),
('lg-david-trezeguet','David Trezeguet','ATA','{}','FRA',88),
('lg-eric-cantona','Éric Cantona','ATA','{MEI}','FRA',90),
('lg-jean-pierre-papin','Jean-Pierre Papin','ATA','{}','FRA',89),
('lg-fabien-barthez','Fabien Barthez','GOL','{}','FRA',87),
('lg-bixente-lizarazu','Bixente Lizarazu','LE','{}','FRA',87),
('lg-robert-pires','Robert Pirès','PE','{MEI}','FRA',87),
('lg-alain-giresse','Alain Giresse','MEI','{}','FRA',88),
('lg-jean-tigana','Jean Tigana','MC','{}','FRA',88),
('lg-xavi-hernandez','Xavi Hernández','MC','{}','ESP',93),
('lg-andres-iniesta','Andrés Iniesta','MC','{MEI}','ESP',93),
('lg-iker-casillas','Iker Casillas','GOL','{}','ESP',91),
('lg-carles-puyol','Carles Puyol','ZAG','{}','ESP',90),
('lg-raul-gonzalez','Raúl González','ATA','{}','ESP',91),
('lg-fernando-hierro','Fernando Hierro','ZAG','{}','ESP',89),
('lg-david-villa','David Villa','ATA','{}','ESP',90),
('lg-fernando-torres','Fernando Torres','ATA','{}','ESP',88),
('lg-xabi-alonso','Xabi Alonso','VOL','{MC}','ESP',90),
('lg-gerard-pique','Gerard Piqué','ZAG','{}','ESP',89),
('lg-david-silva','David Silva','MEI','{}','ESP',90),
('lg-cesc-fabregas','Cesc Fàbregas','MC','{}','ESP',88),
('lg-luis-suarez-miramontes','Luis Suárez Miramontes','MEI','{}','ESP',91),
('lg-emilio-butragueno','Emilio Butragueño','ATA','{}','ESP',89),
('lg-pep-guardiola','Pep Guardiola','VOL','{}','ESP',87),
('lg-luis-enrique','Luis Enrique','MC','{}','ESP',87),
('lg-fernando-morientes','Fernando Morientes','ATA','{}','ESP',86),
('lg-paco-gento','Paco Gento','PE','{}','ESP',91),
('lg-eusebio','Eusébio','ATA','{}','POR',94),
('lg-luis-figo','Luís Figo','PD','{}','POR',92),
('lg-rui-costa','Rui Costa','MEI','{}','POR',89),
('lg-deco','Deco','MEI','{}','POR',88),
('lg-ricardo-carvalho','Ricardo Carvalho','ZAG','{}','POR',88),
('lg-paulo-futre','Paulo Futre','PE','{}','POR',88),
('lg-nani','Nani','PE','{PD}','POR',85),
('lg-lev-yashin','Lev Yashin','GOL','{}','RUS',94),
('lg-oleg-blokhin','Oleg Blokhin','ATA','{}','UKR',90),
('lg-andriy-shevchenko','Andriy Shevchenko','ATA','{}','UKR',91),
('lg-rinat-dasayev','Rinat Dasayev','GOL','{}','RUS',88),
('lg-andrey-arshavin','Andrey Arshavin','MEI','{}','RUS',85),
('lg-pavel-nedved','Pavel Nedvěd','MEI','{PE}','CZE',91),
('lg-josef-masopust','Josef Masopust','MC','{}','CZE',90),
('lg-petr-cech','Petr Čech','GOL','{}','CZE',90),
('lg-tomas-rosicky','Tomáš Rosický','MEI','{}','CZE',86),
('lg-jan-koller','Jan Koller','ATA','{}','CZE',84),
('lg-hristo-stoichkov','Hristo Stoichkov','ATA','{PE}','BUL',91),
('lg-dimitar-berbatov','Dimitar Berbatov','ATA','{}','BUL',87),
('lg-gheorghe-hagi','Gheorghe Hagi','MEI','{}','ROU',90),
('lg-dragan-stojkovic','Dragan Stojković','MEI','{}','SRB',88),
('lg-nemanja-vidic','Nemanja Vidić','ZAG','{}','SRB',89),
('lg-dejan-stankovic','Dejan Stanković','MC','{}','SRB',86),
('lg-davor-suker','Davor Šuker','ATA','{}','CRO',89),
('lg-zvonimir-boban','Zvonimir Boban','MEI','{}','CRO',88),
('lg-robert-prosinecki','Robert Prosinečki','MEI','{}','CRO',88),
('lg-ivan-rakitic','Ivan Rakitić','MC','{}','CRO',87),
('lg-mario-mandzukic','Mario Mandžukić','ATA','{}','CRO',86),
('lg-darijo-srna','Darijo Srna','LD','{}','CRO',85),
('lg-zlatan-ibrahimovic','Zlatan Ibrahimović','ATA','{}','SWE',92),
('lg-henrik-larsson','Henrik Larsson','ATA','{}','SWE',88),
('lg-freddie-ljungberg','Freddie Ljungberg','PD','{}','SWE',85),
('lg-michael-laudrup','Michael Laudrup','MEI','{}','DEN',91),
('lg-peter-schmeichel','Peter Schmeichel','GOL','{}','DEN',91),
('lg-brian-laudrup','Brian Laudrup','PD','{ATA}','DEN',88),
('lg-ole-gunnar-solskjr','Ole Gunnar Solskjær','ATA','{}','NOR',85),
('lg-jari-litmanen','Jari Litmanen','MEI','{}','FIN',88),
('lg-sami-hyypia','Sami Hyypiä','ZAG','{}','FIN',86),
('lg-zbigniew-boniek','Zbigniew Boniek','MEI','{ATA}','POL',90),
('lg-grzegorz-lato','Grzegorz Lato','PD','{}','POL',88),
('lg-kazimierz-deyna','Kazimierz Deyna','MEI','{}','POL',89),
('lg-sandor-kocsis','Sándor Kocsis','ATA','{}','HUN',91),
('lg-nandor-hidegkuti','Nándor Hidegkuti','ATA','{MEI}','HUN',90),
('lg-hans-krankl','Hans Krankl','ATA','{}','AUT',87),
('lg-matthias-sindelar','Matthias Sindelar','ATA','{}','AUT',90),
('lg-stephane-chapuisat','Stéphane Chapuisat','ATA','{}','SUI',85),
('lg-jean-marie-pfaff','Jean-Marie Pfaff','GOL','{}','BEL',88),
('lg-enzo-scifo','Enzo Scifo','MEI','{}','BEL',88),
('lg-vincent-kompany','Vincent Kompany','ZAG','{}','BEL',89),
('lg-eden-hazard','Eden Hazard','PE','{}','BEL',91),
('lg-paul-van-himst','Paul Van Himst','ATA','{}','BEL',89),
('lg-hakan-sukur','Hakan Şükür','ATA','{}','TUR',86),
('lg-rustu-recber','Rüştü Reçber','GOL','{}','TUR',85),
('lg-theodoros-zagorakis','Theodoros Zagorakis','MC','{}','GRE',84),
('lg-george-weah','George Weah','ATA','{}','LBR',91),
('lg-samuel-eto-o','Samuel Eto''o','ATA','{}','CMR',91),
('lg-roger-milla','Roger Milla','ATA','{}','CMR',88),
('lg-didier-drogba','Didier Drogba','ATA','{}','CIV',89),
('lg-yaya-toure','Yaya Touré','MC','{VOL}','CIV',89),
('lg-kolo-toure','Kolo Touré','ZAG','{}','CIV',85),
('lg-jay-jay-okocha','Jay-Jay Okocha','MEI','{}','NGA',87),
('lg-nwankwo-kanu','Nwankwo Kanu','ATA','{}','NGA',86),
('lg-michael-essien','Michael Essien','VOL','{MC}','GHA',87),
('lg-abedi-pele','Abedi Pelé','MEI','{}','GHA',88),
('lg-rabah-madjer','Rabah Madjer','ATA','{}','ALG',87),
('lg-mustapha-hadji','Mustapha Hadji','MEI','{}','MAR',84),
('lg-el-hadji-diouf','El Hadji Diouf','ATA','{}','SEN',83),
('lg-frederic-kanoute','Frédéric Kanouté','ATA','{}','MLI',85),
('lg-mohamed-aboutrika','Mohamed Aboutrika','MEI','{}','EGY',86),
('lg-hidetoshi-nakata','Hidetoshi Nakata','MEI','{}','JPN',85),
('lg-shunsuke-nakamura','Shunsuke Nakamura','MEI','{}','JPN',84),
('lg-park-ji-sung','Park Ji-sung','MC','{PE}','KOR',85),
('lg-cha-bum-kun','Cha Bum-kun','ATA','{}','KOR',87),
('lg-ali-daei','Ali Daei','ATA','{}','IRN',85),
('lg-tim-cahill','Tim Cahill','MEI','{ATA}','AUS',84),
('lg-harry-kewell','Harry Kewell','PE','{}','AUS',85),
('lg-mark-viduka','Mark Viduka','ATA','{}','AUS',84),
('lg-landon-donovan','Landon Donovan','MEI','{ATA}','USA',84),
('lg-clint-dempsey','Clint Dempsey','MEI','{ATA}','USA',83),
('lg-tim-howard','Tim Howard','GOL','{}','USA',84),
('lg-dwight-yorke','Dwight Yorke','ATA','{}','TRI',85),
('lg-alberto-spencer','Alberto Spencer','ATA','{}','ECU',89),
('lg-alex-aguinaga','Álex Aguinaga','MEI','{}','ECU',85),
('lg-antonio-valencia','Antonio Valencia','PD','{LD}','ECU',85),
('lg-juan-arango','Juan Arango','MEI','{}','VEN',85),
('lg-marco-etcheverry','Marco Etcheverry','MEI','{}','BOL',85),
('lg-arsenio-erico','Arsenio Erico','ATA','{}','PAR',90),
('lg-hector-chumpitaz','Héctor Chumpitaz','ZAG','{}','PER',88),
('lg-nolberto-solano','Nolberto Solano','PD','{}','PER',84),
('lg-leonel-sanchez','Leonel Sánchez','PE','{}','CHI',88),
('lg-mario-yepes','Mario Yepes','ZAG','{}','COL',84),
('lg-marcelo','Marcelo','LE','{}','BRA',90),
('lg-fernandinho','Fernandinho','VOL','{}','BRA',86),
('lg-toni-kroos','Toni Kroos','MC','{}','GER',91)
on conflict(id) do update set name=excluded.name,pos=excluded.pos,sec=excluded.sec,nat=excluded.nat,rating=excluded.rating;

insert into supabase_migrations.schema_migrations(version,name) values('20261112140000','online_phase9_market_legends'),('20261112150000','online_phase9_legends_data')
on conflict do nothing;
commit;
