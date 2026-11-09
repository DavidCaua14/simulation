-- Correções relatadas em 2026-11-09:
-- 1) salário acima da folga do teto: o excedente de 12 meses sai da verba de transferências;
-- 2) renovação: o atleta informa uma pedida fixa (bem acima do salário atual) e aceita quem a cobrir;
-- 3) metas de passagem iniciada na reta final da temporada não demitem o treinador;
-- 4) partidas mais difíceis: o adversário da IA joga com fator de concentração por nível de dificuldade;
-- 5) reservas sem minutos perdem moral bem mais rápido.
create table if not exists public.cw_renewal_asks(
 career_id uuid not null references public.careers(id) on delete cascade,
 player_id text not null,
 contract_id uuid not null,
 starts_on date not null,
 ask bigint not null,
 primary key(career_id,player_id));
alter table public.cw_renewal_asks enable row level security;
revoke all on public.cw_renewal_asks from public, anon, authenticated;
alter table public.career_difficulty_levels add column if not exists ai_match_mult numeric not null default 1;
update public.career_difficulty_levels set ai_match_mult=case id when 'easy' then 1.07 when 'normal' then 1.15 when 'hard' then 1.22 else ai_match_mult end;

-- ----------------------------------------------------------------------
-- 1) Teto salarial: excedente coberto pela verba de transferências (somente o clube do treinador)
-- ----------------------------------------------------------------------
create or replace function public.cw_wage_extra(p_id uuid)
 returns bigint language sql stable security definer set search_path to 'public' as $function$
 -- acréscimo mensal da folha que passa da folga do teto (0 para clubes da IA, que seguem o teto estrito)
 select case when n.buyer_club=(select c.club_id from public.mgr_coach c where c.career_id=n.career_id and c.status='employed')
   then greatest(0,coalesce(public.cw_neg_wage_increment(n.id),0)-greatest(0,public.cw_wage_room(n.career_id,n.buyer_club))) else 0 end
 from public.cw_negotiations n where n.id=p_id
$function$;

create or replace function public.cw_reserve_offer(p_id uuid)
 returns void language plpgsql security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare n public.cw_negotiations;needed bigint;available bigint;room bigint;inc bigint;extra bigint;
begin
 select * into n from public.cw_negotiations where id=p_id;
 inc:=coalesce(public.cw_neg_wage_increment(p_id),0);
 room:=public.cw_wage_room(n.career_id,n.buyer_club);
 extra:=coalesce(public.cw_wage_extra(p_id),0);
 if extra=0 and inc>0 and inc>room then
  raise exception 'O teto salarial do clube não comporta este salário (folga de %).',public.cw_money_label(greatest(0,room));
 end if;
 needed:=n.fee+n.signing_bonus+n.performance_bonus+extra*12;
 select public.cw_available_budget(n.career_id,n.buyer_club)+coalesce((select amount from public.cw_commitments where career_id=n.career_id and reference=n.id||':offer'),0) into available;
 if needed>available then
  if extra>0 then
   raise exception 'O salário passa a folga do teto em % por mês. Cobrir 12 meses desse excedente exige % da verba de transferências (disponível: %).',
    public.cw_money_label(extra),public.cw_money_label(needed),public.cw_money_label(greatest(0,available));
  end if;
  raise exception 'Verba de transferências insuficiente para taxa, luvas e bônus';
 end if;
 insert into public.cw_commitments(career_id,club_id,negotiation_id,kind,amount,due_on,reference)
 values(n.career_id,n.buyer_club,n.id,'offer',needed,n.expires_on,n.id||':offer')
 on conflict(career_id,club_id,reference) do update set amount=excluded.amount,status='reserved',due_on=excluded.due_on;
end $function$;

create or replace function public.cw_can_afford_contract(p_id uuid)
 returns boolean language plpgsql stable security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare n public.cw_negotiations;c public.cw_clubs;inc bigint;extra bigint;
begin
 select * into n from public.cw_negotiations where id=p_id;
 select * into c from public.cw_clubs where career_id=n.career_id and club_id=n.buyer_club;
 if c.club_id is null then return false;end if;
 inc:=coalesce(public.cw_neg_wage_increment(p_id),0);
 extra:=coalesce(public.cw_wage_extra(p_id),0);
 if extra=0 and inc>0 and inc>public.cw_wage_room(n.career_id,n.buyer_club) then return false;end if;
 return c.cash-public.cw_reserved(n.career_id,n.buyer_club)
   +coalesce((select amount from public.cw_commitments where career_id=n.career_id and reference=n.id||':offer' and status='reserved'),0)
  >=n.fee+n.signing_bonus+n.performance_bonus+extra*12;
end $function$;
CREATE OR REPLACE FUNCTION public.cw_register_transfer(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- cm69: registro imediato
#variable_conflict use_column
declare v_extra bigint;n public.cw_negotiations;own text;d date;region text;b record;next_date date;legacy boolean;result boolean;reason text;
begin
 select career_id into n.career_id from public.cw_negotiations where id=p_id;
 if n.career_id is null then return false;end if;
 perform 1 from public.careers where id=n.career_id for update;
 select * into n from public.cw_negotiations where id=p_id for update;
 if n.status='completed' then return true;end if;
 if n.status not in('agreed','precontract') then return false;end if;
 select today into d from public.cw_world where career_id=n.career_id;
 if n.register_on>d then return false;end if;
 select club_id into own from public.mgr_coach where career_id=n.career_id and status='employed';
 region:=public.cw_region(n.buyer_club);
 if n.initiator='renewal' and not public.cw_valid_renewal(n.career_id,n.player_id,n.buyer_club,d) then
  perform public.cw_neg_close(n.id,'rejected','A renovação exige atleta e contrato vigentes do próprio clube.');return false;
 end if;
 -- Registration always waits for the buyer's window, including free agents, AI and old pre-contracts.
 -- Defer before reassessing the deal: approved agreements do not expire merely because the window closed.
 if false then
  next_date:=public.cw_next_window(region,d);
  update public.cw_negotiations set register_on=next_date,response='Acordo preservado. O registro aguarda a próxima janela disponível: '||to_char(next_date,'DD/MM/YYYY')||'.' where id=n.id;
  update public.cw_commitments set due_on=next_date where negotiation_id=n.id and kind='offer' and status='reserved';
  return false;
 end if;
 legacy:=exists(select 1 from public.cw_market_legacy_agreements where negotiation_id=n.id);
 if not legacy then
  reason:=public.cw_project_reason(n.career_id,n.player_id,n.buyer_club);
  if reason is not null then perform public.cw_neg_close(n.id,'rejected',reason);return false;end if;
  if n.monthly_salary<public.cw_salary_demand(n.career_id,n.player_id,n.buyer_club)
   or(n.seller_club is null and n.initiator<>'renewal' and n.signing_bonus<public.cw_minimum_signing(n.career_id,n.player_id,n.buyer_club)) then
   perform public.cw_neg_close(n.id,'rejected','Os termos não atendem ao salário e às luvas exigidos pelo atleta.');return false;
  end if;
  if not public.cw_can_afford_contract(n.id) then
   perform public.cw_neg_close(n.id,'failed_funds','O clube não consegue sustentar taxa, luvas, dívidas e seis meses do acréscimo da folha.');return false;
  end if;
 end if;
 if n.initiator<>'renewal' then
  if false then
   select * into b from public.cw_transfer_window(region,d);
   next_date:=public.cw_next_window(region,b.ends_on+1);
  end if;
  if next_date is not null then
   update public.cw_negotiations set register_on=next_date,response='Acordo preservado. O registro aguarda a próxima janela disponível: '||to_char(next_date,'DD/MM/YYYY')||'.' where id=n.id and register_on is distinct from next_date;
   update public.cw_commitments set due_on=next_date where negotiation_id=n.id and kind='offer' and status='reserved';
   return false;
  end if;
 end if;
 v_extra:=coalesce(public.cw_wage_extra(p_id),0); -- calculado antes de o novo contrato entrar na folha
 result:=public.cw_register_transfer_before_v39(p_id);
 if result and v_extra>0 then
  perform public.cw_cash(n.career_id,n.buyer_club,-v_extra*12,'wage_reallocation',n.id::text,'Verba de transferências realocada para a folha (12 meses do excedente do teto)',true);
  update public.cw_clubs set wage_budget=wage_budget+v_extra where career_id=n.career_id and club_id=n.buyer_club and wage_budget is not null;
 end if;
 if result and n.initiator<>'renewal' and n.buyer_club=own then
  insert into public.cw_transfer_registrations(career_id,negotiation_id,player_id,buyer_club,registered_on)
   values(n.career_id,n.id,n.player_id,n.buyer_club,d) on conflict do nothing;
 end if;
 return result;
end $function$
;

-- ----------------------------------------------------------------------
-- 2) Renovação com pedida fixa
-- ----------------------------------------------------------------------
create or replace function public.cw_renewal_ask(p_career uuid, p_player text, p_club text)
 returns bigint language plpgsql security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare ct public.cw_contracts;v_ask bigint;
begin
 select * into ct from public.cw_contracts where career_id=p_career and player_id=p_player and club_id=p_club and status='active' limit 1;
 if not found then return null;end if;
 select a.ask into v_ask from public.cw_renewal_asks a where a.career_id=p_career and a.player_id=p_player and a.contract_id=ct.id and a.starts_on=ct.starts_on;
 if v_ask is not null then return v_ask;end if;
 -- valorização de 30% a 55% sobre o salário atual (sorteio estável por contrato), nunca abaixo do piso do atleta
 v_ask:=ceil(greatest(public.cw_salary_floor(p_player),ct.monthly_salary)
  *(1.30+.25*(('x'||substr(md5(ct.id::text||ct.starts_on::text),1,6))::bit(24)::int/16777215.0)))::bigint;
 insert into public.cw_renewal_asks(career_id,player_id,contract_id,starts_on,ask) values(p_career,p_player,ct.id,ct.starts_on,v_ask)
 on conflict(career_id,player_id) do update set contract_id=excluded.contract_id,starts_on=excluded.starts_on,ask=excluded.ask;
 return v_ask;
end $function$;
CREATE OR REPLACE FUNCTION public.cw_salary_demand(p_career uuid, p_player text, p_buyer text)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare wage bigint;source_club text;prestige numeric;buyer_prestige numeric;
begin
 -- renovação: vale a pedida informada pelo atleta ao clube atual
 select a.ask into wage from public.cw_renewal_asks a join public.cw_contracts c on c.career_id=a.career_id and c.player_id=a.player_id
  and c.id=a.contract_id and c.starts_on=a.starts_on and c.club_id=p_buyer and c.status='active'
 where a.career_id=p_career and a.player_id=p_player limit 1;
 if wage is not null then return wage;end if;
 select monthly_salary,club_id into wage,source_club from public.cw_contracts where career_id=p_career and player_id=p_player
 order by(status='active') desc,starts_on desc,id limit 1;
 select coalesce(source_club,club_id) into source_club from public.sim_players where id=p_player;
 select coalesce((select c.prestige from public.cw_clubs c where c.career_id=p_career and c.club_id=source_club),(select strength from public.sim_clubs where id=source_club),0) into prestige;
 select coalesce((select c.prestige from public.cw_clubs c where c.career_id=p_career and c.club_id=p_buyer),(select strength from public.sim_clubs where id=p_buyer),0) into buyer_prestige;
 return ceil(greatest(public.cw_salary_floor(p_player),coalesce(wage,0)*case when source_club=p_buyer then 1.08 else 1.12 end)
  *(1+least(.75,greatest(0,prestige-buyer_prestige)*.025)))::bigint;
end $function$
;
CREATE OR REPLACE FUNCTION public.career_wage_demand(p_player text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;own text;
begin
 car:=public.mgr_lock();
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 if own is not null then perform public.cw_renewal_ask(car.id,p_player,own);end if;
 return jsonb_build_object('weekly_demand',public.cw_weekly(public.cw_salary_demand(car.id,p_player,own)),
  'max_years',(select max_contract_years from public.cw_rules),'reason',public.cw_project_reason(car.id,p_player,own));
end $function$
;
CREATE OR REPLACE FUNCTION public.career_contract_renew(p_player text, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;cid uuid;own text;car public.careers;d date;reason text;prev jsonb;
begin
 car:=public.mgr_lock();cid:=car.id;
 prev:=public.econ_request_get(cid,p_request,'contract_renew');if prev is not null then return prev||jsonb_build_object('salary_demand',public.cw_salary_demand(cid,p_player,car.club_id));end if;
 select club_id into own from public.mgr_coach where career_id=cid and status='employed';
 select today into d from public.cw_world where career_id=cid;
 if not public.cw_valid_renewal(cid,p_player,own,d) then raise exception 'Só é possível renovar um contrato vigente de um atleta que ainda pertence ao seu clube.';end if;
 reason:=public.cw_project_reason(cid,p_player,own);
 if reason is not null then raise exception 'O atleta recusou a renovação: % O contrato atual continua válido até o vencimento.',reason;end if;
 perform public.cw_renewal_ask(cid,p_player,own);
 r:=public.career_contract_renew_before_v54(p_player,p_request);
 return r||jsonb_build_object('salary_demand',public.cw_salary_demand(cid,p_player,own));
end $function$
;
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
   -- renovação: a pedida foi informada; cobrindo-a, o atleta aceita
   update public.cw_negotiations set status='player_accepted',expires_on=public.cw_deadline(d),
    response=format('Aceito sua oferta de %s por semana por %s ano(s). Se estiver de acordo, confirme e meu agente cuida da papelada.',public.cw_money_label(public.cw_weekly(n.monthly_salary)),n.contract_years) where id=n.id;
   perform public.cw_neg_history(n.id,'player','O atleta aceitou a renovação; aguardando a confirmação do treinador.');
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
end $function$
;

-- ----------------------------------------------------------------------
-- 3) Fim de temporada: metas de passagem recente não contam
-- ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mgr_season_end(p_season uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_s     public.career_seasons;
  v_c     public.mgr_coach;
  r       record;
  v_sum   jsonb;
  v_pos   int;
  v_best  int;
  v_met   int := 0;
  v_fail  int := 0;
  v_major boolean := false;
  v_db    numeric := 0;
  v_dp    record;   -- perfil de dificuldade em vigor (evolução 05: public.mgr_difficulty)
  v_dr    numeric := 0;
  v_n     int;
  v_i     int;
  v_league_fire boolean := false; -- Fase 4: a meta da liga decide a demissão
  v_coins int := 0;
  v_titles int := 0;
  v_rw    jsonb := '[]'::jsonb;
  v_rep_before numeric;
  v_rr    public.cw_season_reward_rules;
begin
  select * into v_s from public.career_seasons where id = p_season for update;
  select * into v_rr from public.cw_season_reward_rules;
  if v_s.status <> 'active' then return v_s.summary; end if;
  for r in select competition_id from public.season_competitions where season_id = p_season and status <> 'finished' loop
    perform public.sim_complete_competition(p_season, r.competition_id);
  end loop;
  select * into v_c from public.mgr_coach where career_id = v_s.career_id;

  -- metas de outra passagem ou de passagem iniciada nesta temporada com menos de 10 jogos não são cobradas
  update public.mgr_objectives o set status = 'void'
   where o.season_id = p_season and o.status = 'open'
     and (o.spell_id is distinct from v_c.spell_id or v_c.status <> 'employed'
          or exists (select 1 from public.mgr_spells sp where sp.id = o.spell_id and sp.started_season = v_s.season_no and sp.matches < 10));
  -- objetivos da passagem atual
  for r in select * from public.mgr_objectives where season_id = p_season and status = 'open' loop
    if r.kind = 'league_pos' then
      select t.pos into v_pos from public.sim_standings(p_season, r.competition_id, null) t where t.club_id = r.club_id;
      if v_pos > r.target + v_rr.dismissal_tolerance then v_league_fire := true; end if;
      if v_pos <= r.target then
        v_coins := v_coins + v_rr.league_coins_per_priority * r.priority + v_rr.league_coins_per_place * greatest(0, r.target - v_pos);
        v_rw := v_rw || jsonb_build_object('kind', 'league', 'competition', r.competition_id, 'label', r.label, 'pos', v_pos, 'target', r.target,
          'coins', v_rr.league_coins_per_priority * r.priority + v_rr.league_coins_per_place * greatest(0, r.target - v_pos));
      end if;
      if v_pos <= r.target then
        update public.mgr_objectives set status = 'met' where id = r.id; v_met := v_met + 1; v_db := v_db + 4 * r.priority; v_dr := v_dr + 1.5 * r.priority;
      else
        update public.mgr_objectives set status = 'failed' where id = r.id; v_fail := v_fail + 1;
        if v_pos <= r.target + 2 then v_db := v_db - r.priority; v_dr := v_dr - 0.3 * r.priority;      -- ficou perto
        else v_db := v_db - 4 * r.priority; v_dr := v_dr - 1.2 * r.priority;
          if r.priority >= 3 and v_pos > r.target + 3 then v_major := true; end if;
        end if;
      end if;
      -- campanha no campeonato nacional também conta para a reputação
      v_dr := v_dr + case when v_pos = 1 then 0 when v_pos <= 4 then 4 when v_pos <= 8 then 2
                          when v_pos > (select count(*) from public.season_participants where season_id = p_season and competition_id = r.competition_id) - 4 then -6
                          else 0 end;
    else
      v_best := public.mgr_best_stage(p_season, r.competition_id, r.club_id);
      if v_best >= r.target then
        update public.mgr_objectives set status = 'met' where id = r.id; v_met := v_met + 1; v_db := v_db + 3 * r.priority; v_dr := v_dr + r.priority;
        v_coins := v_coins + v_rr.cup_coins_per_priority * r.priority;
        v_rw := v_rw || jsonb_build_object('kind', 'cup', 'competition', r.competition_id, 'label', r.label, 'coins', v_rr.cup_coins_per_priority * r.priority);
      else
        update public.mgr_objectives set status = 'failed' where id = r.id; v_fail := v_fail + 1;
        if v_best >= r.target - 1 then v_db := v_db - r.priority; v_dr := v_dr - 0.3 * r.priority;
        else v_db := v_db - 3 * r.priority; v_dr := v_dr - 0.8 * r.priority; end if;
      end if;
    end if;
  end loop;

  select jsonb_agg(jsonb_build_object(
           'competition', sc.competition_id, 'champion', sc.champion_club, 'runner_up', sc.runner_up_club,
           'player_result', sc.player_result, 'player_club', sc.player_club,
           'bonus_xp', sc.player_bonus_xp, 'bonus_coins', sc.player_bonus_coins)
         order by sc.competition_id)
    into v_sum from public.season_competitions sc where sc.season_id = p_season;
  v_sum := jsonb_build_object('competitions', coalesce(v_sum, '[]'::jsonb), 'objectives_met', v_met, 'objectives_failed', v_fail,
                              'coach_club', v_c.club_id, 'coach_status', v_c.status);

  -- acesso, rebaixamento e vagas continentais da próxima temporada (aplicado uma única vez)
  v_sum := v_sum || jsonb_build_object('transition', public.sim_season_transition(p_season));
  update public.career_seasons set status = 'finished', finished_at = now(), summary = v_sum where id = p_season;
  -- Prêmio de fim de temporada (Fase 4): moedas pela meta superada e por título, uma vez por temporada;
  -- reputação da temporada com teto de +6 (cada ponto vale 15 no rank).
  if v_c.status = 'employed' then
    select count(*) into v_titles from public.season_competitions where season_id = p_season and champion_club = v_c.club_id;
    v_coins := v_coins + v_rr.title_coins * v_titles;
    v_dr := v_dr + v_rr.title_reputation * v_titles;
  end if;
  v_dr := least(v_dr, v_rr.reputation_cap);
  v_rep_before := v_c.reputation;
  v_dp := public.mgr_difficulty(v_s.career_id);   -- lido ANTES de contar a temporada (o perfil vale até o fim dela)
  if v_db < 0 then v_db := v_db * v_dp.board_loss_mult; end if;
  update public.mgr_coach set seasons = seasons + 1,
         board_confidence = round(greatest(0, least(100, board_confidence + v_db)), 2),
         reputation = round(greatest(0, least(100, reputation + v_dr)), 2)
   where career_id = v_s.career_id returning * into v_c;

  if v_c.status = 'employed' then
    insert into public.cw_season_rewards(season_id, career_id, club_id, coins, reputation, detail)
    values (p_season, v_s.career_id, v_c.club_id, v_coins, round(v_c.reputation - v_rep_before, 2),
            jsonb_build_object('items', v_rw, 'titles', v_titles, 'title_coins', v_rr.title_coins * v_titles, 'objectives_met', v_met, 'objectives_failed', v_fail, 'year', v_s.year))
    on conflict (season_id) do nothing;
    if found and v_coins > 0 then perform public.econ_apply(v_s.career_id, 'coins', v_coins, 'season_reward', p_season::text); end if;
    if v_league_fire then
      perform public.mgr_fire(v_s.career_id, 'objetivo da temporada não cumprido');
    else
      perform public.mgr_msg(v_s.career_id, p_season, v_s.day_no, 'board', 'Balanço da temporada ' || v_s.year,
        case when v_met + v_fail = 0 then 'Você assumiu o clube na reta final: as metas desta temporada não foram cobradas. A avaliação começa na próxima.'
             when v_fail = 0 then 'Objetivos cumpridos. A diretoria está satisfeita e conta com você na próxima temporada.'
             when v_met > 0 then format('%s objetivo(s) cumprido(s) e %s não. A diretoria espera evolução.', v_met, v_fail)
             else 'Temporada abaixo do esperado. A cobrança vai aumentar.' end, v_c.club_id);
    end if;
  end if;

  -- janela de propostas do fim de temporada
  select * into v_c from public.mgr_coach where career_id = v_s.career_id;
  v_n := case when v_c.status = 'unemployed' then 2 else least(2, floor(v_c.reputation / 35)::int + (case when random() < 0.4 then 1 else 0 end)) end;
  for v_i in 1 .. v_n loop
    perform public.mgr_make_offer(v_s.career_id, p_season, v_s.day_no, v_c.status = 'unemployed', true);
  end loop;
  return v_sum;
end;
$function$
;

-- ----------------------------------------------------------------------
-- 4) Dificuldade das partidas
-- ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cw_cm_match_prepare(p_fixture bigint, p_career uuid, p_user_side character)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare m public.mgr_matches;f public.season_fixtures;sd text;club text;spr public.cw_set_pieces;
 fk jsonb:='{}';ck jsonb:='{}';form numeric[];spb numeric[];drills jsonb:='{}';k text;
begin
 select * into m from public.mgr_matches where fixture_id=p_fixture for update;
 if not found or coalesce((m.state->>'cm64')::boolean,false) or m.minute>0 then return;end if;
 select * into f from public.season_fixtures where id=p_fixture;
 form:=array[coalesce((m.state->'form'->>0)::numeric,1),coalesce((m.state->'form'->>1)::numeric,1)];
 spb:=array[coalesce((m.state->'sp_bonus'->>0)::numeric,0),coalesce((m.state->'sp_bonus'->>1)::numeric,0)];
 foreach sd in array array['h','a'] loop
  club:=case when sd='h' then f.home_club else f.away_club end;
  spr:=null;
  select * into spr from public.cw_set_pieces where career_id=p_career and club_id=club;
  -- batedor de falta: o escolhido; senão, o melhor em finalização+criação em campo
  fk:=fk||jsonb_build_object(sd,coalesce(
   (select player_id from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and player_id=spr.free_kick),
   (select player_id from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and pos<>'GOL' order by c_fin+c_cre desc limit 1)));
  ck:=ck||jsonb_build_object(sd,coalesce(
   (select player_id from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and player_id=spr.corner),
   (select player_id from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and pos<>'GOL' order by c_cre desc limit 1)));
  if spr.captain is not null and exists(select 1 from public.mgr_match_players where fixture_id=p_fixture and side=sd and status='on' and player_id=spr.captain) then
   form[case when sd='h' then 1 else 2 end]:=form[case when sd='h' then 1 else 2 end]*1.02;
  end if;
 end loop;
 -- insatisfação no elenco do treinador derruba o rendimento do time
 if p_user_side in('h','a') then
  form[case when p_user_side='h' then 1 else 2 end]:=form[case when p_user_side='h' then 1 else 2 end]
   *coalesce((public.cw_squad_unrest(p_career,case when p_user_side='h' then f.home_club else f.away_club end)->>'factor')::numeric,1);
 end if;
 -- dificuldade: o adversário da IA entra mais concentrado contra o time do treinador
 if p_user_side in('h','a') then
  form[case when p_user_side='h' then 2 else 1 end]:=form[case when p_user_side='h' then 2 else 1 end]
   *coalesce((public.cw_difficulty_level(p_career)).ai_match_mult,1);
 end if;
 -- exercícios pré-jogo só valem para o time do treinador e gastam um jogo cada
 if p_user_side in('h','a') then
  for k in select kind from public.cw_match_boosts where career_id=p_career and games_left>0 for update loop
   drills:=drills||jsonb_build_object(k,true);
   if k='shooting' then update public.mgr_match_players set c_fin=c_fin*1.06,c_att=c_att*1.03 where fixture_id=p_fixture and side=p_user_side;
   elsif k='passing' then update public.mgr_match_players set c_cre=c_cre*1.06,c_ctl=c_ctl*1.04 where fixture_id=p_fixture and side=p_user_side;
   elsif k='penalty' then spb[case when p_user_side='h' then 1 else 2 end]:=spb[case when p_user_side='h' then 1 else 2 end]+0.06;
   elsif k='blocking' then update public.mgr_match_players set c_gk=c_gk*1.06,c_def=c_def*1.03 where fixture_id=p_fixture and side=p_user_side;
   elsif k='tackling' then update public.mgr_match_players set c_tack=c_tack*1.08,c_def=c_def*1.03 where fixture_id=p_fixture and side=p_user_side;
   end if;
  end loop;
  update public.cw_match_boosts set games_left=games_left-1,updated_at=now() where career_id=p_career and games_left>0;
 end if;
 update public.mgr_matches set state=state||jsonb_build_object('cm64',true,'fk_taker',fk,'ck_taker',ck,'form',to_jsonb(form),
  'sp_bonus',to_jsonb(spb),'drills',drills) where fixture_id=p_fixture;
end $function$
;

-- ----------------------------------------------------------------------
-- 5) Moral de quem não joga
-- ----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cw_market_tick_before_v37(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- cm69: registro imediato
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;threshold numeric;interest numeric;buyer public.cw_clubs;seller public.cw_clubs;
 r record;c public.cw_clubs;p record;id uuid;value bigint;cnt int;expected numeric;apps int;games int;new_morale numeric;paid bigint;user_region text;depth jsonb;style text;
begin
 select today into d from public.cw_world where career_id=p_career;
 if extract(doy from d)=1 then update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or player_id in(select player_id from public.mgr_players where career_id=p_career and club_id in (select public.cw_domestic_clubs(p_career))));end if;
 select club_id into own from public.mgr_coach where career_id=p_career;
 for id in select x.id from public.cw_negotiations x where x.career_id=p_career and x.status='player_accepted' and x.expires_on<d loop
  perform public.cw_neg_close(id,'expired','O prazo para confirmar terminou e o atleta seguiu outro caminho.');
 end loop;
 for n in select * from public.cw_negotiations where career_id=p_career and status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract') order by created_on,id for update loop
  if n.status in('agreed','precontract') then perform public.cw_register_transfer(n.id);continue;end if;
  if n.expires_on<d then perform public.cw_neg_close(n.id,'expired','Prazo da proposta encerrado.');continue;end if;
  if n.reply_on>d or n.status in('seller_review','club_counter','player_counter') then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=n.player_id and status='active';
  select * into buyer from public.cw_clubs where career_id=p_career and club_id=n.buyer_club;
  select * into seller from public.cw_clubs where career_id=p_career and club_id=n.seller_club;
  if n.status='club_pending' then
   select count(*) into cnt from public.mgr_players where career_id=p_career and club_id=n.seller_club;
   threshold:=n.valuation*(case when seller.financial_risk>=50 then .85 else 1.05 end)+n.valuation*case when ct.role='key' then .35 else .05 end;
   threshold:=threshold*(.9+n.decision_roll*.3)*case when ct.expires_on<d+180 then .65 else 1 end;
   if exists(select 1 from public.cw_rivalries rv where rv.club_a=least(n.buyer_club,n.seller_club) and rv.club_b=greatest(n.buyer_club,n.seller_club)) then threshold:=threshold*1.12;end if;
   threshold:=threshold*(1+least(.20,.04*(select count(*) from public.cw_negotiations z where z.career_id=p_career and z.player_id=n.player_id and z.id<>n.id and z.status in('club_pending','player_pending','seller_review'))));
   if n.seller_club is null or n.register_on>coalesce(ct.expires_on,d+999) then threshold:=0;end if;
   if (cnt<=18 and threshold>0) or n.decision_roll<.04 then
    perform public.cw_neg_close(n.id,'rejected','O clube considera o atleta indispensável ou não tem reposição.');
   elsif n.fee+n.performance_bonus*.5<threshold then
    if n.round_no>=2 or n.fee<threshold*.55 then perform public.cw_neg_close(n.id,'rejected','Os valores não atendem à avaliação do clube.');
    else
     update public.cw_negotiations set status='club_counter',fee=ceil(threshold),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O clube pede uma revisão do valor.' where id=n.id;
     if n.initiator='ai' then perform public.cw_neg_close(n.id,'rejected','O comprador desistiu da contraproposta.');else perform public.cw_neg_history(n.id,'seller','Contraproposta do clube vendedor.');end if;
    end if;
   else
    update public.cw_negotiations set status='player_counter',response='Clube de acordo. Apresente salário, duração, luvas e papel ao atleta.',expires_on=public.cw_deadline(d) where id=n.id;
    if n.initiator='ai' then
     update public.cw_negotiations set status='player_pending',monthly_salary=public.cw_salary_demand(p_career,n.player_id,n.buyer_club),contract_years=3,signing_bonus=ceil(n.valuation*.02),reply_on=d+2 where id=n.id;
    end if;
    perform public.cw_neg_history(n.id,'seller','Condições entre clubes aprovadas.');
   end if;
  elsif n.status='player_pending' then
   interest:=coalesce(public.cw_contract_cost(ct.player_id,ct.monthly_salary,ct.appearance_bonus,ct.goal_bonus,ct.role),greatest(40,n.valuation*.0065))*case when buyer.prestige>=coalesce(seller.prestige,0)+5 then 1.02 else 1.12 end;
   interest:=interest*(1+greatest(0,coalesce(seller.prestige,0)-buyer.prestige)*.015);
   interest:=interest*case when (select morale from public.cw_players where career_id=p_career and player_id=n.player_id)<35 and n.initiator='renewal' then 1.35 else 1 end;
   interest:=interest*case when n.role='prospect' and coalesce(ct.role,'rotation') in('key','starter') then 1.35 else 1 end;
   if n.decision_roll<.06 and buyer.prestige<coalesce(seller.prestige,0) then
    perform public.cw_neg_close(n.id,'rejected','O atleta recusou o projeto esportivo, independentemente da remuneração.');continue;
   end if;
   if (public.cw_contract_cost(n.player_id,n.monthly_salary,n.appearance_bonus,n.goal_bonus,n.role)+n.signing_bonus/greatest(12*n.contract_years,1))<interest then
    if n.round_no>=3 or n.monthly_salary<interest*.65 then perform public.cw_neg_close(n.id,'rejected','O atleta recusou salário, papel ou projeto esportivo.');
    else update public.cw_negotiations set status='player_counter',monthly_salary=ceil(interest),round_no=round_no+1,expires_on=public.cw_deadline(d),response='O atleta pede melhores condições salariais.' where id=n.id;perform public.cw_neg_history(n.id,'player','Contraproposta salarial do atleta.');end if;
   elsif exists(select 1 from public.cw_negotiations where career_id=p_career and player_id=n.player_id and id<>n.id and status in('agreed','precontract')) then
    perform public.cw_neg_close(n.id,'rejected','O atleta já assinou um acordo.');
   else
    if n.buyer_club=own and n.initiator in('user','renewal') then
     update public.cw_negotiations set status='player_accepted',expires_on=public.cw_deadline(d),
      response=format('Aceito sua oferta de %s por semana por %s ano(s). Se estiver de acordo, confirme e meu agente cuida da papelada.',public.cw_money_label(public.cw_weekly(n.monthly_salary)),n.contract_years) where id=n.id;
     perform public.cw_neg_history(n.id,'player','O atleta aceitou; aguardando a confirmação do treinador.');
     continue;
    end if;
    begin
     perform public.cw_reserve_offer(n.id);
     update public.cw_negotiations set status=case when n.register_on is not null then 'precontract' else 'agreed' end,response='Ambas as partes aprovaram. Aguardando registro.',register_on=coalesce(n.register_on,d) where id=n.id;
     perform public.cw_neg_history(n.id,'player','Condições do atleta aprovadas.');perform public.cw_register_transfer(n.id);
    exception when raise_exception then perform public.cw_neg_close(n.id,'failed_funds',sqlerrm);end;
   end if;
  end if;
 end loop;
 -- Scheduled transfer liabilities are paid once; performance clauses require ten actual appearances.
 for r in select cm.*,n.player_id,n.seller_club,n.register_on from public.cw_commitments cm join public.cw_negotiations n on n.id=cm.negotiation_id
  where cm.career_id=p_career and cm.status='reserved' and n.status='completed' and cm.kind in('installment','performance') order by cm.due_on,cm.id loop
  if r.kind='performance' then
   select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=r.player_id and mp.club_id=r.club_id and mp.minutes>0 and mp.on_date>=r.register_on;
   if apps<10 and d<r.due_on then continue;end if;
   if apps<10 then update public.cw_commitments set status='released' where id=r.id;continue;end if;
  elsif r.due_on>d then continue;end if;
  perform public.cw_cash(p_career,r.club_id,-r.amount,'transfer_clause',r.id::text,'Parcela ou bônus da contratação',true);
  if r.seller_club is not null then perform public.cw_cash(p_career,r.seller_club,r.amount,'player_sale_clause',r.id::text,'Recebimento de parcela ou bônus');end if;
  update public.cw_commitments set status='paid' where id=r.id;
 end loop;
 -- Moral (CM17) em lote: mesma regra de cw_cm_morale_next, calculada uma vez por clube em vez de por atleta.
 update public.cw_players xcp set last_morale_on=d
  from public.mgr_players xmp, public.cw_contracts xct
  where xcp.career_id=p_career and xmp.career_id=xcp.career_id and xmp.player_id=xcp.player_id
   and xct.career_id=xcp.career_id and xct.player_id=xcp.player_id and xct.status='active' and d-xct.starts_on<28
   and (not (select public.cw_runtime_enabled(p_career)) or xmp.club_id in (select public.cw_domestic_clubs(p_career)) or xmp.club_id=own)
   and (xcp.last_morale_on is null or xcp.last_morale_on<=d-7);
 with m_elig as materialized(
  select distinct on (xcp.player_id) xcp.player_id m_player,xcp.morale m_morale,xmp.club_id m_club,xct.arrears m_arrears
  from public.cw_players xcp join public.mgr_players xmp on xmp.career_id=xcp.career_id and xmp.player_id=xcp.player_id
  join public.cw_contracts xct on xct.career_id=xcp.career_id and xct.player_id=xcp.player_id and xct.status='active'
  where xcp.career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or xmp.club_id in (select public.cw_domestic_clubs(p_career)) or xmp.club_id=own)
   and (xcp.last_morale_on is null or xcp.last_morale_on<=d-7) and d-xct.starts_on>=28
  order by xcp.player_id),
 m_clubs as materialized(select distinct m_club from m_elig),
 m_res as(
  select xfd.club_id m_club,count(*) m_games,
   count(*) filter(where xfd.due_on>=d-7 and ((xf.home_club=xfd.club_id and xf.home_goals>xf.away_goals) or (xf.away_club=xfd.club_id and xf.away_goals>xf.home_goals))) m_w,
   count(*) filter(where xfd.due_on>=d-7 and ((xf.home_club=xfd.club_id and xf.home_goals<xf.away_goals) or (xf.away_club=xfd.club_id and xf.away_goals<xf.home_goals))) m_l
  from public.cw_club_dates xfd join public.season_fixtures xf on xf.id=xfd.fixture_id
  where xfd.career_id=p_career and xfd.club_id in(select m_club from m_clubs) and xf.status='played' and xfd.due_on between d-28 and d
  group by xfd.club_id),
 m_ap as(
  select xa.player_id m_player,xa.club_id m_club,count(*) m_apps from public.cw_appearances xa
  where xa.career_id=p_career and xa.player_id in(select m_player from m_elig) and xa.minutes>=30 and xa.on_date between d-28 and d
  group by 1,2),
 m_rk as(
  select xmp.player_id m_player,rank() over(partition by xmp.club_id order by xpr.rating+coalesce(xdv.d_rating,0) desc,xmp.player_id) m_rank
  from public.mgr_players xmp join public.sim_players xsp on xsp.id=xmp.player_id
  join public.sim_player_pos_ratings xpr on xpr.player_id=xsp.id and xpr.pos=xsp.position
  left join public.cw_player_dev xdv on xdv.career_id=xmp.career_id and xdv.player_id=xmp.player_id
  where xmp.career_id=p_career and xmp.club_id in(select m_club from m_clubs)),
 m_base as(
  select e.m_player,e.m_morale,e.m_arrears,coalesce(rs.m_games,0) m_games,coalesce(ap.m_apps,0) m_apps,coalesce(rs.m_w,0) m_w,coalesce(rs.m_l,0) m_l,
   case when coalesce(rk.m_rank,30)<=11 then .60 when coalesce(rk.m_rank,30)<=16 then .30 else .10 end m_exp
  from m_elig e left join m_res rs on rs.m_club=e.m_club left join m_ap ap on ap.m_player=e.m_player and ap.m_club=e.m_club
  left join m_rk rk on rk.m_player=e.m_player),
 m_calc as(
  select b.m_player,b.m_morale,
   greatest(0,least(100,b.m_morale
    +case when b.m_games>=3 then
          case when b.m_apps::numeric/b.m_games>=b.m_exp then greatest(1,least(6,round(10*(b.m_apps::numeric/b.m_games-b.m_exp))))
               -- abaixo do esperado: de -2 a -8 por semana conforme a falta de minutos
               else -(2+round(6*(b.m_exp-b.m_apps::numeric/b.m_games)/b.m_exp)) end
     else case when b.m_morale<60 then 1 when b.m_morale>70 then -1 else 0 end end
    -- quem não entrou em campo quase não se anima com as vitórias do time
    +case when b.m_games>=3 and b.m_apps=0 then least(1,greatest(-4,least(4,2*b.m_w-2*b.m_l))) else greatest(-4,least(4,2*b.m_w-2*b.m_l)) end
    -case when coalesce(b.m_arrears,0)>0 then 8 else 0 end)) m_new
  from m_base b)
 update public.cw_players xcp set morale=mc.m_new,morale_trend=sign(mc.m_new-mc.m_morale)::smallint,last_morale_on=d,transfer_requested=false,last_warning_on=null
  from m_calc mc where xcp.career_id=p_career and xcp.player_id=mc.m_player;
 -- Alvos realistas (evolução 40): pilares (3 melhores de cada clube) não são alvo, e atletas com menos de 32 anos
 -- não são procurados por clubes de divisão inferior à deles. Calculado uma vez por dia.
 create temp table if not exists _cw_pillars(player_id text primary key) on commit drop;
 create temp table if not exists _cw_levels(club_id text primary key,lvl int not null) on commit drop;
 truncate _cw_pillars;truncate _cw_levels;
 insert into _cw_pillars select x.player_id from(select mp.player_id,row_number() over(partition by mp.club_id order by r.rating desc,mp.player_id) rk
  from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  where mp.career_id=p_career and mp.club_id is not null) x where x.rk<=3 on conflict do nothing;
 insert into _cw_levels select c.id,public.cw_club_level(c.id) from public.sim_clubs c on conflict do nothing;
 -- One AI decision per club/date, with budgets and squad needs. User sales always await explicit approval.
 for c in select * from public.cw_clubs where career_id=p_career and club_id is distinct from own and (not (select public.cw_runtime_enabled(p_career)) or club_id in (select public.cw_domestic_clubs(p_career))) order by club_id loop
  insert into public.cw_ai_days values(p_career,c.club_id,d) on conflict do nothing;if not found then continue;end if;
  -- Janela fechada: só atletas livres (como na vida real). Elenco acima do limite + 6 não compra.
  if c.financial_risk>=75 or random()>public.cw_tick_probability((select ai_bid_chance from public.cw_rules))*(case when public.cw_window_open(public.cw_region(c.club_id),d) then 1 else .35 end)
     or public.cw_squad_count(p_career,c.club_id)>=public.cw_squad_limit()+6 then continue;end if;
  paid:=public.cw_available_budget(p_career,c.club_id);
  select coalesce(jsonb_object_agg(position,n),'{}') into depth from(select sp2.position,count(*) as n from public.mgr_players t join public.sim_players sp2 on sp2.id=t.player_id where t.career_id=p_career and t.club_id=c.club_id group by sp2.position)x;
  select a.style into style from public.mgr_ai_clubs a where a.career_id=p_career and a.club_id=c.club_id;
  select sp.id,mp.club_id,sp.position,coalesce(cp.potential,70) as potential into p from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
   join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
   where mp.career_id=p_career and mp.club_id is distinct from c.club_id and sp.active and (not (select public.cw_runtime_enabled(p_career)) or mp.club_id is null or mp.club_id in (select public.cw_domestic_clubs(p_career)))
    and (mp.club_id is null or public.cw_window_open(public.cw_region(c.club_id),d))
    and cp.market_value<paid*.65
    and not exists(select 1 from public.cw_negotiations x where x.career_id=p_career and x.player_id=sp.id and x.buyer_club=c.club_id and x.status in('seller_review','club_pending','club_counter','player_pending','player_counter','agreed','precontract'))
    and pr.rating>=c.prestige-12
    and (mp.club_id is null or not exists(select 1 from _cw_pillars pl where pl.player_id=sp.id))
    and (mp.club_id is null or cp.age_at_start+floor((d-(select started_on from public.cw_world where career_id=p_career))/365.25)>=32
     or (select lvl from _cw_levels where club_id=c.club_id)<=(select lvl from _cw_levels where club_id=mp.club_id))
   order by (pr.rating+case when c.strategy='youth' then cp.potential-pr.rating else 0 end)
    /greatest(1,coalesce((depth->>sp.position)::int,0))*random() +case when (style='wide' and sp.position in('PD','PE','LD','LE')) or(style='counter' and sp.position in('ATA','PD','PE')) or(style='possession' and sp.position in('MC','MEI','VOL')) then 5 else 0 end
    +case when public.cw_region(mp.club_id)<>public.cw_region(c.club_id) then 20*(select ai_foreign_preference from public.cw_rules) else 0 end desc limit 1;
  if p.id is null then continue;end if;
  select * into ct from public.cw_contracts where career_id=p_career and player_id=p.id and status='active';
  value:=public.cw_player_value(p_career,p.id);
  insert into public.cw_negotiations(career_id,player_id,seller_club,buyer_club,initiator,status,fee,monthly_salary,contract_years,signing_bonus,created_on,reply_on,expires_on,valuation,agreed_owner_contract)
   values(p_career,p.id,p.club_id,c.club_id,'ai',case when p.club_id=own then 'seller_review' else 'club_pending' end,case when p.club_id is null then 0 else round(value*(1.1+random()*.35)) end,
    public.cw_salary_demand(p_career,p.id,c.club_id),3,greatest(ceil(value*.02),case when p.club_id is null then public.cw_minimum_signing(p_career,p.id,c.club_id) else 0 end),d,d+2,public.cw_deadline(d),value,ct.id) returning id into id;
  begin perform public.cw_reserve_offer(id);exception when raise_exception then perform public.cw_neg_close(id,'failed_funds',sqlerrm);continue;end;
  perform public.cw_neg_history(id,'buyer','Proposta enviada pelo clube interessado.');
  if p.club_id=own then perform public.cw_news_add(p_career,'incoming:'||id,'transfer',public.mgr_club_name(c.club_id)||' faz proposta por '||public.mgr_player_name(p.id),'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.id);end if;
 end loop;
 -- Contract continuity and rational renewals run before expiry in cw_finance_tick.
end $function$
;

revoke all on function public.cw_wage_extra(uuid) from public, anon, authenticated;
revoke all on function public.cw_renewal_ask(uuid,text,text) from public, anon, authenticated;
