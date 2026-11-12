-- MODO ONLINE — Fase 10: abertura para todos.
--
--  • Entrada na hora: quem chega com a temporada em andamento assume um clube de bot (o pior colocado que não
--    esteja jogando nem liderando leilão), com elenco real novo, $ 150 mil e a escolha dos três craques. O clube
--    mantém calendário e pontos. Sem bot livre, o usuário entra na fila da próxima temporada (join_instant
--    falso desliga a entrada na hora).
--  • Mercado: quatro leilões comuns (até 80) e, todo dia, um destaque (81 ou mais, 19:00) e uma lenda (20:00).
--    Os dois aparecem cedo, travados, com o horário.

alter table public.on_config add column if not exists join_instant boolean not null default true;
alter table public.on_config alter column featured_count set default 4;
update public.on_config set featured_count=4 where featured_count=3;

-- Entra no modo: assume um clube de bot da temporada em andamento ou, sem vaga, entra na fila.
create or replace function public.on_join_queue() returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid();s public.on_seasons;v_club int;v_nick text;v_name text;
begin
 if v_uid is null then raise exception 'Entre na sua conta para jogar';end if;
 if not public.on_gate() then raise exception 'O modo online ainda não está aberto para a sua conta';end if;
 select * into s from public.on_seasons where status='live';
 if s.id is not null and exists(select 1 from public.on_clubs where season_id=s.id and user_id=v_uid) then return public.on_status();end if;
 if s.id is not null and (select join_instant from public.on_config) then
  select k.id into v_club from public.on_clubs k
  where k.season_id=s.id and k.user_id is null and k.reserved=0
   and not exists(select 1 from public.on_matches m join public.on_fixtures f on f.id=m.fixture_id where m.status='live' and k.id in(f.home,f.away))
   and not exists(select 1 from public.on_lots l where l.status='open' and l.best_club=k.id)
  order by (select r.pos from public.on_rank(s.id) r where r.club_id=k.id) desc
  limit 1 for update of k skip locked;
 end if;
 if v_club is null then
  insert into public.on_access(user_id,state) values(v_uid,'queued') on conflict(user_id) do nothing;
  return public.on_status();
 end if;
 select c.nickname into v_nick from public.careers c where c.user_id=v_uid order by (c.status='active') desc,c.created_at desc limit 1;
 v_name:=left('FC '||coalesce(v_nick,'Novo'),24);
 if exists(select 1 from public.on_clubs k where k.season_id=s.id and lower(k.name)=lower(v_name)) then v_name:=left(v_name,21)||' '||v_club;end if;
 delete from public.on_players where club_id=v_club;
 delete from public.on_lineups where club_id=v_club;
 update public.on_clubs set user_id=v_uid,name=v_name,
  short=upper(left(coalesce(nullif(regexp_replace(coalesce(v_nick,''),'[^A-Za-z0-9]','','g'),''),'CLB'),3)),
  colors=colors||jsonb_build_object('stadium','Arena '||left(coalesce(v_nick,'do Clube'),20)),
  cash=150000,debt=0,reserved=0,draft_step=0,prep='{}',prep_streak=0,train_used=0,train_day=null,coins_conv=0
 where id=v_club;
 perform public.on_gen_squad(v_club,s.seed||':join:'||v_club,62,s.id+1);
 perform public.on_draft_prepare(v_club);
 insert into public.on_access(user_id,state) values(v_uid,'allowed') on conflict(user_id) do update set state='allowed';
 insert into public.on_news(club_id,kind,text) values(v_club,'season','Bem-vindo à liga! Escolha seus três craques e prepare o time para o próximo jogo.');
 return public.on_status();
end $$;

-- Leilões comuns em quatro faixas, sempre até 80: 76 a 80, 72 a 76, 68 a 72 e 63 a 68.
create or replace function public.on_gen_featured(p_seed text,p_tier int) returns text
language plpgsql security definer set search_path=public as $$
declare v_lo numeric:=(array[76,72,68,63])[p_tier];v_hi numeric:=(array[80.5,76,72,68])[p_tier];v_src text;v_id text;
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

-- Especiais do dia. p_legend: lenda; senão, destaque (jogador de 81 ou mais que não é lenda). Nulo se não houver livre.
create or replace function public.on_gen_special(p_seed text,p_legend boolean) returns text
language plpgsql security definer set search_path=public as $$
declare v_src text;v_end int:=(select max(id) from public.on_seasons)+2;
begin
 v_src:=case when p_legend then public.on_real_pick(null,80,100,p_seed,true) else public.on_real_pick(null,80.5,100,p_seed,false) end;
 if v_src is null then return null;end if;
 return public.on_real_insert(v_src,null,null,v_end,true);
end $$;

-- Gancho do cron: fecha lotes vencidos, mantém os leilões comuns, cria o destaque (featured 9) e a lenda
-- (featured 8) do dia e move os bots.
create or replace function public.on_market_tick(p_now timestamptz,p_new_day boolean) returns void
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;cfg public.on_config;r record;t int;pid text;k int;v_bid bigint;v_end timestamptz;v_day date;v_hour int;v_open timestamptz;sp record;
begin
 select * into s from public.on_seasons where status='live';
 if s.id is null then return;end if;
 select * into cfg from public.on_config;
 v_day:=(p_now at time zone s.tz)::date;
 v_hour:=extract(hour from p_now at time zone s.tz);
 for r in select l.id from public.on_lots l where l.season_id=s.id and l.status='open' and l.ends_at<=p_now order by l.ends_at limit 10 loop
  perform public.on_lot_settle(r.id,p_now);
 end loop;
 if v_hour between 8 and 22 then
  for t in 1..least(cfg.featured_count,4) loop
   continue when exists(select 1 from public.on_lots x where x.season_id=s.id and x.status='open' and x.featured=t);
   pid:=public.on_gen_featured(s.seed||':f:'||t||':'||floor(extract(epoch from p_now))::bigint,t);
   v_end:=case when cfg.featured_minutes=60 then date_trunc('hour',p_now+interval '15 minutes')+interval '1 hour'
    else p_now+cfg.featured_minutes*interval '1 minute' end;
   insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
   select s.id,pid,public.on_start_price(p),p_now,v_end,v_end+cfg.lot_extend_max,t from public.on_players p where p.id=pid;
  end loop;
 end if;
 -- especiais do dia: aparecem cedo e travados. Destaque às special_hour; lenda uma hora depois. Cada um dura uma hora.
 for sp in select * from(values(9,false,0),(8,true,1)) v(feat,legend,plus) loop
  continue when v_hour>=cfg.special_hour+sp.plus;
  continue when exists(select 1 from public.on_lots x where x.season_id=s.id and x.featured=sp.feat and (x.opens_at at time zone s.tz)::date=v_day);
  pid:=public.on_gen_special(s.seed||':special:'||sp.feat||':'||v_day,sp.legend);
  continue when pid is null;
  v_open:=(v_day+make_time(cfg.special_hour+sp.plus,0,0)) at time zone s.tz;
  insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
  select s.id,pid,public.on_start_price(p),v_open,v_open+interval '1 hour',v_open+interval '1 hour'+cfg.lot_extend_max,sp.feat
  from public.on_players p where p.id=pid;
 end loop;
 -- bots: entram na disputa só quando um técnico já deu lance, nos últimos 3 minutos, até 70% a 90% do valor
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

-- Mercado: leilões abertos e os especiais do dia (mesmo antes de abrir).
create or replace function public.on_market() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();cfg public.on_config;
begin
 select * into cfg from public.on_config;
 return jsonb_build_object('server_now',now(),'my_club',c.id,
  'club',jsonb_build_object('cash',c.cash,'reserved',c.reserved,'debt',c.debt,'roster',(select count(*) from public.on_players where club_id=c.id)),
  'coins',jsonb_build_object('wallet',coalesce(public.on_wallet(),0),'rate',cfg.coin_rate,'bid_rate',cfg.coin_bid_rate,'converted',c.coins_conv,'cap',cfg.coin_cap),
  'lots',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.featured<8,l.featured desc,l.ends_at) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='open' and (x.featured>=8 or x.opens_at<=now())) l where l.featured>=8),'[]'::jsonb)
   ||coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.featured=0,l.featured,l.ends_at) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='open' and x.featured<8 and x.opens_at<=now()) l),'[]'::jsonb),
  'recent',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.settled_at desc) from(
    select * from public.on_lots x where x.season_id=c.season_id and x.status='sold' order by x.settled_at desc limit 8) l),'[]'::jsonb));
end $$;

revoke all on function public.on_gen_featured(text,int),public.on_gen_special(text,boolean),public.on_market_tick(timestamptz,boolean) from public,anon,authenticated;
revoke all on function public.on_join_queue(),public.on_market() from public,anon;
grant execute on function public.on_join_queue(),public.on_market() to authenticated;
