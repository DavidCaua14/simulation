-- MODO ONLINE — Fase 44: reinício dos clubes dos técnicos e cartas com tipo fixo.
--  1. Tipo da carta gravado em on_players.tier (base < destaque < epica < bigtime). Nunca muda com a nota: uma carta base
--     treinada até 84 continua base. As antigas lendas passam a ser cartas Épicas.
--  2. Teto de overall por tipo: base 84, destaque 94, épica 104; Big Time passa de 105 (regras da fase 42).
--  3. Mercado por série: Séries C e D só contratam cartas base, a Série B contrata base e destaque, só a Série A contrata
--     épicas. Vale para técnicos e bots; o mercado mostra o motivo no leilão bloqueado.
--  4. Clube novo (e o reinício): elenco base real no nível da Série D, sem o rascunho dos três craques, e $ 1 milhão.
--  5. on_restart_club: transfere o caixa do clube Online para o clube do técnico no modo Temporadas, apaga o elenco
--     (cartas tiradas na caixa da loja ficam: foram pagas com diamantes) e dá o elenco novo com $ 1 milhão.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1–2. Tipo fixo e teto por tipo
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_tier_of(p_tier text,p_legend boolean,p_star boolean) returns text
language sql immutable as $$
 select case when p_tier in('bigtime','epica','destaque','base') then p_tier
  when coalesce(p_legend,false) then 'epica' when coalesce(p_star,false) then 'destaque' else 'base' end $$;

create or replace function public.on_tier_cap(p_tier text) returns int
language sql immutable as $$
 select case p_tier when 'base' then 84 when 'destaque' then 94 when 'epica' then 104 end $$;

create or replace function public.on_players_tier() returns trigger
language plpgsql as $$
declare cap int;
begin
 new.tier:=public.on_tier_of(new.tier,new.legend,new.star);
 cap:=public.on_tier_cap(new.tier);
 if cap is not null then
  new.pot:=least(new.pot,cap);new.level:=least(new.level,cap);new.ovr:=least(new.ovr,cap);
 end if;
 return new;
end $$;

drop trigger if exists on_players_tier on public.on_players;
create trigger on_players_tier before insert or update on public.on_players
 for each row execute function public.on_players_tier();

-- Cartas que já existem: grava o tipo e aplica o teto (o gatilho faz o corte).
update public.on_players set tier=public.on_tier_of(tier,legend,star)
 where tier is distinct from public.on_tier_of(tier,legend,star)
  or ovr>coalesce(public.on_tier_cap(public.on_tier_of(tier,legend,star)),999)
  or pot>coalesce(public.on_tier_cap(public.on_tier_of(tier,legend,star)),999);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Mercado por série
-- ─────────────────────────────────────────────────────────────────────────────
-- Motivo do bloqueio (null = pode contratar). Clube sem série (só copa) contrata tudo.
create or replace function public.on_tier_lock(p_div text,p_tier text) returns text
language sql immutable as $$
 select case
  when p_tier='bigtime' then 'Cartas Big Time só saem nas caixas da Loja'
  when p_div in('C','D') and p_tier<>'base' then 'Na Série '||p_div||' só cartas base. Destaque libera na Série B e Épica na Série A.'
  when p_div='B' and p_tier='epica' then 'Cartas Épicas só para clubes da Série A'
 end $$;

do $$ begin
 perform public.on_patch('public.on_bid_as(integer,bigint,bigint,timestamp with time zone)',
  ' if p_amount is null or p_amount<public.on_min_bid(l) then',
  ' if public.on_tier_lock((select b.div from public.on_clubs b where b.id=p_club),
   (select public.on_tier_of(o.tier,o.legend,o.star) from public.on_players o where o.id=l.player_id)) is not null then
  raise exception ''%'',public.on_tier_lock((select b.div from public.on_clubs b where b.id=p_club),
   (select public.on_tier_of(o.tier,o.legend,o.star) from public.on_players o where o.id=l.player_id));
 end if;
 if p_amount is null or p_amount<public.on_min_bid(l) then');
 perform public.on_patch('public.on_bot_limit(integer,bigint,text)',
  '  when c.debt>0 or c.user_id is not null then 0',
  '  when c.debt>0 or c.user_id is not null then 0
  when public.on_tier_lock(c.div,public.on_tier_of(p.tier,p.legend,p.star)) is not null then 0 -- regra da série');
 perform public.on_patch('public.on_bot_limit(integer,bigint,text)',
  '   case when p.level>=81 then',
  '   case when public.on_tier_of(p.tier,p.legend,p.star)<>''base'' then');
 perform public.on_patch('public.on_lot_json(on_lots,integer)',
  '  ''owned'',',
  '  ''locked'',public.on_tier_lock((select k.div from public.on_clubs k where k.id=p_me),public.on_tier_of(p.tier,p.legend,p.star)),
  ''owned'',');
 perform public.on_patch('public.on_lot_json(on_lots,integer)',
  '''legend'',p.legend,''card''',
  '''legend'',p.legend,''tier'',public.on_tier_of(p.tier,p.legend,p.star),''card''');
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Clube novo: elenco base real da Série D e $ 1 milhão
-- ─────────────────────────────────────────────────────────────────────────────
-- Todo clube que passa a um técnico (entrada na hora, fila da virada, criação da temporada) gera o elenco com
-- on_gen_squad e depois chama on_draft_prepare. Com draft_on desligado: o elenco do técnico sai no nível da Série D,
-- on_draft_prepare não oferece craques, encerra o rascunho, põe o caixa inicial e escala o time.
alter table public.on_config add column if not exists start_cash bigint not null default 1000000;
alter table public.on_config add column if not exists draft_on boolean not null default false;

do $$ begin
 perform public.on_patch('public.on_gen_squad(integer,text,integer,integer)',
  'begin
 for r in select',
  'begin
 if not (select draft_on from public.on_config) and exists(select 1 from public.on_clubs k where k.id=p_club and k.user_id is not null) then
  p_base:=coalesce((select (series_level->>''D'')::int from public.on_config),56)+3; -- fase 44: técnico começa na Série D
 end if;
 for r in select');
 perform public.on_patch('public.on_draft_prepare(integer)',
  ' select * into c from public.on_clubs where id=p_club for update;',
  ' select * into c from public.on_clubs where id=p_club for update;
 if not (select draft_on from public.on_config) then -- fase 44: sem rascunho de craques
  if c.draft_step<3 then
   update public.on_clubs set draft_step=3,cash=(select start_cash from public.on_config),debt=0,reserved=0 where id=p_club;
   perform public.on_auto_lineup(p_club);
  end if;
  return;
 end if;');
 perform public.on_patch('public.on_take_seat(integer,uuid,text)',
  'Escolha seus três craques e prepare o time para o próximo jogo.',
  'Seu elenco é de cartas base da Série D. Use o caixa no mercado e suba de série para contratar cartas Destaque e Épicas.');
 if strpos(pg_get_functiondef('public.on_season_end(smallint,timestamp with time zone)'::regprocedure),'Escolha seus três craques para começar.')>0 then
  perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',
   'Escolha seus três craques para começar.','Seu elenco é de cartas base da Série D.');
 end if;
 perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',
  '  perform public.on_gen_squad(v_seat,v_seed||'':''||v_seat,62,v_new+1);',
  '  perform public.on_gen_squad(v_seat,v_seed||'':''||v_seat,62,v_new+1);
  perform public.on_draft_prepare(v_seat); -- fase 44: caixa inicial e escalação (sem rascunho)');
end $$;

-- Elenco base real no nível da Série D (19 jogadores do catálogo em volta da média dos bots da série).
create or replace function public.on_user_squad(p_club int,p_seed text) returns void
language plpgsql security definer set search_path=public as $$
declare k public.on_clubs;
begin
 select * into k from public.on_clubs where id=p_club;
 perform public.on_gen_squad(p_club,p_seed,coalesce((select (series_level->>'D')::int from public.on_config),56)+3,k.season_id+1);
 update public.on_players p set number=x.rn from(select id,row_number() over(order by (pos='GOL') desc,ovr desc,id) rn from public.on_players where club_id=p_club) x
  where p.id=x.id;
 perform public.on_auto_lineup(p_club);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Reinício de um clube de técnico
-- ─────────────────────────────────────────────────────────────────────────────
-- O caixa do Online (descontada a dívida) vai para o clube do técnico no modo Temporadas (lá o valor é em milhares).
create or replace function public.on_restart_club(p_club int,p_seed text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare k public.on_clubs;v_car uuid;v_cw text;v_amount bigint;v_sent bigint:=0;v_kept int;
begin
 select * into k from public.on_clubs where id=p_club for update;
 if k.id is null or k.user_id is null then raise exception 'Clube % não é de um técnico',p_club;end if;
 v_amount:=greatest(0,k.cash-k.debt);
 if v_amount>=1000 and to_regclass('public.mgr_coach') is not null and to_regclass('public.cw_clubs') is not null then
  execute 'select m.career_id,m.club_id from public.mgr_coach m join public.careers c on c.id=m.career_id
    where c.user_id=$1 and m.status=''employed'' order by (c.status=''active'') desc,c.created_at desc limit 1'
   into v_car,v_cw using k.user_id;
  if v_car is not null and exists(select 1 from public.cw_clubs w where w.career_id=v_car and w.club_id=v_cw) then
   v_sent:=round(v_amount/1000.0);
   execute 'select public.cw_cash($1,$2,$3,''online_transfer'',$4,''Caixa do clube Online transferido pelo técnico'',false,$5)'
    using v_car,v_cw,v_sent,'online-restart:'||k.id||':'||k.season_id,jsonb_build_object('online_club',k.id,'online_cash',v_amount);
  end if;
 end if;
 -- elenco: some tudo, menos as cartas tiradas na caixa da Loja (e Big Time)
 update public.on_lots set status='cancelled',settled_at=now() where status='open'
  and (player_id in(select id from public.on_players where club_id=p_club) or seller=p_club);
 update public.on_clubs b set reserved=greatest(0,b.reserved-x.s) from(select best_club,sum(best_bid) s from public.on_lots
  where status='open' and best_club=p_club group by 1) x where b.id=x.best_club;
 update public.on_lots set best_club=null,best_bid=null where status='open' and best_club=p_club;
 create temp table if not exists on_keep(id text primary key) on commit drop;
 delete from on_keep;
 insert into on_keep select p.id from public.on_players p where p.club_id=p_club
  and (p.tier='bigtime' or p.id in(select d.player_id from public.on_pack_draws d where d.club_id=p_club and d.player_id is not null));
 get diagnostics v_kept=row_count;
 delete from public.on_lots where status<>'open' and player_id in(select id from public.on_players where club_id=p_club and id not in(select id from on_keep));
 delete from public.on_players where club_id=p_club and id not in(select id from on_keep) and id not in(select player_id from public.on_lots);
 update public.on_players set club_id=null where club_id=p_club and id not in(select id from on_keep);
 delete from public.on_players where hold=p_club and club_id is null and id not in(select player_id from public.on_lots);
 delete from public.on_lineups where club_id=p_club;
 update public.on_clubs set cash=(select start_cash from public.on_config),debt=0,reserved=0,draft_step=3 where id=p_club;
 perform public.on_user_squad(p_club,p_seed||':restart:'||p_club);
 insert into public.on_news(club_id,kind,text) values(p_club,'season',
  'O Online recomeçou: elenco novo de cartas base da Série D e $ 1 milhão no caixa'
  ||case when v_sent>0 then '. O caixa antigo foi para o seu clube no modo Temporadas.' else '.' end);
 return jsonb_build_object('club',p_club,'online_cash',v_amount,'sent_thousands',v_sent,'kept',v_kept,
  'players',(select count(*) from public.on_players where club_id=p_club));
end $$;

revoke all on function public.on_restart_club(int,text) from public, anon, authenticated;
revoke all on function public.on_user_squad(int,text) from public, anon, authenticated;
