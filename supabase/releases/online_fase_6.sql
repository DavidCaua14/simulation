-- Pacote de publicação do modo online, fase 6 (gerado de supabase/online/06_experience.sql).
-- Rodar inteiro no SQL Editor ou pela API, como administrador. Tudo ou nada.
-- Depois, para voltar à escolha dos craques: supabase/releases/online_reiniciar.sql.
begin;

-- ===== supabase/online/06_experience.sql =====
-- MODO ONLINE — Fase 6: experiência de clube.
--
--  • Calendário: jogos só de manhã e à tarde (09:00, 10:00, 11:00, 14:00, 15:30 e 17:00).
--  • Leilões em destaque: sempre 3 jogadores do sistema em disputa, os mesmos para todos. Cada um fica até a
--    virada da hora; sem lances, sai e entra outro. Com lances, cada lance novo garante mais 5 minutos, então a
--    disputa pode durar horas (teto em lot_extend_max). O maior lance vence.
--  • Resultado do leilão: todo técnico que deu lance recebe um aviso com quem venceu (tela inicial do modo).
--  • Moedas: investir no clube (coin_rate por moeda) ou cobrir um lance direto com moedas, que rende menos
--    (coin_bid_rate por moeda).
--  • Identidade do clube: nome, sigla, cores, desenho do escudo e estádio (tudo em on_clubs.colors).
--  • Carta do jogador: seis atributos visíveis, calculados dos mesmos atributos que o motor usa (on_comp).
--  • Treino: seis mini-games; individual rende mais, coletivo (até 11) rende menos por jogador.
--
-- Nenhuma função mgr_* ou cw_* é alterada.

-- ─────────────────────────────────────────────────────────────────────────────
-- Configuração e colunas
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.on_config add column if not exists featured_count smallint not null default 3;
alter table public.on_config add column if not exists featured_minutes int not null default 60;
alter table public.on_config add column if not exists bid_extend interval not null default interval '5 minutes';
alter table public.on_config add column if not exists coin_bid_rate int not null default 600;
alter table public.on_config alter column lot_extend_max set default interval '6 hours';
alter table public.on_config alter column user_lot_minutes set default 60;
alter table public.on_config alter column coin_cap set default 1000;
update public.on_config set lot_extend_max=interval '6 hours',user_lot_minutes=60,coin_cap=1000 where coin_cap=300;

alter table public.on_seasons alter column slots set default array['09:00','10:00','11:00','14:00','15:30','17:00']::time[];

alter table public.on_lots add column if not exists featured smallint not null default 0; -- 1 a 3: faixa do destaque
alter table public.on_news add column if not exists data jsonb;
alter table public.on_news add column if not exists seen_at timestamptz;
create index if not exists on_bids_club on public.on_bids(club_id,lot_id);

alter table public.on_train drop constraint if exists on_train_game_check;
alter table public.on_train add constraint on_train_game_check check (game in('reaction','passing','aim','timing','tackle','dribble'));

-- ─────────────────────────────────────────────────────────────────────────────
-- Carta do jogador: seis atributos de 20 a 99
-- Linha: pac velocidade, sho finalização, pas passe, dri controle, def defesa, phy físico.
-- Goleiro (mesmas chaves): pac elasticidade, sho mãos, pas reposição, dri reflexo, def velocidade, phy posição.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_card(p_id text,p_pos text,p_level numeric,p_g smallint[]) returns jsonb
language sql immutable set search_path=public as $$
 select jsonb_object_agg(x.k,greatest(20,least(99,round(x.v)))::int)
 from(select public.on_comp(p_id,p_pos,p_level,p_g) c) q
 cross join lateral(
  select * from(values('pac',c[8]),('sho',c[6]),('pas',c[2]),('dri',c[4]),('def',(c[3]+c[10])/2),('phy',(c[11]+c[9])/2)) o(k,v) where p_pos<>'GOL'
  union all
  select * from(values('pac',c[5]+(public.sim_hash01(p_id||':k1')-.5)*6),('sho',c[5]+(public.sim_hash01(p_id||':k2')-.5)*6),('pas',c[2]+22),
   ('dri',c[5]+(public.sim_hash01(p_id||':k3')-.5)*6),('def',c[8]+18),('phy',c[5]+(public.sim_hash01(p_id||':k4')-.5)*6)) g(k,v) where p_pos='GOL') x
$$;

-- Identificador do craque oferecido na escolha: o mesmo na leitura e na contratação (a carta mostrada é a real).
create or replace function public.on_star_id(p_seed text,p_step int,p_i int) returns text
language sql immutable as $$ select 's'||left(md5(p_seed||':id:'||p_step||':'||p_i),12) $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Criação da temporada: clubes de bot com estádio e escudo próprios; calendário pela função da Fase 5.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_season_bootstrap(p_users uuid[],p_start date,p_kind text default 'main',
 p_gap interval default null,p_now timestamptz default now(),p_cash bigint default 150000) returns smallint
language plpgsql security definer set search_path=public as $$
declare v_s smallint;v_seed text:=md5(gen_random_uuid()::text);r record;n int:=coalesce(cardinality(p_users),0);
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

 -- 12 clubes em assentos sorteados: usuários primeiro, bots completam.
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

 -- Elencos: 19 genéricos por clube; bots já recebem os 3 craques (um pouco abaixo dos craques dos usuários).
 for r in select c.id,c.user_id from public.on_clubs c where c.season_id=v_s order by c.id loop
  perform public.on_gen_squad(r.id,v_seed||':'||r.id,
   case when r.user_id is null then 60+floor(public.sim_hash01(v_seed||':base:'||r.id)*5)::int else 62 end,v_s+1);
  if r.user_id is null then
   insert into public.on_players(club_id,name,pos,age,level,pot,ovr,number,wage,contract_end,star)
   select r.id,st.name,st.pos,st.age,st.level-2,st.pot,st.level-2,21+k.step,public.on_wage(st.level-2),v_s+1,true
   from generate_series(0,2) k(step)
   cross join lateral public.on_star(v_seed||':'||r.id,k.step,1+floor(public.sim_hash01(v_seed||':botpick:'||r.id||':'||k.step)*3)::int) st;
   perform public.on_auto_lineup(r.id);
  end if;
 end loop;

 perform public.on_league_fixtures(v_s,p_start,p_gap,p_now);
 insert into public.on_table(season_id,club_id) select v_s,c.id from public.on_clubs c where c.season_id=v_s;
 return v_s;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Escolha dos craques com a carta completa
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_draft_read() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();v_seed text;
begin
 select s.seed||':'||c.id into v_seed from public.on_seasons s where s.id=c.season_id;
 return jsonb_build_object('step',c.draft_step,'done',c.draft_step>=3,
  'line',(array['DEF','MID','ATT'])[c.draft_step+1],
  'club',jsonb_build_object('id',c.id,'name',c.name,'short',c.short,'colors',c.colors),
  'options',case when c.draft_step>=3 then '[]'::jsonb else(select jsonb_agg(jsonb_build_object('idx',i.i,'name',st.name,'pos',st.pos,
    'age',st.age,'ovr',st.level,'pot',st.pot,'value',public.on_value(st.level,st.age,st.pot),'wage',public.on_wage(st.level),
    'card',public.on_card(public.on_star_id(v_seed,c.draft_step,i.i),st.pos,st.level,'{0,0,0,0}')) order by i.i)
   from generate_series(1,3) i(i) cross join lateral public.on_star(v_seed,c.draft_step,i.i) st) end,
  'picked',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'age',p.age,'ovr',p.ovr,'pot',p.pot,
    'card',public.on_card(p.id,p.pos,p.level,p.g)) order by p.number)
   from public.on_players p where p.club_id=c.id and p.star),'[]'::jsonb));
end $$;

create or replace function public.on_draft_pick(p_step int,p_idx int) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);v_seed text;
begin
 if p_idx is null or p_idx not between 1 and 3 then raise exception 'Opção inválida';end if;
 if c.draft_step=p_step and c.draft_step<3 then
  select s.seed||':'||c.id into v_seed from public.on_seasons s where s.id=c.season_id;
  insert into public.on_players(id,club_id,name,pos,age,level,pot,ovr,number,wage,contract_end,star)
  select public.on_star_id(v_seed,c.draft_step,p_idx),c.id,st.name,st.pos,st.age,st.level,st.pot,st.level,21+c.draft_step,public.on_wage(st.level),c.season_id+2,true
  from public.on_star(v_seed,c.draft_step,p_idx) st;
  update public.on_clubs set draft_step=draft_step+1 where id=c.id;
  if c.draft_step=2 then perform public.on_auto_lineup(c.id);end if;
 end if;
 return public.on_draft_read();
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Identidade do clube
-- ─────────────────────────────────────────────────────────────────────────────
-- p: {name, short, a, b, pattern, shape, stadium}. Só as chaves enviadas mudam.
create or replace function public.on_club_identity(p jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);v_name text;v_short text;v_col jsonb;v text;
begin
 v_name:=c.name;v_short:=c.short;v_col:=c.colors;
 if p ? 'name' then
  v_name:=btrim(regexp_replace(coalesce(p->>'name',''),'\s+',' ','g'));
  if char_length(v_name) not between 3 and 24 then raise exception 'O nome do clube precisa ter de 3 a 24 caracteres';end if;
  if exists(select 1 from public.on_clubs k where k.season_id=c.season_id and k.id<>c.id and lower(k.name)=lower(v_name)) then
   raise exception 'Já existe um clube com esse nome';
  end if;
 end if;
 if p ? 'short' then
  v_short:=upper(regexp_replace(coalesce(p->>'short',''),'[^A-Za-z0-9]','','g'));
  if char_length(v_short) not between 2 and 4 then raise exception 'A sigla precisa ter de 2 a 4 letras ou números';end if;
 end if;
 foreach v in array array['a','b'] loop
  if p ? v then
   if coalesce(p->>v,'') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Cor inválida';end if;
   v_col:=v_col||jsonb_build_object(v,lower(p->>v));
  end if;
 end loop;
 if p ? 'pattern' then
  if p->>'pattern' not in('stripes','hoops','plain','sash','halves','chevron') then raise exception 'Desenho inválido';end if;
  v_col:=v_col||jsonb_build_object('pattern',p->>'pattern');
 end if;
 if p ? 'shape' then
  if p->>'shape' not in('shield','round','diamond') then raise exception 'Formato inválido';end if;
  v_col:=v_col||jsonb_build_object('shape',p->>'shape');
 end if;
 if p ? 'stadium' then
  v:=btrim(regexp_replace(coalesce(p->>'stadium',''),'\s+',' ','g'));
  if char_length(v) not between 3 and 28 then raise exception 'O nome do estádio precisa ter de 3 a 28 caracteres';end if;
  v_col:=v_col||jsonb_build_object('stadium',v);
 end if;
 update public.on_clubs set name=v_name,short=v_short,colors=v_col where id=c.id;
 return public.on_status();
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Mercado: leilões em destaque
-- ─────────────────────────────────────────────────────────────────────────────

-- Jogador do sistema para o destaque. Faixa 1: 77 a 85 de nota; 2: 70 a 77; 3: 62 a 70.
create or replace function public.on_gen_featured(p_seed text,p_tier int) returns text
language sql security definer set search_path=public as $$
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end,agg,disc,star)
 select null,public.cw_regen_name('BRA',p_seed),(array['GOL','LD','ZAG','ZAG','LE','VOL','MC','MEI','PD','PE','ATA','ATA'])[1+floor(public.sim_hash01(p_seed||':p')*12)::int],
  a.age,a.lvl,least(94,a.lvl+floor(public.sim_hash01(p_seed||':pot')*case when a.age<23 then 12 else 5 end)::int),a.lvl,public.on_wage(a.lvl),
  (select max(id) from public.on_seasons)+1+floor(public.sim_hash01(p_seed||':ct')*2)::int,
  35+floor(public.sim_hash01(p_seed||':agg')*40)::int,40+floor(public.sim_hash01(p_seed||':disc')*45)::int,a.lvl>=80
 from(select 18+floor(public.sim_hash01(p_seed||':age')*15)::int age,
  case p_tier when 1 then 77+floor(public.sim_hash01(p_seed||':lvl')*9)::int
   when 2 then 70+floor(public.sim_hash01(p_seed||':lvl')*8)::int
   else 62+floor(public.sim_hash01(p_seed||':lvl')*9)::int end lvl) a
 returning id
$$;

-- Lance de um clube. Cada lance garante pelo menos bid_extend até o fim (até o teto do lote).
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
  ends_at=least(hard_end,greatest(ends_at,p_now+(select bid_extend from public.on_config))) where id=l.id;
 insert into public.on_bids(lot_id,club_id,amount,at) values(l.id,p_club,p_amount,p_now);
end $$;

-- Fecha um lote vencido. Vendido: todo técnico que deu lance recebe o resultado (quem venceu e por quanto).
-- Destaque sem lances: o jogador sai do mercado e outro entra no lugar.
create or replace function public.on_lot_settle(p_lot bigint,p_now timestamptz default now()) returns text
language plpgsql security definer set search_path=public as $$
declare l public.on_lots;p public.on_players;v_buyer int;v_price bigint;v_in text[];v_value bigint;w public.on_clubs;
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
  if l.seller is not null then
   insert into public.on_news(club_id,kind,text) values(l.seller,'market',format('%s não recebeu lances e continua no elenco.',p.name));
  elsif p.club_id is null then
   delete from public.on_players where id=p.id; -- leva o lote junto (on delete cascade)
  end if;
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
 -- resultado para o vencedor e para todos os técnicos que disputaram
 select * into w from public.on_clubs where id=v_buyer;
 insert into public.on_news(club_id,kind,text,data)
 select k.id,'auction',
  case when k.id=v_buyer then format('%s é seu! Leilão vencido por $ %s.',p.name,v_price)
   else format('%s venceu o leilão de %s por $ %s.',w.name,p.name,v_price) end,
  jsonb_build_object('lot',l.id,'won',k.id=v_buyer,'price',v_price,
   'player',jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'ovr',p.ovr,'age',p.age,'star',p.star),
   'winner',jsonb_build_object('id',w.id,'name',w.name,'short',w.short,'colors',w.colors))
 from public.on_clubs k
 where k.user_id is not null and (k.id=v_buyer or k.id in(select b.club_id from public.on_bids b where b.lot_id=l.id));
 if l.seller is not null then
  v_in:=public.on_lineup_repair(l.seller);
  insert into public.on_news(club_id,kind,text) values(l.seller,'market',format('%s foi vendido por $ %s.%s',p.name,v_price,
   case when cardinality(v_in)>0 then ' '||array_to_string(v_in,', ')||' entrou na vaga dele.' else '' end));
 end if;
 return 'sold';
end $$;

-- Gancho do cron: mantém os destaques, lances dos bots e fechamento dos lotes vencidos.
create or replace function public.on_market_tick(p_now timestamptz,p_new_day boolean) returns void
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;cfg public.on_config;r record;t int;pid text;k int;v_bid bigint;v_end timestamptz;
begin
 select * into s from public.on_seasons where status='live';
 if s.id is null then return;end if;
 select * into cfg from public.on_config;
 -- fechamento primeiro: a vaga do destaque que acabou é preenchida no mesmo minuto
 for r in select l.id from public.on_lots l where l.season_id=s.id and l.status='open' and l.ends_at<=p_now order by l.ends_at limit 10 loop
  perform public.on_lot_settle(r.id,p_now);
 end loop;
 -- destaques: um por faixa, das 08:00 às 22:59 (horário da temporada); cada um fica até a virada da hora
 if extract(hour from p_now at time zone s.tz) between 8 and 22 then
  for t in 1..cfg.featured_count loop
   continue when exists(select 1 from public.on_lots x where x.season_id=s.id and x.status='open' and x.featured=t);
   pid:=public.on_gen_featured(s.seed||':f:'||t||':'||floor(extract(epoch from p_now))::bigint,t);
   v_end:=case when cfg.featured_minutes=60 then date_trunc('hour',p_now+interval '15 minutes')+interval '1 hour'
    else p_now+cfg.featured_minutes*interval '1 minute' end;
   insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
   select s.id,pid,greatest(500,round(public.on_value(p.ovr,p.age,p.pot)*.4))::bigint,p_now,v_end,v_end+cfg.lot_extend_max,t
   from public.on_players p where p.id=pid;
  end loop;
 end if;
 -- bots: entram na disputa só quando um técnico já deu lance, nos últimos 3 minutos, até 70% a 90% do valor
 for r in select l.*,public.on_value(p.ovr,p.age,p.pot) v from public.on_lots l join public.on_players p on p.id=l.player_id
  where l.season_id=s.id and l.status='open' and l.opens_at<=p_now and l.ends_at>p_now and l.ends_at<=p_now+interval '3 minutes'
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

create or replace function public.on_lot_json(l public.on_lots,p_me int) returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('id',l.id,'status',l.status,'opens_at',l.opens_at,'ends_at',l.ends_at,'start_price',l.start_price,
  'best_bid',l.best_bid,'bids',l.bids,'min_bid',public.on_min_bid(l),'mine',l.seller=p_me,'leading',l.best_club=p_me,'featured',l.featured,
  'bidding',exists(select 1 from public.on_bids x where x.lot_id=l.id and x.club_id=p_me),
  'bidders',(select count(distinct x.club_id) from public.on_bids x where x.lot_id=l.id),
  'history',coalesce((select jsonb_agg(jsonb_build_object('club',jsonb_build_object('id',k.id,'short',k.short,'name',k.name,'colors',k.colors),
     'amount',x.amount,'at',x.at,'me',x.club_id=p_me) order by x.id desc)
   from(select * from public.on_bids y where y.lot_id=l.id order by y.id desc limit 4) x join public.on_clubs k on k.id=x.club_id),'[]'::jsonb),
  'player',jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'sec',p.sec,'age',p.age,'ovr',p.ovr,'pot',p.pot,'star',p.star,'cond',p.cond,
   'wage',p.wage,'value',public.on_value(p.ovr,p.age,p.pot),'number',p.number,'card',public.on_card(p.id,p.pos,p.level,p.g)),
  'seller',case when s.id is null then null else jsonb_build_object('id',s.id,'name',s.name,'short',s.short,'colors',s.colors) end,
  'best_club',case when b.id is null then null else jsonb_build_object('id',b.id,'name',b.name,'short',b.short,'colors',b.colors) end)
 from public.on_players p left join public.on_clubs s on s.id=l.seller left join public.on_clubs b on b.id=l.best_club
 where p.id=l.player_id
$$;

-- Carteira de moedas do usuário (carreira ativa).
create or replace function public.on_wallet() returns int
language sql stable security definer set search_path=public as $$
 select x.coins from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1
$$;

create or replace function public.on_market() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();cfg public.on_config;
begin
 select * into cfg from public.on_config;
 return jsonb_build_object('server_now',now(),'my_club',c.id,
  'club',jsonb_build_object('cash',c.cash,'reserved',c.reserved,'debt',c.debt,'roster',(select count(*) from public.on_players where club_id=c.id)),
  'coins',jsonb_build_object('wallet',coalesce(public.on_wallet(),0),'rate',cfg.coin_rate,'bid_rate',cfg.coin_bid_rate,'converted',c.coins_conv,'cap',cfg.coin_cap),
  'lots',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.featured=0,l.featured,l.ends_at) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='open' and x.opens_at<=now()+interval '2 hours') l),'[]'::jsonb),
  'recent',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.settled_at desc) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='sold' order by x.settled_at desc limit 8) l),'[]'::jsonb));
end $$;

-- Lance do técnico. Com p_coins, o que faltar no caixa livre é coberto com moedas da conta (coin_bid_rate por
-- moeda, menos que investir no clube). As moedas viram caixa na hora e não voltam se o lance for coberto.
-- Trava o lote antes do clube (mesma ordem de on_bid_as).
drop function if exists public.on_bid(bigint,bigint);
create or replace function public.on_bid(p_lot bigint,p_amount bigint,p_coins boolean default false) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();l public.on_lots;cfg public.on_config;k public.careers;v_need bigint;v_coins int;
begin
 select * into l from public.on_lots where id=p_lot and season_id=c.season_id for update;
 if l.id is null then raise exception 'Leilão não encontrado';end if;
 if coalesce(p_coins,false) then
  select * into cfg from public.on_config;
  select * into c from public.on_clubs where id=c.id for update;
  v_need:=p_amount-case when l.best_club=c.id then l.best_bid else 0 end-(c.cash-c.reserved);
  if v_need>0 and c.debt=0 and l.status='open' and now()<l.ends_at and p_amount>=public.on_min_bid(l) then
   v_coins:=ceil(v_need::numeric/cfg.coin_bid_rate)::int;
   select x.* into k from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1 for update;
   if k.id is null or k.coins<v_coins then raise exception 'Moedas insuficientes: esse lance pede % moedas',v_coins;end if;
   update public.careers set coins=coins-v_coins where id=k.id;
   perform public.on_money(c.id,v_coins::bigint*cfg.coin_bid_rate,'coins',format('%s moedas em lance',v_coins));
  end if;
 end if;
 perform public.on_bid_as(c.id,p_lot,p_amount);
 return public.on_market();
end $$;

-- Marca avisos como vistos (resultado de leilão na tela inicial).
create or replace function public.on_news_seen(p_ids bigint[]) returns void
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();
begin
 update public.on_news set seen_at=now() where club_id=c.id and id=any(p_ids) and seen_at is null;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Treino: seis mini-games; individual, grupo ou coletivo
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_train_group(p_game text) returns int
language sql immutable as $$ select case p_game when 'reaction' then 1 when 'tackle' then 1 when 'passing' then 2 when 'aim' then 3 else 4 end $$;

-- Rendimento por jogador conforme o tamanho da sessão: 1 jogador 150%, 2 a 6 100%, 7 a 11 65%.
create or replace function public.on_train_scale(p_n int) returns numeric
language sql immutable as $$ select case when p_n<=1 then 1.5 when p_n<=6 then 1 else .65 end $$;

create or replace function public.on_train_start(p_game text,p_players text[]) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;v_today date;v_id bigint;v_seed text:=md5(gen_random_uuid()::text);
begin
 select * into cfg from public.on_config;
 if p_game not in('reaction','passing','aim','timing','tackle','dribble') then raise exception 'Treino inválido';end if;
 if coalesce(cardinality(p_players),0) not between 1 and 11 or cardinality(p_players)<>(select count(distinct x) from unnest(p_players) x) then
  raise exception 'Escolha de 1 a 11 jogadores';
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

create or replace function public.on_train_finish(p_session bigint,p_score numeric) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);t public.on_train;v numeric:=greatest(0,least(1,coalesce(p_score,0)));gi int;out jsonb;f numeric;
begin
 select * into t from public.on_train where id=p_session and club_id=c.id for update;
 if t.id is null then raise exception 'Treino não encontrado';end if;
 if t.finished_at is not null then raise exception 'Esse treino já terminou';end if;
 if now()-t.started_at<interval '8 seconds' then raise exception 'Treino curto demais';end if;
 if now()-t.started_at>interval '10 minutes' then v:=0;end if; -- sessão abandonada não rende
 gi:=public.on_train_group(t.game);
 f:=public.on_train_scale(cardinality(t.players));
 update public.on_train set finished_at=now(),score=v where id=t.id;
 with g as(
  select p.id,p.ovr before,round(public.on_train_gain(v,p.age,p.ovr,p.pot,(c.lv->>'training')::int)*f)::int gain
  from public.on_players p where p.id=any(t.players) and p.club_id=c.id),
 u as(update public.on_players p set
   g[gi]=p.g[gi]+(p.xp[gi]+g.gain)/100,
   xp[gi]=(p.xp[gi]+g.gain)%100,
   ovr=public.on_ovr(p.level,p.pot,(select array_agg(case when i=gi then p.g[i]+(p.xp[gi]+g.gain)/100 else p.g[i] end order by i) from generate_series(1,4) i)::smallint[])
  from g where p.id=g.id returning p.id,p.name,p.pos,p.ovr,g.gain,g.before,(p.xp[gi]) xp)
 select jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'pos',u.pos,'gain',u.gain,'ovr',u.ovr,'before',u.before,'xp',u.xp)) into out from u;
 return jsonb_build_object('score',v,'group',gi,'players',coalesce(out,'[]'::jsonb));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Leituras com o que as telas novas precisam
-- ─────────────────────────────────────────────────────────────────────────────

-- Elenco com a carta de cada jogador.
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
    'value',public.on_value(p.ovr,p.age,p.pot),'card',public.on_card(p.id,p.pos,p.level,p.g)) order by sp.sort,p.ovr desc,p.id)
   from public.on_players p join public.sim_positions sp on sp.code=p.pos where p.club_id=c.id),'[]'::jsonb),
  'lineup',(select jsonb_build_object('formation',l.formation,'slots',l.slots,'bench',l.bench,'tactics',l.tactics,'roles',l.roles)
   from public.on_lineups l where l.club_id=c.id));
end $$;

-- Situação do usuário e tudo que a tela inicial mostra: clube, próximo jogo, campanha, leilões em que ele
-- está, resultados de leilão ainda não vistos e avisos recentes.
create or replace function public.on_status() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_uid uuid:=auth.uid();s public.on_seasons;c public.on_clubs;a text;cfg public.on_config;v_today date;j jsonb;
begin
 if v_uid is null then raise exception 'Entre na sua conta para jogar';end if;
 if not public.on_gate() then
  return jsonb_build_object('server_now',now(),'access','unavailable','season',null,'club',null,'next',null);
 end if;
 select x.* into s from public.on_seasons x where x.status='live';
 select x.state into a from public.on_access x where x.user_id=v_uid;
 if s.id is not null then select k.* into c from public.on_clubs k where k.season_id=s.id and k.user_id=v_uid;end if;
 j:=jsonb_build_object('server_now',now(),
  'access',case when c.id is not null then 'playing' when a is not null then 'queued' else 'none' end,
  'season',case when s.id is null then null else jsonb_build_object('id',s.id,'kind',s.kind,'starts_on',s.starts_on) end,
  'club',null,'next',null);
 if c.id is null then return j;end if;
 select * into cfg from public.on_config;
 v_today:=(now() at time zone s.tz)::date;
 return j||jsonb_build_object(
  'club',jsonb_build_object('id',c.id,'name',c.name,'short',c.short,'colors',c.colors,
   'cash',c.cash,'reserved',c.reserved,'debt',c.debt,'draft_step',c.draft_step,'levels',c.lv,
   'roster',(select count(*) from public.on_players p where p.club_id=c.id),
   'strength',(select round(avg(x.ovr),1) from(select p.ovr from public.on_players p where p.club_id=c.id order by p.ovr desc limit 11) x)),
  'coins',coalesce(public.on_wallet(),0),
  'day',jsonb_build_object('n',greatest(1,v_today-s.starts_on+1),'of',26),
  'position',(select x.pos from public.on_rank(s.id) x where x.club_id=c.id),
  'standing',(select jsonb_build_object('p',t.p,'w',t.w,'d',t.d,'l',t.l,'gf',t.gf,'ga',t.ga,'pts',t.pts) from public.on_table t where t.season_id=s.id and t.club_id=c.id),
  'form',coalesce((select jsonb_agg(x.r order by x.kickoff) from(
    select f.kickoff,case when f.hg=f.ag then 'D' when (f.hg>f.ag)=(f.home=c.id) then 'W' else 'L' end r
    from public.on_fixtures f where f.season_id=s.id and f.status='done' and c.id in(f.home,f.away) order by f.kickoff desc limit 5) x),'[]'::jsonb),
  'next',(select jsonb_build_object('id',f.id,'comp',f.comp,'round',f.round,'stage',f.stage,'kickoff',f.kickoff,
    'status',f.status,'live',f.kickoff<=now(),'at_home',f.home=c.id,
    'opp',jsonb_build_object('id',o.id,'name',o.name,'short',o.short,'colors',o.colors,'bot',o.user_id is null,
     'position',(select x.pos from public.on_rank(s.id) x where x.club_id=o.id)))
   from public.on_fixtures f join public.on_clubs o on o.id=case when f.home=c.id then f.away else f.home end
   where f.season_id=s.id and f.status<>'done' and (f.home=c.id or f.away=c.id) order by f.kickoff limit 1),
  'rest_today',not exists(select 1 from public.on_fixtures f where f.season_id=s.id and c.id in(f.home,f.away) and (f.kickoff at time zone s.tz)::date=v_today)
   and exists(select 1 from public.on_fixtures f where f.season_id=s.id and (f.kickoff at time zone s.tz)::date=v_today),
  'last',(select jsonb_build_object('id',f.id,'hg',f.hg,'ag',f.ag,'at_home',f.home=c.id,'comp',f.comp,'round',f.round,
    'opp',jsonb_build_object('id',o.id,'name',o.name,'short',o.short,'colors',o.colors))
   from public.on_fixtures f join public.on_clubs o on o.id=case when f.home=c.id then f.away else f.home end
   where f.season_id=s.id and f.status='done' and (f.home=c.id or f.away=c.id) order by f.kickoff desc limit 1),
  'train',jsonb_build_object('used',case when c.train_day=v_today then c.train_used else 0 end,'max',cfg.train_sessions),
  'featured',(select jsonb_build_object('count',count(*),'ends_at',min(l.ends_at)) from public.on_lots l
   where l.season_id=s.id and l.status='open' and l.featured>0 and l.opens_at<=now()),
  'bids',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.ends_at) from(
    select * from public.on_lots x where x.season_id=s.id and x.status='open'
     and (x.seller=c.id or exists(select 1 from public.on_bids b where b.lot_id=x.id and b.club_id=c.id)) order by x.ends_at limit 6) l),'[]'::jsonb),
  'results',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'text',n.text,'data',n.data,'at',n.at) order by n.id desc) from(
    select * from public.on_news x where x.club_id=c.id and x.kind='auction' and x.seen_at is null order by x.id desc limit 5) n),'[]'::jsonb),
  'news',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'kind',n.kind,'text',n.text,'at',n.at) order by n.id desc) from(
    select * from public.on_news x where x.club_id=c.id and x.kind<>'auction' order by x.id desc limit 5) n),'[]'::jsonb));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Permissões
-- ─────────────────────────────────────────────────────────────────────────────
revoke all on function public.on_card(text,text,numeric,smallint[]),public.on_star_id(text,int,int),public.on_gen_featured(text,int),
 public.on_wallet(),public.on_train_scale(int),public.on_season_bootstrap(uuid[],date,text,interval,timestamptz,bigint),
 public.on_bid_as(int,bigint,bigint,timestamptz),public.on_lot_settle(bigint,timestamptz),public.on_market_tick(timestamptz,boolean),
 public.on_lot_json(public.on_lots,int),public.on_train_group(text)
 from public,anon,authenticated;
revoke all on function public.on_club_identity(jsonb),public.on_bid(bigint,bigint,boolean),public.on_news_seen(bigint[]),public.on_market(),
 public.on_draft_read(),public.on_draft_pick(int,int),public.on_train_start(text,text[]),public.on_train_finish(bigint,numeric),
 public.on_squad(),public.on_status() from public,anon;
grant execute on function public.on_club_identity(jsonb),public.on_bid(bigint,bigint,boolean),public.on_news_seen(bigint[]),public.on_market(),
 public.on_draft_read(),public.on_draft_pick(int,int),public.on_train_start(text,text[]),public.on_train_finish(bigint,numeric),
 public.on_squad(),public.on_status() to authenticated;

insert into supabase_migrations.schema_migrations(version,name) values('20261111120000','online_phase6_experience')
on conflict do nothing;
commit;
