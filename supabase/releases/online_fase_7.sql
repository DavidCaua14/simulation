-- Pacote de publicação do modo online, fase 7 (gerado de supabase/online/07_real_players.sql).
-- Rodar inteiro no SQL Editor ou pela API, como administrador. Tudo ou nada.
-- Depois: supabase/releases/online_reiniciar.sql (os elencos só passam a ser reais em uma temporada nova).
begin;

-- MODO ONLINE — Fase 7: jogadores reais, leilão com relógio de 5 minutos, energia de treino e pênaltis.
--
--  • Elencos, craques e leilões usam os jogadores do catálogo (sim_players + sim_player_base, linhas sem
--    career_id). Cada jogador real existe uma única vez no modo online (índice único em on_players.src), então
--    o mercado nunca oferece quem já está em um clube. Sem jogador real na faixa pedida, entra um gerado.
--  • Leilão: todo lance põe o relógio em bid_extend (5 minutos), para os outros técnicos poderem cobrir.
--  • Técnico não leiloa mais jogador do próprio elenco: vende direto ao mercado por 60% do valor (on_sell).
--  • Energia de treino: treinos extras no dia comprados com moedas da conta (train_energy_cost cada, até
--    train_energy_max por dia).
--  • Mini-game de pênaltis: treino individual do grupo de ataque.
--
-- Nenhuma função mgr_* ou cw_* é alterada; o catálogo é só lido.

alter table public.on_players add column if not exists src text;                 -- id em sim_players (nulo = jogador gerado)
alter table public.on_players add column if not exists hold int references public.on_clubs(id) on delete cascade; -- opção de craque reservada
alter table public.on_players add column if not exists hold_slot smallint;       -- passo*3 + opção (1 a 9)
create unique index if not exists on_players_src on public.on_players(src) where src is not null;
create index if not exists on_players_hold on public.on_players(hold) where hold is not null;
alter table public.on_clubs add column if not exists train_extra smallint not null default 0;
alter table public.on_config add column if not exists train_energy_cost int not null default 40;
alter table public.on_config add column if not exists train_energy_max smallint not null default 5;

alter table public.on_train drop constraint if exists on_train_game_check;
alter table public.on_train add constraint on_train_game_check check (game in('reaction','passing','aim','timing','tackle','dribble','penalty'));

-- ─────────────────────────────────────────────────────────────────────────────
-- Catálogo real
-- ─────────────────────────────────────────────────────────────────────────────

-- Jogador real livre (em nenhum clube, leilão ou reserva) da posição, com nota em [p_lo, p_hi). Sorteio pela semente.
-- p_pos nulo: qualquer posição.
create or replace function public.on_real_pick(p_pos text,p_lo numeric,p_hi numeric,p_seed text) returns text
language sql stable security definer set search_path=public as $$
 select p.id from public.sim_players p join public.sim_player_base b on b.player_id=p.id
 where p.career_id is null and p.active and (p_pos is null or p.position=p_pos) and b.rating>=p_lo and b.rating<p_hi
  and not exists(select 1 from public.on_players o where o.src=p.id)
 order by public.sim_hash01(p_seed||':'||p.id) limit 1
$$;

-- Copia o jogador real para on_players. Devolve o id novo.
create or replace function public.on_real_insert(p_src text,p_club int,p_number int,p_contract_end int,p_star boolean default false,
 p_hold int default null,p_hold_slot int default null) returns text
language sql security definer set search_path=public as $$
 insert into public.on_players(club_id,src,name,pos,sec,nat,age,level,pot,ovr,number,wage,contract_end,agg,disc,star,hold,hold_slot)
 select p_club,p.id,coalesce(nullif(p.short_name,''),p.full_name),p.position,
  array(select x from unnest(coalesce(p.secondary_positions,'{}')) x where x in(select code from public.sim_positions) and x<>p.position),
  coalesce(p.nationality,'BRA'),a.age,a.lvl,greatest(a.lvl,least(95,coalesce(b.potential,a.lvl)))::smallint,a.lvl,p_number,public.on_wage(a.lvl),p_contract_end,
  35+floor(public.sim_hash01(p.id||':agg')*40)::int,40+floor(public.sim_hash01(p.id||':disc')*45)::int,p_star,p_hold,p_hold_slot
 from public.sim_players p join public.sim_player_base b on b.player_id=p.id
 cross join lateral(select greatest(16,least(40,coalesce(b.age0,p.age,25)))::smallint age,round(b.rating)::smallint lvl) a
 where p.id=p_src
 returning id
$$;

-- 19 jogadores do elenco base: reais com nota perto de p_base (±4); posição sem jogador real livre recebe um gerado.
create or replace function public.on_gen_squad(p_club int,p_seed text,p_base int,p_contract_end int) returns void
language plpgsql security definer set search_path=public as $$
declare r record;v_src text;v_s text;
begin
 for r in select u.n::int n,u.pos from unnest(array['GOL','LD','ZAG','ZAG','VOL','LE','PD','MC','ATA','MEI','PE','GOL','ZAG','LD','MC','LE','VOL','MEI','ATA']) with ordinality u(pos,n) loop
  v_s:=p_seed||':g'||r.n;
  v_src:=public.on_real_pick(r.pos,p_base-4.5,p_base+4.5,v_s);
  if v_src is not null then
   perform public.on_real_insert(v_src,p_club,r.n,p_contract_end+floor(public.sim_hash01(v_s||':ct')*2)::int);
  else
   insert into public.on_players(club_id,name,pos,age,level,pot,ovr,number,wage,contract_end,agg,disc)
   select p_club,public.cw_regen_name('BRA',v_s),r.pos,a.age,a.lvl,
    least(92,a.lvl+floor(public.sim_hash01(v_s||':pot')*case when a.age<24 then 12 else 5 end)::int),
    a.lvl,r.n,public.on_wage(a.lvl),p_contract_end+floor(public.sim_hash01(v_s||':ct')*2)::int,
    35+floor(public.sim_hash01(v_s||':agg')*40)::int,40+floor(public.sim_hash01(v_s||':disc')*45)::int
   from(select 19+floor(public.sim_hash01(v_s||':age')*14)::int age,p_base-4+floor(public.sim_hash01(v_s||':lvl')*9)::int lvl) a;
  end if;
 end loop;
end $$;

-- Craque de uma linha (passo 0 defesa, 1 meio-campo, 2 ataque; p_i de 1 a 3), real com nota em [p_lo, p_hi).
-- Devolve o id em on_players. Sem real livre, usa o gerador antigo.
create or replace function public.on_star_add(p_club int,p_seed text,p_step int,p_i int,p_lo numeric,p_hi numeric,p_contract_end int,
 p_hold int default null) returns text
language plpgsql security definer set search_path=public as $$
declare v_pos text:=(array['ZAG','LD','LE','VOL','MC','MEI','PD','ATA','PE'])[p_step*3+p_i];v_src text;v_id text;
begin
 v_src:=public.on_real_pick(v_pos,p_lo,p_hi,p_seed||':star'||p_step||':'||p_i);
 if v_src is not null then
  return public.on_real_insert(v_src,p_club,21+p_step,p_contract_end,true,p_hold,case when p_hold is null then null else p_step*3+p_i end);
 end if;
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,number,wage,contract_end,star,hold,hold_slot)
 select p_club,st.name,st.pos,st.age,least(st.level,floor(p_hi)::int-1),st.pot,least(st.level,floor(p_hi)::int-1),21+p_step,
  public.on_wage(least(st.level,floor(p_hi)::int-1)),p_contract_end,true,p_hold,case when p_hold is null then null else p_step*3+p_i end
 from public.on_star(p_seed,p_step,p_i) st returning id into v_id;
 return v_id;
end $$;

-- Reserva as nove opções de craque do clube (três por linha). Nada acontece se já existem.
create or replace function public.on_draft_prepare(p_club int) returns void
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs;v_seed text;st int;i int;
begin
 select * into c from public.on_clubs where id=p_club for update;
 if c.draft_step>=3 or exists(select 1 from public.on_players where hold=p_club) then return;end if;
 select s.seed||':'||c.id into v_seed from public.on_seasons s where s.id=c.season_id;
 for st in c.draft_step..2 loop
  for i in 1..3 loop
   perform public.on_star_add(null,v_seed,st,i,77.5,82.5,c.season_id+2,p_club);
  end loop;
 end loop;
end $$;

create or replace function public.on_draft_read() returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();
begin
 if c.draft_step<3 and not exists(select 1 from public.on_players where hold=c.id) then perform public.on_draft_prepare(c.id);end if;
 return jsonb_build_object('step',c.draft_step,'done',c.draft_step>=3,
  'line',(array['DEF','MID','ATT'])[c.draft_step+1],
  'club',jsonb_build_object('id',c.id,'name',c.name,'short',c.short,'colors',c.colors),
  'options',coalesce((select jsonb_agg(jsonb_build_object('idx',p.hold_slot-c.draft_step*3,'name',p.name,'pos',p.pos,'nat',p.nat,
    'age',p.age,'ovr',p.level,'pot',p.pot,'value',public.on_value(p.level,p.age,p.pot),'wage',p.wage,
    'card',public.on_card(p.id,p.pos,p.level,p.g)) order by p.hold_slot)
   from public.on_players p where p.hold=c.id and p.hold_slot between c.draft_step*3+1 and c.draft_step*3+3),'[]'::jsonb),
  'picked',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'nat',p.nat,'age',p.age,'ovr',p.ovr,'pot',p.pot,
    'card',public.on_card(p.id,p.pos,p.level,p.g)) order by p.number)
   from public.on_players p where p.club_id=c.id and p.star),'[]'::jsonb));
end $$;

-- Contrata a opção p_idx do passo p_step; as outras duas da linha voltam ao mercado. Repetir o mesmo passo não contrata duas vezes.
create or replace function public.on_draft_pick(p_step int,p_idx int) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);
begin
 if p_idx is null or p_idx not between 1 and 3 then raise exception 'Opção inválida';end if;
 if c.draft_step=p_step and c.draft_step<3 then
  if not exists(select 1 from public.on_players where hold=c.id) then perform public.on_draft_prepare(c.id);end if;
  update public.on_players set club_id=c.id,hold=null,hold_slot=null where hold=c.id and hold_slot=p_step*3+p_idx;
  if not found then raise exception 'Opção indisponível';end if;
  delete from public.on_players where hold=c.id and hold_slot between p_step*3+1 and p_step*3+3;
  update public.on_clubs set draft_step=draft_step+1 where id=c.id;
  if c.draft_step=2 then perform public.on_auto_lineup(c.id);end if;
 end if;
 return public.on_draft_read();
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Criação da temporada com jogadores reais
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_season_bootstrap(p_users uuid[],p_start date,p_kind text default 'main',
 p_gap interval default null,p_now timestamptz default now(),p_cash bigint default 150000) returns smallint
language plpgsql security definer set search_path=public as $$
declare v_s smallint;v_seed text:=md5(gen_random_uuid()::text);r record;n int:=coalesce(cardinality(p_users),0);k int;
 bots constant text[]:=array['Aurora FC','Real Maré','Estrela do Norte','União Serrana','Porto Vila','Ferroviário Central','Guarani do Vale',
  'Atlético Ipê','Vila Rica','Náutico Lagoa','Operário Minas','Sport Bandeira'];
 homes constant text[]:=array['Arena Aurora','Estádio da Maré','Estádio Boreal','Serra Dourada do Vale','Cais do Porto','Estação Central','Ninho do Vale',
  'Bosque dos Ipês','Vila Olímpica','Estádio da Lagoa','Mina Velha','Arena Bandeira'];
 pal constant text[]:=array['#e63946','#1d3557','#2a9d8f','#f4a261','#6a4c93','#118ab2','#ef476f','#06d6a0','#ffd166','#8d99ae','#bc6c25','#3a86ff'];
 pat constant text[]:=array['stripes','hoops','plain','sash','halves','chevron'];
 shp constant text[]:=array['shield','round','shield','diamond'];
begin
 if n>12 then raise exception 'No máximo 12 usuários por temporada';end if;
 if n<>(select count(distinct u) from unnest(p_users) u) then raise exception 'Usuário repetido';end if;
 if exists(select 1 from public.on_seasons where status='live') then raise exception 'Já existe uma temporada online em andamento';end if;
 insert into public.on_seasons(kind,starts_on,seed,gap) values(p_kind,p_start,v_seed,p_gap) returning id into v_s;

 insert into public.on_access(user_id,state) select u,'allowed' from unnest(p_users) u
 on conflict(user_id) do update set state='allowed';

 insert into public.on_clubs(season_id,user_id,seat,name,short,colors,cash,draft_step)
 select v_s,u.uid,row_number() over(order by public.sim_hash01(v_seed||':seat:'||g.i))::smallint,
  coalesce('FC '||nk.nickname,bots[g.i-n]),
  upper(left(coalesce(nullif(regexp_replace(nk.nickname,'[^A-Za-z0-9]','','g'),''),regexp_replace(bots[g.i-n],'[^A-Za-zÀ-ú]','','g')),3)),
  jsonb_build_object('a',pal[g.i],'b',case when g.i%3=0 then '#111827' else '#ffffff' end,
   'pattern',pat[1+(g.i-1)%6],'shape',shp[1+(g.i-1)%4],
   'stadium',case when u.uid is null then homes[g.i-n] else 'Arena '||left(coalesce(nk.nickname,'do Clube'),20) end),
  p_cash,case when u.uid is null then 3 else 0 end
 from generate_series(1,12) g(i)
 left join unnest(p_users) with ordinality u(uid,i) on u.i=g.i
 left join lateral(select c.nickname from public.careers c where c.user_id=u.uid order by (c.status='active') desc,c.created_at desc limit 1) nk on true;

 -- Elencos reais: 19 jogadores por clube. Técnicos escolhem 3 craques (78 a 82); bots recebem os deles um pouco abaixo (76 a 80).
 for r in select c.id,c.user_id from public.on_clubs c where c.season_id=v_s order by c.id loop
  perform public.on_gen_squad(r.id,v_seed||':'||r.id,
   case when r.user_id is null then 60+floor(public.sim_hash01(v_seed||':base:'||r.id)*5)::int else 62 end,v_s+1);
  if r.user_id is null then
   for k in 0..2 loop
    perform public.on_star_add(r.id,v_seed||':'||r.id,k,1+floor(public.sim_hash01(v_seed||':botpick:'||r.id||':'||k)*3)::int,76,80.5,v_s+1);
   end loop;
   perform public.on_auto_lineup(r.id);
  else
   perform public.on_draft_prepare(r.id);
  end if;
 end loop;

 perform public.on_league_fixtures(v_s,p_start,p_gap,p_now);
 insert into public.on_table(season_id,club_id) select v_s,c.id from public.on_clubs c where c.season_id=v_s;
 return v_s;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Mercado
-- ─────────────────────────────────────────────────────────────────────────────

-- Destaque: jogador real livre da faixa (1: 77 a 85; 2: 70 a 77; 3: 62 a 70). Nunca alguém que já tem clube.
create or replace function public.on_gen_featured(p_seed text,p_tier int) returns text
language plpgsql security definer set search_path=public as $$
declare v_lo numeric:=(array[77,70,62])[p_tier];v_hi numeric:=(array[85.5,77,70])[p_tier];v_src text;v_id text;
 v_pos text:=(array['GOL','LD','ZAG','ZAG','LE','VOL','MC','MEI','PD','PE','ATA','ATA'])[1+floor(public.sim_hash01(p_seed||':p')*12)::int];
 v_end int:=(select max(id) from public.on_seasons)+1+floor(public.sim_hash01(p_seed||':ct')*2)::int;
begin
 v_src:=coalesce(public.on_real_pick(v_pos,v_lo,v_hi,p_seed),public.on_real_pick(null,v_lo,v_hi,p_seed));
 if v_src is not null then
  v_id:=public.on_real_insert(v_src,null,null,v_end);
  update public.on_players set star=level>=80 where id=v_id;
  return v_id;
 end if;
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end,agg,disc,star)
 select null,public.cw_regen_name('BRA',p_seed),v_pos,a.age,a.lvl,least(94,a.lvl+floor(public.sim_hash01(p_seed||':pot')*case when a.age<23 then 12 else 5 end)::int),
  a.lvl,public.on_wage(a.lvl),v_end,35+floor(public.sim_hash01(p_seed||':agg')*40)::int,40+floor(public.sim_hash01(p_seed||':disc')*45)::int,a.lvl>=80
 from(select 18+floor(public.sim_hash01(p_seed||':age')*15)::int age,floor(v_lo+public.sim_hash01(p_seed||':lvl')*(v_hi-v_lo))::int lvl) a
 returning id into v_id;
 return v_id;
end $$;

-- Lance de um clube. Todo lance põe o relógio do lote em bid_extend (5 minutos), até o teto do lote.
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
  ends_at=least(hard_end,p_now+(select bid_extend from public.on_config)) where id=l.id;
 insert into public.on_bids(lot_id,club_id,amount,at) values(l.id,p_club,p_amount,p_now);
end $$;

-- Venda direta ao mercado: 60% do valor, na hora. O jogador sai do modo (um real volta a ficar livre para leilão).
create or replace function public.on_sell(p_player text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);p public.on_players;v bigint;
begin
 select * into p from public.on_players where id=p_player and club_id=c.id for update;
 if p.id is null then raise exception 'Jogador fora do seu elenco';end if;
 if (select count(*) from public.on_players where club_id=c.id)<=16 then raise exception 'Elenco com 16 jogadores: não dá para vender mais';end if;
 if public.on_in_live(p.id) then raise exception 'Ele está jogando agora. Venda depois do apito final.';end if;
 if exists(select 1 from public.on_lots where player_id=p.id and status='open') then raise exception 'Esse jogador está em leilão';end if;
 v:=round(public.on_value(p.ovr,p.age,p.pot)*.6)::bigint;
 perform public.on_money(c.id,v,'sell',p.name);
 delete from public.on_players where id=p.id;
 perform public.on_lineup_repair(c.id);
 insert into public.on_news(club_id,kind,text) values(c.id,'market',format('%s foi vendido por $ %s.',p.name,v));
 return public.on_squad();
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Treino: pênaltis (individual) e energia de treino
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_train_group(p_game text) returns int
language sql immutable as $$ select case p_game when 'reaction' then 1 when 'tackle' then 1 when 'passing' then 2 when 'aim' then 3 when 'penalty' then 3 else 4 end $$;

-- Treinos permitidos hoje: os do dia mais os extras comprados hoje.
create or replace function public.on_train_max(c public.on_clubs,p_today date) returns int
language sql stable set search_path=public as $$
 select (select train_sessions from public.on_config)+case when c.train_day=p_today then c.train_extra else 0 end
$$;

create or replace function public.on_train_start(p_game text,p_players text[]) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;v_today date;v_id bigint;v_seed text:=md5(gen_random_uuid()::text);
begin
 select * into cfg from public.on_config;
 if p_game not in('reaction','passing','aim','timing','tackle','dribble','penalty') then raise exception 'Treino inválido';end if;
 if coalesce(cardinality(p_players),0) not between 1 and 11 or cardinality(p_players)<>(select count(distinct x) from unnest(p_players) x) then
  raise exception 'Escolha de 1 a 11 jogadores';
 end if;
 if p_game='penalty' and cardinality(p_players)<>1 then raise exception 'O treino de pênaltis é individual';end if;
 select (now() at time zone tz)::date into v_today from public.on_seasons where id=c.season_id;
 if c.train_day is distinct from v_today then c.train_used:=0;c.train_extra:=0;end if;
 if c.train_used>=cfg.train_sessions+c.train_extra then raise exception 'Limite de % treinos por dia atingido',cfg.train_sessions+c.train_extra;end if;
 if exists(select 1 from unnest(p_players) x where not exists(select 1 from public.on_players p where p.id=x and p.club_id=c.id
   and (p.inj_until is null or p.inj_until<=v_today) and p.cond>=30)) then
  raise exception 'Só treinam jogadores do elenco, sem lesão e com pelo menos 30%% de condição';
 end if;
 if exists(select 1 from unnest(p_players) x where public.on_in_live(x)) then raise exception 'Quem está jogando agora não treina';end if;
 update public.on_clubs set train_day=v_today,train_used=c.train_used+1,train_extra=c.train_extra where id=c.id;
 update public.on_players set cond=greatest(0,cond-cfg.train_cond) where id=any(p_players);
 insert into public.on_train(club_id,game,players,seed) values(c.id,p_game,p_players,v_seed) returning id into v_id;
 return jsonb_build_object('session',v_id,'game',p_game,'seed',v_seed,'started_at',now());
end $$;

-- Compra um treino extra para hoje com moedas da conta.
-- Sem prefixo on_: o app trata como escrita e atualiza o saldo de moedas nas outras telas.
create or replace function public.online_train_energy_buy() returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;k public.careers;v_today date;
begin
 select * into cfg from public.on_config;
 select (now() at time zone tz)::date into v_today from public.on_seasons where id=c.season_id;
 if c.train_day is distinct from v_today then c.train_used:=0;c.train_extra:=0;end if;
 if c.train_extra>=cfg.train_energy_max then raise exception 'Limite de % treinos extras por dia',cfg.train_energy_max;end if;
 select x.* into k from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1 for update;
 if k.id is null or k.coins<cfg.train_energy_cost then raise exception 'Moedas insuficientes';end if;
 update public.careers set coins=coins-cfg.train_energy_cost where id=k.id;
 update public.on_clubs set train_day=v_today,train_used=c.train_used,train_extra=c.train_extra+1 where id=c.id;
 return public.on_club();
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Leituras: nacionalidade nas cartas e treinos extras. As funções das fases anteriores recebem o trecho novo
-- por troca de texto conferida (uma ocorrência; se já foi trocado, não faz nada).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_patch(p_fn regprocedure,p_from text,p_to text) returns void
language plpgsql set search_path=public as $$
declare v text:=pg_get_functiondef(p_fn);c int;
begin
 if strpos(v,p_to)>0 then return;end if;
 c:=(length(v)-length(replace(v,p_from,'')))/length(p_from);
 if c<>1 then raise exception '%: "%" aparece % vez(es), esperado 1',p_fn,p_from,c;end if;
 execute replace(v,p_from,p_to);
end $$;

do $$ begin
 perform public.on_patch('public.on_squad()','''value'',public.on_value(p.ovr,p.age,p.pot),''card''',
  '''value'',public.on_value(p.ovr,p.age,p.pot),''nat'',p.nat,''sell'',round(public.on_value(p.ovr,p.age,p.pot)*.6),''card''');
 perform public.on_patch('public.on_lot_json(public.on_lots,int)','''number'',p.number,''card''','''number'',p.number,''nat'',p.nat,''card''');
 perform public.on_patch('public.on_club()','''max'',cfg.train_sessions,''cond_cost'',cfg.train_cond)',
  '''max'',public.on_train_max(c,v_today),''cond_cost'',cfg.train_cond,''extra'',case when c.train_day=v_today then c.train_extra else 0 end,''extra_max'',cfg.train_energy_max,''extra_cost'',cfg.train_energy_cost)');
 perform public.on_patch('public.on_status()','''max'',cfg.train_sessions)','''max'',public.on_train_max(c,v_today))');
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Permissões
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on function public.on_real_pick(text,numeric,numeric,text),public.on_real_insert(text,int,int,int,boolean,int,int),
 public.on_gen_squad(int,text,int,int),public.on_star_add(int,text,int,int,numeric,numeric,int,int),public.on_draft_prepare(int),
 public.on_season_bootstrap(uuid[],date,text,interval,timestamptz,bigint),public.on_gen_featured(text,int),
 public.on_bid_as(int,bigint,bigint,timestamptz),public.on_train_group(text),public.on_train_max(public.on_clubs,date),
 public.on_patch(regprocedure,text,text)
 from public,anon,authenticated;
-- técnico não leiloa mais jogador do próprio elenco
revoke all on function public.on_lot_create(text,bigint),public.on_lot_cancel(bigint) from public,anon,authenticated;
revoke all on function public.on_sell(text),public.online_train_energy_buy(),public.on_draft_read(),public.on_draft_pick(int,int),
 public.on_train_start(text,text[]),public.on_squad(),public.on_club(),public.on_status() from public,anon;
grant execute on function public.on_sell(text),public.online_train_energy_buy(),public.on_draft_read(),public.on_draft_pick(int,int),
 public.on_train_start(text,text[]),public.on_squad(),public.on_club(),public.on_status() to authenticated;

insert into supabase_migrations.schema_migrations(version,name) values('20261112120000','online_phase7_real_players')
on conflict do nothing;
commit;
