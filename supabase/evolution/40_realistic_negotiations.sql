-- EVOLUÇÃO 40: negociações como na vida real e idade em todas as cartas.
-- * Clube vendedor (da IA): os 3 melhores do elenco são intocáveis (só uma proposta enorme, de clube maior, às vezes
--   abre conversa); titulares saem por 1,6–2× (4º–7º) ou 1,25–1,5× (8º–11º; entre clubes da IA, regra normal) o valor de
--   mercado (mais se o comprador for menor) e às
--   vezes o clube nem negocia. Quem pediu para sair ou está no fim do contrato segue a regra normal.
-- * Atleta: não aceita descer de divisão (Série A/Premier → Série B/Championship) — só com 32+ anos ou se quer sair e
--   recebe 30% a mais; na mesma divisão recusa clube bem mais fraco (salvo +50% de salário, 31+ anos ou pedido de
--   saída); livre muito acima do nível do clube espera proposta melhor.
-- * IA mira alvos realistas: não procura pilares de outros clubes nem atletas de divisão acima da sua (salvo 32+).
-- * Cartas: a idade vai em todas as listas de atletas (inclusive partidas).
begin;

create or replace function public.cw_patch_players(p_career uuid, p_list jsonb, p_extra boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select coalesce(jsonb_agg(case when cp.player_id is null then e else e||jsonb_build_object('number',coalesce(cp.shirt_number,(e->>'number')::int),'age',cp.age_at_start+floor((w.today-w.started_on)/365.25)::int)||
  case when p_extra then jsonb_build_object('morale',round(cp.morale),'transfer_requested',cp.transfer_requested,'transfer_listed',cp.transfer_listed,
   'promised_role',cp.promised_role,'age',cp.age_at_start+floor((w.today-w.started_on)/365.25)::int,
   'contract_expires',ct.expires_on,'monthly_salary',ct.monthly_salary,
   'precontract',exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=cp.player_id and n.status='precontract' and n.buyer_club is distinct from (e->>'club_id')))
  else '{}'::jsonb end end order by o),'[]'::jsonb)
 from jsonb_array_elements(coalesce(p_list,'[]')) with ordinality x(e,o)
 left join public.cw_players cp on cp.career_id=p_career and cp.player_id=e->>'id'
 left join public.cw_world w on w.career_id=p_career
 left join public.cw_contracts ct on ct.career_id=p_career and ct.player_id=cp.player_id and ct.status='active'
$function$;

-- Nível do clube: 1 = primeira divisão (ou estrangeiro forte), 2 = segunda divisão.
create or replace function public.cw_club_level(p_club text)
returns int language sql stable security definer set search_path=public as $$
 select case when c.tier in('premier_league','serie_a') then 1 when c.tier in('championship','serie_b') then 2
  when c.strength>=72 then 1 else 2 end from public.sim_clubs c where c.id=p_club
$$;

-- Posição do atleta no elenco do clube pela nota (1 = melhor).
create or replace function public.cw_squad_rank(p_career uuid,p_club text,p_player text)
returns int language sql stable security definer set search_path=public as $$
 select x.rk from(select mp.player_id,rank() over(order by r.rating desc,mp.player_id) rk from public.mgr_players mp
  join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  where mp.career_id=p_career and mp.club_id=p_club) x where x.player_id=p_player
$$;

-- Mercado da IA (cópia da evolução 34) com alvos realistas.
create or replace function public.cw_market_tick_before_v37(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;threshold numeric;interest numeric;buyer public.cw_clubs;seller public.cw_clubs;
 r record;c public.cw_clubs;p record;id uuid;value bigint;cnt int;expected numeric;apps int;games int;new_morale numeric;paid bigint;user_region text;depth jsonb;style text;
begin
 select today into d from public.cw_world where career_id=p_career;
 if extract(doy from d)=1 then update public.cw_players set market_value=public.cw_player_value(p_career,player_id) where career_id=p_career;end if;
 select club_id into own from public.mgr_coach where career_id=p_career;
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
     update public.cw_negotiations set status='player_pending',monthly_salary=greatest(40,ceil(coalesce(ct.monthly_salary,n.valuation*.0065)*1.15)),contract_years=3,signing_bonus=ceil(n.valuation*.02),reply_on=d+2 where id=n.id;
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
    begin
     perform public.cw_reserve_offer(n.id);
     update public.cw_negotiations set status=case when n.register_on is not null then 'precontract' else 'agreed' end,response='Ambas as partes aprovaram. Aguardando registro.',register_on=coalesce(n.register_on,case when n.seller_club is not null and n.initiator<>'renewal' and not public.cw_window_open(public.cw_region(n.buyer_club),d) then public.cw_next_window(public.cw_region(n.buyer_club),d) else d end) where id=n.id;
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
 -- Satisfação semanal pelos minutos reais x papel prometido e pelos salários em dia (evolução 34).
 -- Reservas e promessas aceitam o papel (não caem abaixo de 40 só por minutos); quem cobra espaço é o titular encostado.
 for p in select cp.*,mp.club_id,ct.arrears,ct.starts_on,ct.role from public.cw_players cp join public.mgr_players mp using(career_id,player_id)
  join public.cw_contracts ct on ct.career_id=cp.career_id and ct.player_id=cp.player_id and ct.status='active'
  where cp.career_id=p_career and (cp.last_morale_on is null or cp.last_morale_on<=d-7) loop
  if d-p.starts_on<28 then update public.cw_players set last_morale_on=d where career_id=p_career and player_id=p.player_id;continue;end if;
  select count(*) into games from public.cw_club_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=p_career and fd.club_id=p.club_id and f.status='played' and fd.due_on between d-28 and d;
  select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=p.player_id and mp.club_id=p.club_id and mp.minutes>=30 and mp.on_date between d-28 and d;
  expected:=case p.promised_role when 'key' then .70 when 'starter' then .50 when 'rotation' then .20 else 0 end;
  -- Clubes da IA conversam com quem não tem espaço: o papel prometido passa a ser de reserva (o seu clube decide sozinho).
  if p.club_id is distinct from own and games>=3 and expected>.2 and apps::numeric/games<expected*.4 and random()<.5 then
   update public.cw_players set promised_role='rotation' where career_id=p_career and player_id=p.player_id;
   update public.cw_contracts set role='rotation' where career_id=p_career and player_id=p.player_id and status='active';
   expected:=.20;
  end if;
  if games<3 or expected=0 or apps::numeric/games>=expected then
   -- Papel cumprido (ou sem jogos suficientes): recupera, mais rápido quando estava insatisfeito; perto do topo sobe devagar.
   new_morale:=p.morale+case when p.morale<50 then 6 when p.morale<80 then 3 else 1 end;
  else
   new_morale:=greatest(least(p.morale,case p.promised_role when 'key' then 5 when 'starter' then 15 else 40 end),
    p.morale-round(2+4*(expected-apps::numeric/games)/expected));
  end if;
  new_morale:=greatest(0,least(100,new_morale-case when p.arrears>0 then 12 else 0 end));
  update public.cw_players set morale=new_morale,last_morale_on=d,transfer_requested=new_morale<30,
   last_warning_on=case when new_morale<45 then coalesce(last_warning_on,d) else null end where career_id=p_career and player_id=p.player_id;
  if new_morale<45 and p.morale>=45 and p.club_id=own then perform public.cw_news_add(p_career,'morale:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||' cobra espaço no time',
   'O papel prometido, os minutos recentes e os pagamentos estão afetando a satisfação. Reveja as oportunidades ou o papel no contrato.',90,own,p.player_id);
  elsif new_morale<30 and p.morale>=30 and p.club_id=own then perform public.cw_news_add(p_career,'morale-out:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||' pede para sair',
   'Muito insatisfeito, o atleta quer ser negociado e rende menos em campo. Dê minutos, ajuste o papel ou negocie a saída.',95,own,p.player_id);
  elsif new_morale>=45 and p.morale<45 and p.club_id=own then perform public.cw_news_add(p_career,'morale-up:'||p.player_id||':'||to_char(d,'IYYY-IW'),'squad',public.mgr_player_name(p.player_id)||' volta a ficar satisfeito',
   'Com mais oportunidades, o atleta voltou a se dedicar e esquece a ideia de sair.',60,own,p.player_id);
  end if;
 end loop;
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
 for c in select * from public.cw_clubs where career_id=p_career and club_id is distinct from own order by club_id loop
  insert into public.cw_ai_days values(p_career,c.club_id,d) on conflict do nothing;if not found then continue;end if;
  -- Janela fechada: só atletas livres (como na vida real). Elenco acima do limite + 6 não compra.
  if c.financial_risk>=75 or random()>(select ai_bid_chance from public.cw_rules)*(case when public.cw_window_open(public.cw_region(c.club_id),d) then 1 else .35 end)
     or public.cw_squad_count(p_career,c.club_id)>=public.cw_squad_limit()+6 then continue;end if;
  paid:=public.cw_available_budget(p_career,c.club_id);
  select coalesce(jsonb_object_agg(position,n),'{}') into depth from(select sp2.position,count(*) as n from public.mgr_players t join public.sim_players sp2 on sp2.id=t.player_id where t.career_id=p_career and t.club_id=c.club_id group by sp2.position)x;
  select a.style into style from public.mgr_ai_clubs a where a.career_id=p_career and a.club_id=c.club_id;
  select sp.id,mp.club_id,sp.position,coalesce(cp.potential,70) as potential into p from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
   join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
   where mp.career_id=p_career and mp.club_id is distinct from c.club_id and sp.active
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
    greatest(40,ceil(coalesce(ct.monthly_salary,value*.0065)*1.15)),3,ceil(value*.02),d,d+2,public.cw_deadline(d),value,ct.id) returning id into id;
  begin perform public.cw_reserve_offer(id);exception when raise_exception then perform public.cw_neg_close(id,'failed_funds',sqlerrm);continue;end;
  perform public.cw_neg_history(id,'buyer','Proposta enviada pelo clube interessado.');
  if p.club_id=own then perform public.cw_news_add(p_career,'incoming:'||id,'transfer',public.mgr_club_name(c.club_id)||' faz proposta por '||public.mgr_player_name(p.id),'A venda depende da sua decisão. Abra Negociações para aceitar, recusar ou apresentar uma contraproposta.',95,own,p.id);end if;
 end loop;
 -- AI contract management: renew affordable contributors before expiry; release surplus players without deleting them.
 if extract(day from d)=15 then
  for ct in select x.* from public.cw_contracts x where x.career_id=p_career and x.status='active' and x.club_id is distinct from own and x.expires_on between d and d+120
   and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and n.status in('agreed','precontract')) loop
   if public.cw_available_budget(p_career,ct.club_id)>ct.monthly_salary*3 and (select morale from public.cw_players where career_id=p_career and player_id=ct.player_id)>=35 then
    update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id;
    insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
     values(p_career,ct.player_id,ct.club_id,d,(d+interval '2years')::date,ceil(ct.monthly_salary*1.06),ct.role);
    perform public.cw_news_add(p_career,'ai-renew:'||ct.id,'contract',public.mgr_player_name(ct.player_id)||' renova contrato','Vínculo renovado por duas temporadas.',25,ct.club_id,ct.player_id);
   end if;
  end loop;
 end if;
end $function$;

create or replace function public.cw_market_tick(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d date;own text;n public.cw_negotiations;ct public.cw_contracts;cp public.cw_players;rk int;minfee numeric;
 sb public.sim_clubs;bb public.sim_clubs;age int;rating numeric;wants_out boolean;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
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
  wants_out:=coalesce(cp.transfer_requested,false) or coalesce(cp.morale,60)<30;

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
     minfee:=n.valuation*case when rk<=7 then 1.6+n.decision_roll*.4 else 1.25+n.decision_roll*.25 end*case when bb.strength<sb.strength then 1.2 else 1 end;
     if n.fee<minfee then
      if n.initiator='ai' and n.decision_roll>.3 and public.cw_available_budget(p_career,n.buyer_club)>=minfee then
       -- Comprador da IA com caixa topa pagar o preço de um titular.
       update public.cw_negotiations set fee=ceil(minfee) where id=n.id;
       perform public.cw_neg_history(n.id,'buyer','Comprador aceitou pagar o preço pedido por um titular.');
      elsif n.round_no>=2 or n.initiator='ai' then
       perform public.cw_neg_close(n.id,'rejected','O clube só libera um titular por um valor bem acima do mercado.');
      else
       update public.cw_negotiations set status='club_counter',fee=ceil(minfee),round_no=round_no+1,expires_on=public.cw_deadline(d),
        response='Titular do elenco: o clube só negocia por '||ceil(minfee)||' moedas.' where id=n.id;
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
end $$;

revoke all on function public.cw_patch_players(uuid,jsonb,boolean),public.cw_club_level(text),public.cw_squad_rank(uuid,text,text),public.cw_market_tick(uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
