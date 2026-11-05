-- Fase 1 (desempenho): funções quentes reescritas com o mesmo resultado.
-- Cada bloco foi conferido contra a versão anterior em produção antes de aplicar.

-- cw_eff_attrs
CREATE OR REPLACE FUNCTION public.cw_eff_attrs(p_career uuid, p_player text)
 RETURNS sim_player_attrs
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select row(
  a.player_id,
  case when d.d ? 'gk_reflexes' then greatest(1,least(99,round(a.gk_reflexes+(d.d->>'gk_reflexes')::numeric)))::smallint else a.gk_reflexes end,
  case when d.d ? 'gk_handling' then greatest(1,least(99,round(a.gk_handling+(d.d->>'gk_handling')::numeric)))::smallint else a.gk_handling end,
  case when d.d ? 'gk_positioning' then greatest(1,least(99,round(a.gk_positioning+(d.d->>'gk_positioning')::numeric)))::smallint else a.gk_positioning end,
  case when d.d ? 'marking' then greatest(1,least(99,round(a.marking+(d.d->>'marking')::numeric)))::smallint else a.marking end,
  case when d.d ? 'tackling' then greatest(1,least(99,round(a.tackling+(d.d->>'tackling')::numeric)))::smallint else a.tackling end,
  case when d.d ? 'positioning' then greatest(1,least(99,round(a.positioning+(d.d->>'positioning')::numeric)))::smallint else a.positioning end,
  case when d.d ? 'heading' then greatest(1,least(99,round(a.heading+(d.d->>'heading')::numeric)))::smallint else a.heading end,
  case when d.d ? 'passing' then greatest(1,least(99,round(a.passing+(d.d->>'passing')::numeric)))::smallint else a.passing end,
  case when d.d ? 'vision' then greatest(1,least(99,round(a.vision+(d.d->>'vision')::numeric)))::smallint else a.vision end,
  case when d.d ? 'technique' then greatest(1,least(99,round(a.technique+(d.d->>'technique')::numeric)))::smallint else a.technique end,
  case when d.d ? 'stamina' then greatest(1,least(99,round(a.stamina+(d.d->>'stamina')::numeric)))::smallint else a.stamina end,
  case when d.d ? 'finishing' then greatest(1,least(99,round(a.finishing+(d.d->>'finishing')::numeric)))::smallint else a.finishing end,
  case when d.d ? 'off_ball' then greatest(1,least(99,round(a.off_ball+(d.d->>'off_ball')::numeric)))::smallint else a.off_ball end,
  case when d.d ? 'pace' then greatest(1,least(99,round(a.pace+(d.d->>'pace')::numeric)))::smallint else a.pace end,
  case when d.d ? 'dribbling' then greatest(1,least(99,round(a.dribbling+(d.d->>'dribbling')::numeric)))::smallint else a.dribbling end,
  case when d.d ? 'strength' then greatest(1,least(99,round(a.strength+(d.d->>'strength')::numeric)))::smallint else a.strength end,
  a.estimated,
  a.method,
  a.updated_at,
  case when d.d ? 'aggression' then greatest(1,least(99,round(a.aggression+(d.d->>'aggression')::numeric)))::smallint else a.aggression end,
  case when d.d ? 'discipline' then greatest(1,least(99,round(a.discipline+(d.d->>'discipline')::numeric)))::smallint else a.discipline end)::public.sim_player_attrs
 from public.sim_player_attrs a left join public.cw_player_dev d on d.career_id=p_career and d.player_id=p_player
 where a.player_id=p_player
$function$;

-- cw_market_tick_before_v37
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
    +case when b.m_games>=3 then greatest(case when b.m_apps::numeric/b.m_games>=b.m_exp then 1 else -6 end,
          greatest(-6,least(6,round(10*(b.m_apps::numeric/b.m_games-b.m_exp)))))
     else case when b.m_morale<60 then 1 when b.m_morale>70 then -1 else 0 end end
    +greatest(-4,least(4,2*b.m_w-2*b.m_l))
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
end $function$;

-- cw_runtime_maintenance
CREATE OR REPLACE FUNCTION public.cw_runtime_maintenance()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record;n int:=0;
begin
 for r in select c.id,w.today from public.careers c join public.cw_runtime rt on rt.career_id=c.id join public.cw_world w on w.career_id=c.id
 where (rt.last_maintenance_at is null or rt.last_maintenance_at<now()-interval '1 day'
        or rt.last_maintained_on is null or w.today-rt.last_maintained_on>=30)
 and not exists(select 1 from public.mgr_matches m where m.career_id=c.id and m.status='live' and m.user_side is not null)
 order by rt.last_maintenance_at nulls first,c.id limit 1 for update of c skip locked loop
  perform public.cw_prune_career(r.id);
  perform public.cw_compact_closed_seasons(r.id);
  perform public.cw_trim_closed_stats(r.id);
  perform public.cw_compact_old_wages(r.id);
  delete from public.cw_ai_days where career_id=r.id and on_date<r.today-1;
  update public.cw_runtime set last_maintenance_at=now(),last_maintained_on=r.today where career_id=r.id;n:=n+1;
 end loop;
 return n;
end $function$;

-- Manutenção: uma carreira por execução, a cada 15 minutos, para não segurar a trava de várias carreiras por até 25 s.
select cron.alter_job(28, schedule := '*/15 * * * *');
