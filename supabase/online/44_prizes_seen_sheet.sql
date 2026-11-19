-- MODO ONLINE — Fase 40: prêmios balanceados por série, título pago assim que a série termina, ficha dos jogadores do
-- mercado e "já vi" das comemorações guardado na conta (não no aparelho).
--
-- 1. PRÊMIOS DAS SÉRIES. Antes: a tabela de prêmios da liga vezes o peso da série (A 1, B 0,6, C 0,4, D 0,25) em tudo
--    (dinheiro, diamantes, XP e energia), sem nada pelo acesso nem pelo rebaixamento. Problemas: o campeão da D levava
--    75 diamantes (um quarto do da A) por um título tão difícil quanto; quem subia chegava à série de cima sem caixa para
--    reforçar o elenco (e caía de novo); quem caía perdia receita e salário pesado de uma vez.
--    Agora:
--     • dinheiro continua pelo peso da série (a economia de cada série é diferente: salários da A ~7x os da D);
--     • diamantes, XP e energia usam a raiz do peso (A 1, B 0,77, C 0,63, D 0,5): o título de qualquer série vale;
--     • bônus de acesso: 40% do prêmio de campeão da série para onde o clube sobe (D→C $ 800 mil, C→B $ 1,2 mi,
--       B→A $ 2 mi; o campeão da B leva o mesmo que o da A);
--     • ajuda de rebaixamento: um quarto do prêmio de campeão da série que o clube deixa (A→B $ 1,25 mi,
--       B→C $ 750 mil, C→D $ 500 mil).
-- 2. TÍTULO NA HORA. O prêmio (e a comemoração de campeão) de cada série sai quando a série termina, não só quando a
--    temporada inteira (com a copa) acaba. A copa já pagava na final.
-- 3. FICHA DO MERCADO. on_player_sheet passa a abrir jogador em leilão aberto (sem clube), para a tela de proposta.
-- 4. "JÁ VI" NA CONTA (ui_seen): comemoração de título e animação de nível aparecem uma vez por conta. Antes ficavam
--    no aparelho (localStorage): quem abria no PC e depois no celular via a festa de novo, como se recebesse outra vez.
--    Os prêmios em si sempre foram entregues uma vez só (resgate da caixa de entrada travado por carreira).

alter table public.on_config add column if not exists series_bonus jsonb not null default '{"promotion":0.4,"parachute":0.25}';
alter table public.on_seasons add column if not exists div_paid text[] not null default '{}';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Prêmio da liga de uma série
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_league_prize(p_div text,p_pos int,p_result text) returns jsonb
language sql stable security definer set search_path=public as $$
 with c as(select * from public.on_config),
 m as(select coalesce((c.series_mult->>p_div)::numeric,1) m,
   least(12,ceil(p_pos*12.0/public.on_div_size(p_div)))::int idx,
   (c.prize_league->0->>'cash')::numeric top,
   case when p_result in('promoted','champion') and p_div<>'A'
     then (c.prize_league->0->>'cash')::numeric*coalesce((c.series_mult->>chr(ascii(p_div)-1))::numeric,1)*coalesce((c.series_bonus->>'promotion')::numeric,0)
    when p_result='relegated' and p_div<>'D'
     then (c.prize_league->0->>'cash')::numeric*coalesce((c.series_mult->>p_div)::numeric,1)*coalesce((c.series_bonus->>'parachute')::numeric,0)
    else 0 end bonus
  from c)
 select jsonb_object_agg(e.key,case when e.key='cash' then round(e.value::numeric*m.m+m.bonus)::bigint else round(e.value::numeric*sqrt(m.m))::bigint end)
  ||jsonb_build_object('bonus',round(m.bonus)::bigint)
 from m,c,jsonb_each_text(c.prize_league->(m.idx-1)) e group by m.bonus
$$;

-- Paga uma série (prêmio pela posição + acesso/rebaixamento) e avisa. Uma vez por série e temporada (div_paid).
create or replace function public.on_series_div_award(p_season smallint,p_div text) returns boolean
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;r record;v jsonb;k public.on_clubs;
begin
 select * into s from public.on_seasons where id=p_season for update;
 if s.status<>'live' or not coalesce(s.series,false) or p_div=any(s.div_paid) then return false;end if;
 -- série encerrada: nenhum jogo de liga dela por jogar (as fases seguintes nascem no gancho antes desta chamada)
 if exists(select 1 from public.on_fixtures where season_id=p_season and comp='L' and div=p_div and status<>'done') then return false;end if;
 update public.on_seasons set div_paid=div_paid||p_div where id=p_season;
 for r in select x.* from public.on_series_result(p_season) x where x.div=p_div order by x.pos loop
  select * into k from public.on_clubs where id=r.club_id;
  v:=public.on_league_prize(p_div,r.pos,r.result);
  perform public.on_award(p_season,r.club_id,'L'||p_div,r.pos::text,v-'bonus',0);
  continue when k.user_id is null;
  if r.result in('promoted','champion') and p_div<>'A' then
   insert into public.on_news(club_id,kind,text) values(k.id,'season',format('ACESSO! Na próxima temporada o %s joga a %s. Bônus de acesso: %s.',
    k.name,public.on_div_name(chr(ascii(p_div)-1)),public.on_fmt_money((v->>'bonus')::bigint)));
  elsif r.result='relegated' then
   insert into public.on_news(club_id,kind,text) values(k.id,'season',format('Rebaixado: na próxima temporada o %s joga a %s. Ajuda para a nova série: %s.',
    k.name,public.on_div_name(chr(ascii(p_div)+1)),public.on_fmt_money((v->>'bonus')::bigint)));
  end if;
 end loop;
 return true;
end $$;

do $$ begin
 -- fim da temporada: só paga as séries que ainda não foram pagas (o pagamento é o mesmo de on_series_div_award)
 perform public.on_patch('public.on_series_end(smallint,timestamp with time zone)',
  '  for r in select h.* from public.on_history h where h.season_id=p_season and h.div is not null order by h.div,h.pos loop
   v_mult:=coalesce((cfg.series_mult->>r.div)::numeric,1);
   v_idx:=least(12,ceil(r.pos*12.0/public.on_div_size(r.div)))::int;
   v_prize:=(select jsonb_object_agg(e.key,round(e.value::numeric*v_mult)) from jsonb_each_text(cfg.prize_league->(v_idx-1)) e);
   perform public.on_award(p_season,r.club_id,''L''||r.div,r.pos::text,v_prize,0);',
  '  for r in select h.* from public.on_history h where h.season_id=p_season and h.div is not null
    and not h.div=any(coalesce((select div_paid from public.on_seasons where id=p_season),''{}'')) order by h.div,h.pos loop
   v_prize:=public.on_league_prize(r.div,r.pos,r.result); -- fase 40: dinheiro pelo peso da série, resto pela raiz, acesso e rebaixamento
   perform public.on_award(p_season,r.club_id,''L''||r.div,r.pos::text,v_prize-''bonus'',0);');
 -- série que acabou paga na hora (o campeão comemora sem esperar a final da copa)
 perform public.on_patch('public.on_series_hook(bigint)',
  ' if not exists(select 1 from public.on_fixtures x where x.season_id=s.id and x.status<>''done'') then
  perform public.on_series_end(',
  ' if f.comp=''L'' and f.div is not null then perform public.on_series_div_award(s.id,f.div);end if; -- fase 40
 if not exists(select 1 from public.on_fixtures x where x.season_id=s.id and x.status<>''done'') then
  perform public.on_series_end(');
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Ficha de jogador em leilão (mercado)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_player_sheet(p_player text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();p public.on_players;
begin
 select x.* into p from public.on_players x where x.id=p_player and (
  exists(select 1 from public.on_clubs k where k.id=x.club_id and k.season_id=c.season_id)
  or exists(select 1 from public.on_lots l where l.player_id=x.id and l.status='open'));
 if p.id is null then raise exception 'Jogador não encontrado';end if;
 return public.on_sheet(p)||jsonb_build_object('id',p.id,'name',p.name,'pos',p.pos,'legend',coalesce(p.legend,false),'mine',p.club_id=c.id);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. "Já vi" por conta
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.ui_seen(
 user_id uuid not null,
 key text not null check (length(key) between 1 and 80),
 value int not null default 1,
 seen_at timestamptz not null default now(),
 primary key(user_id,key));
alter table public.ui_seen enable row level security;
revoke all on public.ui_seen from anon,authenticated;

-- Marca "visto" com um valor (nível, 1 para festa) e devolve o valor anterior (null na primeira vez). Só sobe.
-- Dois aparelhos ao mesmo tempo: o primeiro leva o valor anterior verdadeiro; o segundo já vê o novo (não repete a festa).
create or replace function public.ui_seen_bump(p_key text,p_value int default 1) returns int
language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid();v int;
begin
 if u is null then raise exception 'Faça login';end if;
 insert into public.ui_seen(user_id,key,value) values(u,p_key,p_value) on conflict do nothing;
 if found then return null;end if;
 select value into v from public.ui_seen where user_id=u and key=p_key for update;
 if p_value>v then update public.ui_seen set value=p_value,seen_at=now() where user_id=u and key=p_key;end if;
 return v;
end $$;

-- Lê vários de uma vez (para não pedir um por um): {chave: valor}
create or replace function public.ui_seen_get(p_keys text[]) returns jsonb
language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from public.ui_seen where user_id=auth.uid() and key=any(p_keys)
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Elenco de bot incompleto: as cartas geradas só completam as posições que faltam
-- ─────────────────────────────────────────────────────────────────────────────
-- Antes, com menos de 18 reais, entravam 22 geradas e saíam as de camisa mais alta entre as sem origem no catálogo —
-- o que incluía jogadores reais das Séries C e D (também sem origem) e podia deixar o time sem goleiro.
do $$ begin
 perform public.on_patch('public.on_bot_squad(integer,text)',
  'declare k public.on_clubs;rc public.on_real_clubs;v_lv int;v_end int;n int:=0;r record;v_id text;',
  'declare k public.on_clubs;rc public.on_real_clubs;v_lv int;v_end int;n int:=0;r record;v_id text;v_old text[];');
 perform public.on_patch('public.on_bot_squad(integer,text)',
  '  perform public.on_gen_fake(p_club,p_seed||'':''||p_club,v_lv,v_end);
  if n>0 then -- completa: tira as geradas que sobram nas posições já cheias
   delete from public.on_players p where p.club_id=p_club and p.src is null
    and p.id in(select x.id from public.on_players x where x.club_id=p_club and x.src is null order by x.number desc limit greatest(0,n+22-23));
  end if;',
  '  v_old:=array(select id from public.on_players where club_id=p_club);
  perform public.on_gen_fake(p_club,p_seed||'':''||p_club,v_lv,v_end);
  if n>0 then -- fase 40: completa só o que falta em cada posição (3 goleiros, 4 zagueiros, 2 nas demais); reais nunca saem
   delete from public.on_players p where p.id in(
    select g.id from(select x.id,x.pos,row_number() over(partition by x.pos order by x.ovr desc,x.id) rn
     from public.on_players x where x.club_id=p_club and not x.id=any(v_old)) g
    where g.rn>greatest(0,case g.pos when ''GOL'' then 3 when ''ZAG'' then 4 else 2 end
     -(select count(*) from public.on_players o where o.id=any(v_old) and o.pos=g.pos)));
  end if;');
 -- elenco real sem 2 goleiros também é completado
 perform public.on_patch('public.on_bot_squad(integer,text)',
  ' if n<18 then
  v_old:=',
  ' if n<18 or (select count(*) from public.on_players g where g.club_id=p_club and g.pos=''GOL'')<2 then
  v_old:=');
end $$;

-- temporada em andamento: refaz os bots com menos de 2 goleiros (jogo ainda não começou para eles)
do $$ declare r record;
begin
 for r in select k.id,s.seed from public.on_clubs k join public.on_seasons s on s.id=k.season_id and s.status='live'
  where k.user_id is null and (select count(*) from public.on_players p where p.club_id=k.id and p.pos='GOL')<2
   and not exists(select 1 from public.on_fixtures f where f.season_id=s.id and k.id in(f.home,f.away) and f.status<>'sched') loop
  perform public.on_bot_squad(r.id,r.seed);
 end loop;
end $$;

revoke all on function public.on_league_prize(text,int,text),public.on_series_div_award(smallint,text) from public,anon,authenticated;
revoke all on function public.on_player_sheet(text),public.ui_seen_bump(text,int),public.ui_seen_get(text[]) from public,anon;
grant execute on function public.on_player_sheet(text),public.ui_seen_bump(text,int),public.ui_seen_get(text[]) to authenticated;
