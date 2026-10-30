-- EVOLUÇÃO 37: correções de mercado, economia mais realista e avanço mais leve.
-- * Renovar de novo antes de enviar a proposta reabre a renovação já aberta (antes: "duplicate key").
-- * Venda para clube da IA: quando o atleta pede salário maior, o clube comprador da IA aceita sozinho e a venda
--   é registrada (antes ficava parada esperando o comprador e expirava; o dinheiro nunca entrava).
-- * Vendas concluídas cujo valor não entrou no caixa: a diferença é creditada no clube atual do treinador.
-- * Busca no mercado só lê (não trava a carreira) e usa o valor de mercado guardado: sem tempo limite estourado.
-- * Notícias só do seu clube (propostas, contratações, resultados, finanças e empregos) e os campeões. As dos outros clubes
--   deixam de ser criadas e as antigas são apagadas. O gatilho de resultados fica bem mais leve.
-- * Receita de jogo: bilheteria para o mandante e prêmio por vitória/empate, em todos os jogos do mundo.
-- * Seu clube acumula caixa até 10× o orçamento inicial (antes 3×: o excedente sumia todo mês em "investimento").
-- * Valor de mercado mais realista: dobra a cada ~4,5 pontos de nota (medianos baratos, craques caros).
begin;

-- ---------- renovação: reusa a negociação aberta ----------
do $$ begin
 if to_regprocedure('public.career_contract_renew_before_v37(text,uuid)') is null then
  alter function public.career_contract_renew(text,uuid) rename to career_contract_renew_before_v37;
 end if;
 if to_regprocedure('public.cw_market_tick_before_v37(uuid)') is null then
  alter function public.cw_market_tick(uuid) rename to cw_market_tick_before_v37;
 end if;
end $$;

create or replace function public.career_contract_renew(p_player text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;own text;open_id uuid;prev jsonb;d date;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'contract_renew');if prev is not null then return prev;end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 select today into d from public.cw_world where career_id=car.id;
 select id into open_id from public.cw_negotiations where career_id=car.id and player_id=p_player and buyer_club=own and initiator='renewal'
  and status in('seller_review','club_pending','club_counter','player_pending','player_counter') order by created_on desc limit 1;
 if open_id is null then return public.career_contract_renew_before_v37(p_player,p_request);end if;
 -- Ainda não enviada (ou aguardando): reabre a mesma renovação com prazo renovado.
 update public.cw_negotiations set expires_on=greatest(expires_on,public.cw_deadline(d)) where id=open_id;
 return public.econ_request_save(car.id,p_request,'contract_renew',jsonb_build_object('id',open_id,'reopened',true));
end $$;

-- ---------- mercado: comprador da IA aceita o pedido salarial do atleta ----------
create or replace function public.cw_market_tick(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
declare d date;own text;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 update public.cw_negotiations set status='player_pending',reply_on=d,response='O clube comprador aceitou as condições pedidas pelo atleta.'
  where career_id=p_career and status='player_counter' and initiator<>'renewal' and buyer_club is distinct from own and expires_on>=d;
 perform public.cw_market_tick_before_v37(p_career);
end $$;

-- ---------- notícias: só as do seu clube ----------
create or replace function public.cw_news_add(p_career uuid,p_key text,p_kind text,p_title text,p_body text,p_priority int default 40,p_club text default null,
 p_player text default null,p_season uuid default null,p_meta jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare own text;
begin
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 if not coalesce(p_kind in('world','job','finance','title')
   or (own is not null and (p_club is not distinct from own or p_meta->>'from_club' is not distinct from own or p_meta->>'to_club' is not distinct from own
     or (p_player is not null and exists(select 1 from public.mgr_players where career_id=p_career and player_id=p_player and club_id=own)))),false) then
  return;
 end if;
 insert into public.cw_news(career_id,event_key,on_date,kind,title,body,priority,club_id,player_id,season_id,metadata)
 select p_career,p_key,today,p_kind,p_title,p_body,p_priority,p_club,p_player,p_season,p_meta from public.cw_world where career_id=p_career on conflict do nothing;
end $$;

-- ---------- resultado: notícias do seu clube + receita de jogo ----------
create or replace function public.cw_result_news()
returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c uuid;own text;winner text;loser text;sc public.sim_competitions;mult numeric;home public.cw_clubs;prize bigint;leader record;second_team record;
begin
 if new.status<>'played' or (tg_op='UPDATE' and old.status='played') then return new;end if;
 select career_id into c from public.career_seasons where id=new.season_id;
 if c is null or not exists(select 1 from public.cw_world where career_id=c) then return new;end if;
 select * into sc from public.sim_competitions where id=new.competition_id;
 select club_id into own from public.mgr_coach where career_id=c and status='employed';
 winner:=case when new.home_goals>new.away_goals then new.home_club when new.away_goals>new.home_goals then new.away_club else new.tie_winner end;
 loser:=case when winner=new.home_club then new.away_club when winner=new.away_club then new.home_club end;
 -- Receita de jogo: bilheteria do mandante (torcida) e prêmio por resultado. Uma vez por jogo (referência única).
 mult:=case sc.kind when 'continental' then 1.6 when 'cup' then 1.2 else 1 end;
 select * into home from public.cw_clubs where career_id=c and club_id=new.home_club;
 if found then
  perform public.cw_cash(c,new.home_club,round(home.fanbase*.02*mult)::bigint,'matchday','match:'||new.id,'Bilheteria: '||public.mgr_club_name(new.home_club)||' × '||public.mgr_club_name(new.away_club));
 end if;
 if new.home_goals<>new.away_goals then
  select round((1500+prestige*30)*mult)::bigint into prize from public.cw_clubs where career_id=c and club_id=case when new.home_goals>new.away_goals then new.home_club else new.away_club end;
  if prize is not null then perform public.cw_cash(c,case when new.home_goals>new.away_goals then new.home_club else new.away_club end,prize,'match_prize','match:'||new.id,'Premiação por vitória');end if;
 else
  for winner in select unnest(array[new.home_club,new.away_club]) loop
   select round((1500+prestige*30)*mult/3)::bigint into prize from public.cw_clubs where career_id=c and club_id=winner;
   if prize is not null then perform public.cw_cash(c,winner,prize,'match_prize','match:'||new.id,'Premiação por empate');end if;
  end loop;
  winner:=new.tie_winner;
 end if;
 if own is null or own not in(new.home_club,new.away_club) then return new;end if;
 if new.tie_winner is not null and new.stage not in('league','group','swiss') then
  perform public.cw_news_add(c,'knockout:'||new.id,'result',public.mgr_club_name(new.tie_winner)||' avança de fase',public.mgr_club_name(loser)||' deixa a disputa de '||sc.name||'.',60,own,null,new.season_id,jsonb_build_object('fixture_id',new.id));
 end if;
 if new.player_match then
  perform public.cw_news_add(c,'user-result:'||new.id,'result',public.mgr_club_name(new.home_club)||' '||new.home_goals||' × '||new.away_goals||' '||public.mgr_club_name(new.away_club),sc.name||' · Rodada '||new.round_no||'.',90,own,null,new.season_id,jsonb_build_object('fixture_id',new.id));
 end if;
 if sc.kind='league' and new.round_no>=8 and not exists(select 1 from public.season_fixtures fx where fx.season_id=new.season_id and fx.competition_id=new.competition_id and fx.round_no=new.round_no and fx.status='pending') then
  select * into leader from public.sim_standings(new.season_id,new.competition_id,null) where pos=1;
  select * into second_team from public.sim_standings(new.season_id,new.competition_id,null) where pos=2;
  if leader.points-second_team.points<=2 and own in(leader.club_id,second_team.club_id) then
   perform public.cw_news_add(c,'race:'||new.season_id||':'||sc.id||':'||new.round_no,'race','Disputa pela liderança de '||sc.name,
    public.mgr_club_name(leader.club_id)||' e '||public.mgr_club_name(second_team.club_id)||' terminaram a rodada '||new.round_no||' separados por até dois pontos.',50,own,null,new.season_id);
  end if;
 end if;
 return new;
end $$;

-- ---------- teto de caixa: seu clube pode acumular para contratar ----------
create or replace function public.cw_settle_month(p_career uuid, p_month date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare month_end date:=(p_month+interval '1 month - 1 day')::date;month_days int;ct public.cw_contracts;staff public.cw_coach_contracts;club public.cw_clubs;
 due bigint;paid bigint;before_cash bigint;overlap int;ref text;apps int;goals int;revenue bigint;surplus bigint;debt_paid bigint;
begin
 perform 1 from public.careers where id=p_career for update;
 month_days:=month_end-p_month+1;
 for club in select * from public.cw_clubs where career_id=p_career order by club_id loop
  ref:=to_char(p_month,'YYYY-MM');
  select count(*) into apps from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
   where d.career_id=p_career and f.status='played' and f.home_club=club.club_id and d.due_on between p_month and month_end;
  revenue:=club.monthly_revenue+apps*(300+club.prestige::int*12);
  perform public.cw_cash(p_career,club.club_id,revenue,'commercial',ref,'Receitas comerciais, torcida e bilheteria');
  perform public.cw_cash(p_career,club.club_id,-round(revenue*.12)::bigint,'operations',ref,'Comissão técnica e operação do clube',true);
 end loop;
 for ct in select * from public.cw_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by club_id,id loop
  ref:=ct.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=ct.club_id and kind='wages' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on))-greatest(p_month,ct.starts_on)+1);
  select count(*),coalesce(sum(mp.goals),0) into apps,goals from public.cw_appearances mp
   where mp.career_id=p_career and mp.player_id=ct.player_id and mp.club_id=ct.club_id and mp.minutes>0 and mp.on_date between greatest(p_month,ct.starts_on) and least(month_end,ct.expires_on,coalesce(ct.ended_on,ct.expires_on));
  due:=round(ct.monthly_salary*overlap::numeric/month_days)+apps*ct.appearance_bonus+goals*ct.goal_bonus;
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=ct.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,ct.club_id,-due,'wages',ref,'Salário de '||public.mgr_player_name(ct.player_id),true,jsonb_build_object('contract_id',ct.id,'paid',paid,'owed',due-paid));
  update public.cw_contracts set arrears=arrears+due-paid where id=ct.id;
 end loop;
 for staff in select * from public.cw_coach_contracts where career_id=p_career and starts_on<=month_end and coalesce(ended_on,expires_on)>=p_month order by id loop
  ref:=staff.id::text||':'||to_char(p_month,'YYYY-MM');
  if exists(select 1 from public.cw_finance where career_id=p_career and club_id=staff.club_id and kind='coach_salary' and reference=ref) then continue;end if;
  overlap:=greatest(0,least(month_end,staff.expires_on,coalesce(staff.ended_on,staff.expires_on))-greatest(p_month,staff.starts_on)+1);
  due:=round(staff.monthly_salary*overlap::numeric/month_days);
  if due<=0 then continue;end if;
  select cash into before_cash from public.cw_clubs where career_id=p_career and club_id=staff.club_id;
  paid:=least(before_cash,due);
  perform public.cw_cash(p_career,staff.club_id,-due,'coach_salary',ref,'Salário do treinador',true,jsonb_build_object('paid',paid,'owed',due-paid));
  if paid>0 then perform public.econ_apply(p_career,'coins',paid::int,'coach_salary',ref);end if;
  update public.cw_coach_contracts set arrears=arrears+due-paid where id=staff.id;
 end loop;
 for club in select * from public.cw_clubs where career_id=p_career order by club_id loop
  -- Retained surpluses are recorded as club infrastructure, not unlimited cash for players.
  -- Seu clube pode juntar até 10× o orçamento inicial para contratar; os da IA seguem com 3×.
  surplus:=greatest(0,club.cash-case when club.club_id=(select mc.club_id from public.mgr_coach mc where mc.career_id=p_career and mc.status='employed') then 10 else 3 end*club.initial_budget);
  if surplus>0 and club.debt=0 and not exists(select 1 from public.cw_finance where career_id=p_career and club_id=club.club_id and kind='infrastructure' and reference=to_char(p_month,'YYYY-MM')) then
   perform public.cw_cash(p_career,club.club_id,-surplus,'infrastructure',to_char(p_month,'YYYY-MM'),'Investimento patrimonial da diretoria');
   update public.cw_clubs set infrastructure=infrastructure+surplus where career_id=p_career and club_id=club.club_id;
  end if;
 end loop;
end $function$;

-- ---------- valor de mercado ----------
create or replace function public.cw_player_value(p_career uuid,p_player text)
returns bigint language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare rating numeric;age numeric;pot numeric;performance numeric:=1;
begin
 select r.rating,coalesce(cp.age_at_start,p.age,case when p.is_youth then 19 else 26 end)+coalesce(floor((w.today-w.started_on)/365.25),0),coalesce(cp.potential,r.rating)
 into rating,age,pot from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
 left join public.cw_players cp on cp.career_id=p_career and cp.player_id=p.id left join public.cw_world w on w.career_id=p_career where p.id=p_player;
 if rating is null then raise exception 'Atleta sem avaliação';end if;
 select greatest(.85,least(1.15,1+(coalesce(avg(x.rating),6.5)-6.5)*.06)) into performance from(
  select a.rating from public.cw_appearances a where a.career_id=p_career and a.player_id=p_player and a.minutes>0 order by a.on_date desc,a.fixture_id desc limit 5)x;
 -- Curva realista: 80 de nota ≈ 40 mil; dobra a cada 4,5 pontos (85 ≈ 86 mil, 90 ≈ 185 mil, 75 ≈ 18 mil, 70 ≈ 8,6 mil).
 return round(performance*greatest(250,40000*power(2,(least(rating,99)-80)/4.5))
  *case when age<21 then 1.3 when age<24 then 1.2 when age<28 then 1 when age<31 then .8 when age<33 then .55 else .3 end
  *(1+greatest(0,pot-rating)*.03))::bigint;
end $$;

-- ---------- busca no mercado: só leitura, sem travar a carreira ----------
create or replace function public.career_player_search(p_query text default '',p_position text default '',p_region text default '',p_club text default '',
 p_max_value bigint default null,p_page int default 0,p_country text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car uuid:=public.cw_current_career();own text;w public.cw_world;
begin
 if car is null then raise exception 'Carreira ativa não encontrada';end if;
 select * into w from public.cw_world where career_id=car;
 if not found then return public.career_player_search_before_v32(p_query,p_position,p_region,p_club,p_max_value,p_page,p_country);end if;
 select club_id into own from public.mgr_coach where career_id=car;
 return(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('number',public.cw_shirt_number(car,x.id)) order by x.overall desc,x.id),'[]') from(
  select b.id,b.name,b.short_name,b.position,b.club_id,b.nationality,b.overall,round(mp.condition) as condition,
   cp.age_at_start+floor((w.today-w.started_on)/365.25)::int as age,cp.age_estimated,cp.potential,cp.morale,cp.promised_role,cp.transfer_requested,
   public.cw_player_value(car,b.id) as value,ct.monthly_salary,ct.expires_on,ct.role,ct.arrears,
   coalesce((select sum(st.minutes) from public.mgr_player_stats st join public.career_seasons ss on ss.id=st.season_id where ss.career_id=car and ss.status='active' and st.player_id=b.id),0) as minutes
  from(
   select sp.id,sp.full_name as name,sp.short_name,sp.position,mp.club_id,sp.nationality,round(pr.rating) as overall
   from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
   join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
   where mp.career_id=car and sp.active and (coalesce(p_query,'')='' or sp.full_name ilike '%'||left(p_query,60)||'%')
    and (coalesce(p_country,'')='' or (select country from public.sim_clubs sc where sc.id=mp.club_id)=upper(p_country))
    and (coalesce(p_position,'')='' or sp.position=p_position)
    and (coalesce(p_region,'')='' or public.cw_region(mp.club_id)=p_region or(p_region='free' and mp.club_id is null))
    and (coalesce(p_club,'')='' or mp.club_id=case when p_club='mine' then own else p_club end)
    and (p_max_value is null or cp.market_value<=p_max_value)
   order by pr.rating desc,sp.id limit 30 offset least(greatest(coalesce(p_page,0),0),200)*30) b
  join public.mgr_players mp on mp.career_id=car and mp.player_id=b.id
  join public.cw_players cp on cp.career_id=car and cp.player_id=b.id
  left join public.cw_contracts ct on ct.career_id=car and ct.player_id=b.id and ct.status='active') x);
end $$;

revoke all on function public.career_contract_renew_before_v37(text,uuid),public.cw_market_tick_before_v37(uuid),public.cw_market_tick(uuid),
 public.cw_news_add(uuid,text,text,text,text,int,text,text,uuid,jsonb),public.cw_player_value(uuid,text),public.cw_result_news(),public.cw_settle_month(uuid,date) from public,anon,authenticated;
revoke all on function public.career_contract_renew(text,uuid),public.career_player_search(text,text,text,text,bigint,int,text) from public,anon;
grant execute on function public.career_contract_renew(text,uuid),public.career_player_search(text,text,text,text,bigint,int,text) to authenticated;

-- ---------- dados: valores de mercado, notícias e vendas sem recebimento ----------
update public.cw_players cp set market_value=public.cw_player_value(cp.career_id,cp.player_id)
 where exists(select 1 from public.cw_world w where w.career_id=cp.career_id);

delete from public.cw_news n using public.mgr_coach mc
 where mc.career_id=n.career_id and n.kind not in('world','job','finance','title')
  and (mc.status<>'employed' or mc.club_id is null or (n.club_id is distinct from mc.club_id
   and coalesce(n.metadata->>'from_club','')<>mc.club_id and coalesce(n.metadata->>'to_club','')<>mc.club_id));

do $$
declare n record;missing bigint;dest text;
begin
 for n in
  select ng.*,mc.club_id as coach_club,mc.status as coach_status,
   coalesce((select sum(f.amount) from public.cw_finance f where f.career_id=ng.career_id and f.club_id=ng.seller_club
     and ((f.kind='player_sale' and f.reference=ng.id||':0')
      or (f.kind='player_sale_clause' and f.reference in(select cm.id::text from public.cw_commitments cm where cm.negotiation_id=ng.id)))),0)
   +coalesce((select sum(f.amount) from public.cw_finance f where f.career_id=ng.career_id and f.kind='sale_fix' and f.reference='salefix:'||ng.id),0) as received,
   coalesce((select sum(cm.amount) from public.cw_commitments cm where cm.negotiation_id=ng.id and cm.kind='installment' and cm.status='reserved'),0) as pending
  from public.cw_negotiations ng join public.mgr_coach mc on mc.career_id=ng.career_id
  where ng.status='completed' and ng.initiator<>'renewal' and ng.seller_club is not null and ng.fee>0
   and exists(select 1 from public.cw_coach_contracts cc where cc.career_id=ng.career_id and cc.club_id=ng.seller_club
    and ng.register_on>=cc.starts_on and ng.register_on<=coalesce(cc.ended_on,'9999-12-31'::date))
 loop
  missing:=n.fee-n.received-n.pending;
  if missing>0 then
   dest:=case when n.coach_status='employed' and n.coach_club is not null then n.coach_club else n.seller_club end;
   perform public.cw_cash(n.career_id,dest,missing,'sale_fix','salefix:'||n.id,'Ajuste: valor de venda de '||public.mgr_player_name(n.player_id)||' que não havia entrado no caixa');
   raise notice 'Venda corrigida: carreira % atleta % +%',n.career_id,n.player_id,missing;
  end if;
 end loop;
end $$;

notify pgrst,'reload schema';
commit;
