-- Renovações perdidas em silêncio.
-- 1) Renovação aceita pelo atleta é registrada na hora (antes ficava em 'player_accepted' por 7 dias
--    e expirava se o treinador avançasse o calendário sem confirmar; o contrato vencia e o titular saía de graça).
-- 2) Contratação aceita pelo atleta ('player_accepted') agora pausa o avanço de dias (cw_attention)
--    e o passo do calendário para na véspera do prazo.

CREATE OR REPLACE FUNCTION public.cw_market_tick_before_v70(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;cp public.cw_players;rk int;minfee numeric;
 sb public.sim_clubs;bb public.sim_clubs;age int;rating numeric;wants_out boolean;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 -- Every new decision uses the same salary floor, including renewals and free agents.
 for n in select * from public.cw_negotiations where career_id=p_career and status='player_pending' and reply_on<=d and expires_on>=d order by created_on,id for update loop
  if n.initiator='renewal' and not public.cw_valid_renewal(p_career,n.player_id,n.buyer_club,d) then
   perform public.cw_neg_close(n.id,'rejected','O atleta já não possui vínculo vigente com o clube.');continue;
  end if;
  if public.cw_project_reason(p_career,n.player_id,n.buyer_club) is not null then
   perform public.cw_neg_close(n.id,'rejected',public.cw_project_reason(p_career,n.player_id,n.buyer_club));continue;
  end if;
  if n.monthly_salary<public.cw_salary_demand(p_career,n.player_id,n.buyer_club)
   or(n.seller_club is null and n.initiator<>'renewal' and n.signing_bonus<public.cw_minimum_signing(p_career,n.player_id,n.buyer_club)) then
   if n.round_no>=3 then perform public.cw_neg_close(n.id,'rejected','O atleta recusou as condições salariais e as luvas.');
   else
    update public.cw_negotiations set status='player_counter',monthly_salary=greatest(monthly_salary,public.cw_salary_demand(p_career,n.player_id,n.buyer_club)),
     signing_bonus=greatest(signing_bonus,case when seller_club is null and initiator<>'renewal' then public.cw_minimum_signing(p_career,n.player_id,n.buyer_club) else 0 end),
     round_no=round_no+1,expires_on=public.cw_deadline(d),response='O atleta exige salário e luvas compatíveis com sua qualidade e com o projeto esportivo.' where id=n.id;
    perform public.cw_neg_history(n.id,'player','Exigência salarial e de luvas atualizada.');
   end if;
  elsif n.initiator='renewal' and n.buyer_club=own then
   -- renovação: a pedida foi informada; cobrindo-a, o atleta aceita e o contrato é registrado na hora.
   -- O atleta já é do clube: não há papelada a esperar nem prazo de confirmação que expire em silêncio
   -- enquanto os dias avançam (antes o vínculo vencia e o titular saía de graça).
   begin
    perform public.cw_reserve_offer(n.id);
    update public.cw_negotiations set status=case when n.register_on is not null then 'precontract' else 'agreed' end,
     response='Renovação aceita pelo atleta e registrada automaticamente.',register_on=coalesce(n.register_on,d) where id=n.id;
    perform public.cw_neg_history(n.id,'player','O atleta aceitou a renovação; contrato registrado automaticamente.');
    perform public.cw_register_transfer(n.id);
   exception when raise_exception then
    perform public.cw_neg_close(n.id,'failed_funds',sqlerrm);
   end;
  end if;
 end loop;
 -- Comprador da IA aceita o pedido salarial do atleta (evolução 37).
 update public.cw_negotiations set status='player_pending',reply_on=d,response='O clube comprador aceitou as condições pedidas pelo atleta.'
  where career_id=p_career and status='player_counter' and initiator<>'renewal' and buyer_club is distinct from own and expires_on>=d;

 for n in select * from public.cw_negotiations where career_id=p_career and status in('club_pending','player_pending') and reply_on<=d and expires_on>=d
   and initiator<>'renewal' order by created_on,id for update loop
  select * into ct from public.cw_contracts where career_id=p_career and player_id=n.player_id and status='active';
  select * into cp from public.cw_players where career_id=p_career and player_id=n.player_id;
  select * into bb from public.sim_clubs where id=n.buyer_club;
  select * into sb from public.sim_clubs where id=n.seller_club;
  select r.rating into rating from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=n.player_id;
  age:=cp.age_at_start+floor((d-(select started_on from public.cw_world where career_id=p_career))/365.25)::int;
  wants_out:=coalesce(cp.transfer_listed,false);

  -- Clube vendedor da IA: pilares e titulares não saem por qualquer valor.
  if n.status='club_pending' and n.seller_club is not null and n.seller_club is distinct from own
     and not wants_out and coalesce(ct.expires_on,d+999)>=d+180 and n.register_on is null then
   rk:=public.cw_squad_rank(p_career,n.seller_club,n.player_id);
   if rk<=3 and not(bb.strength>sb.strength+5 and n.fee>=n.valuation*3 and n.decision_roll>.7) then
    perform public.cw_neg_close(n.id,'rejected',public.mgr_club_name(n.seller_club)||' considera '||public.mgr_player_name(n.player_id)||' intocável: é um dos pilares do elenco.');
   elsif rk between 4 and 7 or (rk between 8 and 11 and n.initiator<>'ai') then
    if n.decision_roll<.2 then
     perform public.cw_neg_close(n.id,'rejected',public.mgr_club_name(n.seller_club)||' não quer perder um titular agora.');
    else
     -- Titulares principais (4º–7º) custam 1,6–2× o valor; os demais titulares (8º–11º), 1,25–1,5×. Comprador menor paga 20% a mais.
     minfee:=n.valuation*case when rk<=7 then 1.6+n.decision_roll*.4 else 1.25+n.decision_roll*.25 end*case when bb.strength<sb.strength then 1.2 else 1 end*case when n.buyer_club=own then (public.cw_difficulty_level(p_career)).seller_fee_mult else 1 end;
     if n.fee<minfee then
      if n.initiator='ai' and n.decision_roll>.3 and public.cw_available_budget(p_career,n.buyer_club)>=minfee then
       -- Comprador da IA com caixa topa pagar o preço de um titular.
       update public.cw_negotiations set fee=ceil(minfee) where id=n.id;
       perform public.cw_neg_history(n.id,'buyer','Comprador aceitou pagar o preço pedido por um titular.');
      elsif n.round_no>=2 or n.initiator='ai' then
       perform public.cw_neg_close(n.id,'rejected','O clube só libera um titular por um valor bem acima do mercado.');
      else
       update public.cw_negotiations set status='club_counter',fee=ceil(minfee),round_no=round_no+1,expires_on=public.cw_deadline(d),
        response='Titular do elenco: o clube só negocia por '||public.cw_money_label(ceil(minfee))||'.' where id=n.id;
       perform public.cw_neg_history(n.id,'seller','Contraproposta por um titular.');
      end if;
     end if;
    end if;
   end if;

  -- Atleta: carreira em primeiro lugar (não desce de divisão nem vai para clube bem menor sem motivo).
  elsif n.status='player_pending' and bb.id is not null then
   if sb.id is null then
    if rating>=bb.strength+12 and age<31 then
     perform public.cw_neg_close(n.id,'rejected',public.mgr_player_name(n.player_id)||' prefere esperar uma proposta de um clube do seu nível.');
    end if;
   elsif public.cw_club_level(n.buyer_club)>public.cw_club_level(n.seller_club)
      and not(age>=32 or (wants_out and n.monthly_salary>=coalesce(ct.monthly_salary,0)*1.3)) then
    perform public.cw_neg_close(n.id,'rejected',public.mgr_player_name(n.player_id)||' não aceita deixar a primeira divisão por um clube de divisão inferior: seria um retrocesso na carreira.');
   elsif public.cw_club_level(n.buyer_club)=public.cw_club_level(n.seller_club) and bb.strength<sb.strength-8
      and not(age>=31 or wants_out or n.monthly_salary>=coalesce(ct.monthly_salary,0)*1.5) then
    perform public.cw_neg_close(n.id,'rejected',public.mgr_player_name(n.player_id)||' considera '||public.mgr_club_name(n.buyer_club)||' pequeno para o momento da carreira.');
   end if;
  end if;
 end loop;
 perform public.cw_market_tick_before_v37(p_career);
end $function$;

CREATE OR REPLACE FUNCTION public.cw_attention(p_career uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date;own text;a jsonb;k text;ack text;
begin
 select w.today,c.club_id,r.attention_ack into d,own,ack from public.cw_world w
 join public.mgr_coach c using(career_id) left join public.cw_runtime r using(career_id) where w.career_id=p_career;
 select j into a from(
 select o.created_at ts,jsonb_build_object('id',o.id,'kind','job','expires_on',o.expires_on,'action','offers',
 'key','job:'||o.id||':'||o.negotiation_round||case when o.expires_on<=d+1 then ':deadline' else '' end) j
 from public.season_offers o where o.career_id=p_career and o.kind='coach' and o.status='pending' and o.expires_on>=d
 union all
 select n.created_on::timestamptz,jsonb_build_object('id',n.id,'kind','negotiation','expires_on',n.expires_on,'action','deals',
 'key','neg:'||n.id||':'||n.status||':'||n.round_no||case when n.expires_on<=d+1 then ':deadline' else '' end)
 from public.cw_negotiations n where n.career_id=p_career and n.expires_on>=d
 and (n.status in('seller_review','club_counter','player_counter')
  -- contratação aceita pelo atleta aguarda o clique em confirmar: o calendário para até o treinador decidir
  or (n.status='player_accepted' and n.buyer_club=own))
 and (n.initiator in('user','renewal') or n.seller_club=own)
 union all
 select w.today::timestamptz,jsonb_build_object('id',cc.career_id,'kind','coach_contract','expires_on',cc.contract_until,'action','contract',
 'key','contract:'||cc.contract_until||case when cc.contract_until<=d+1 then ':deadline' else '' end)
 from public.cw_coach cc join public.cw_world w using(career_id)
 where cc.career_id=p_career and own is not null and cc.contract_until between d and d+7
 union all
 select ct.starts_on::timestamptz,jsonb_build_object('id',ct.id,'kind','player_contract','expires_on',ct.expires_on,'action','contracts',
 'key','player-contract:'||ct.id||':'||ct.expires_on||case when ct.expires_on<=d+1 then ':deadline' else '' end)
 from public.cw_contracts ct where ct.career_id=p_career and ct.club_id=own and ct.status='active' and ct.expires_on between d and d+7
 and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=ct.player_id and n.status in('agreed','precontract'))
 )x where not exists(select 1 from public.cw_attention_acks a where a.career_id=p_career and a.decision_key=x.j->>'key') order by ts limit 1;
 if a is null then return null;end if;
 return a;
end $function$;

CREATE OR REPLACE FUNCTION public.career_world_advance(p_days integer, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare car public.careers;w public.cw_world;c public.mgr_coach;s public.career_seasons;prev jsonb;result jsonb;attention jsonb;
 started timestamptz:=clock_timestamp();from_date date;target date;next_date date;due date;boundary date;summary jsonb;n int:=0;stopped boolean:=false;ready boolean:=false;
begin
 car:=public.mgr_lock();
 if not(select enabled from public.cw_runtime_rules) then raise exception 'Calendário temporariamente pausado. Seu progresso está preservado';end if;
 if not public.cw_runtime_enabled(car.id) then return public.career_world_advance_before_v45(p_days,p_request);end if;
 if p_days is null or p_days<0 or p_days>(select max_days_per_call from public.cw_rules) then raise exception 'Quantidade de dias acima do limite por atualização';end if;
 prev:=public.cw_advance_receipt(car.id,p_request,p_days);if prev is not null then return prev;end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 select * into w from public.cw_world where career_id=car.id;from_date:=w.today;target:=w.today+p_days;
 loop
  n:=n+public.cw_simulate_due(car.id,24);
  select * into w from public.cw_world where career_id=car.id;
  select * into c from public.mgr_coach where career_id=car.id;
  select * into s from public.career_seasons where id=w.primary_season;
  -- Close a completed season before a new job interrupts time advancement.
  -- Otherwise an unemployed coach can receive successive offers forever without closing the year.
  if s.status='active' and not w.needs_sync
   and not exists(select 1 from public.season_fixtures where season_id=s.id and status='pending')
   and not exists(select 1 from public.season_competitions where season_id=s.id and status<>'finished') then
   summary:=public.mgr_season_end(s.id);select * into s from public.career_seasons where id=s.id;
  end if;
  attention:=public.cw_attention(car.id);exit when attention is not null;
  select min(d.due_on) into due from public.season_fixtures f join public.cw_fixture_dates d on d.fixture_id=f.id
   where f.season_id=w.primary_season and f.status='pending' and c.club_id in(f.home_club,f.away_club);
  stopped:=due<=w.today;
  ready:=s.status='finished' and w.today>=public.cw_start(s.region,s.year+1);
  exit when w.needs_sync or w.today>=target or coalesce(stopped,false) or ready
   -- Orçamento do lote: só encerra depois de algum progresso (dia ou jogo), senão o app recebe um lote vazio.
   or (clock_timestamp()-started>interval '2000 milliseconds' and (n>0 or w.today>from_date));
  next_date:=least(target,coalesce(due,target),w.today+(select market_interval from public.cw_runtime_rules),
   (date_trunc('month',w.today)+interval '1 month')::date,
   case when extract(day from w.today)<15 then date_trunc('month',w.today)::date+14 else (date_trunc('month',w.today)+interval '1 month')::date end);
  select min(reply_on) into boundary from public.cw_negotiations where career_id=car.id and status in('club_pending','player_pending') and reply_on>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select contract_until-7 into boundary from public.cw_coach where career_id=car.id and contract_until-7>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select contract_until-1 into boundary from public.cw_coach where career_id=car.id and contract_until-1>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on+1) into boundary from public.cw_contracts where career_id=car.id and status='active' and expires_on>=w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on-7) into boundary from public.cw_contracts where career_id=car.id and club_id=c.club_id and status='active' and expires_on-7>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on-1) into boundary from public.cw_contracts where career_id=car.id and club_id=c.club_id and status='active' and expires_on-1>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(register_on) into boundary from public.cw_negotiations where career_id=car.id and status in('agreed','precontract') and register_on>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on-1) into boundary from public.season_offers where career_id=car.id and kind='coach' and status='pending' and expires_on-1>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  select min(expires_on-1) into boundary from public.cw_negotiations where career_id=car.id and status in('seller_review','club_counter','player_counter','player_accepted') and expires_on-1>w.today;
  next_date:=least(next_date,coalesce(boundary,next_date));
  if s.status='finished' then next_date:=least(next_date,public.cw_start(s.region,s.year+1));end if;
  perform public.cw_step_to(car.id,next_date);
 end loop;
 select * into w from public.cw_world where career_id=car.id;
 if attention is null and not w.needs_sync and not exists(select 1 from public.season_fixtures where season_id=w.primary_season and status='pending') and (select status from public.career_seasons where id=w.primary_season)='active' then summary:=public.mgr_season_end(w.primary_season);end if;
 perform public.cw_recover_club(car.id,c.club_id);
 update public.cw_runtime set version=version+1 where career_id=car.id;
 result:=jsonb_build_object('today',w.today,'days',w.today-from_date,'days_remaining',greatest(0,target-w.today),'matches',n,
 'more',w.needs_sync and attention is null,'stopped_for_match',coalesce(stopped,false),'next_season_ready',ready,
 'stop_reason',case when attention is not null then 'decision_required' when stopped then 'match' when ready then 'season_boundary' else 'batch' end,
 'requires_attention',attention is not null,'attention',attention,'rounds','[]'::jsonb,'offers','[]'::jsonb,
 'season_finished',summary is not null,'season_summary',summary,'state_version',(select version from public.cw_runtime where career_id=car.id));
 insert into public.cw_operations(career_id,request_id,kind,parameters,result) values(car.id,p_request,'advance',jsonb_build_object('days',p_days),result);
 insert into public.cw_runtime_metrics(career_id,calls,total_ms,max_ms,matches,days)
 values(car.id,1,extract(epoch from(clock_timestamp()-started))*1000,extract(epoch from(clock_timestamp()-started))*1000,n,w.today-from_date)
 on conflict(career_id) do update set calls=cw_runtime_metrics.calls+1,total_ms=cw_runtime_metrics.total_ms+excluded.total_ms,max_ms=greatest(cw_runtime_metrics.max_ms,excluded.max_ms),matches=cw_runtime_metrics.matches+excluded.matches,days=cw_runtime_metrics.days+excluded.days;
 return result;
end $function$;
