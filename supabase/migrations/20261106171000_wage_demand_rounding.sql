-- Correção (2026-11-06): o salário é negociado por semana, mas guardado por mês. cw_weekly arredonda, então o
-- valor semanal mostrado como "pedida do atleta" às vezes volta como um mensal 1 abaixo da pedida e a oferta
-- era recusada com "Recusei sua oferta de R$ 259.000 por semana. Peço pelo menos R$ 259.000 por semana."
-- Agora oferecer o valor semanal mostrado sempre cumpre a pedida.
create or replace function public.career_contract_offer(p_negotiation uuid, p_weekly_wage bigint, p_years integer, p_request uuid)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare car public.careers;n public.cw_negotiations;own text;demand bigint;monthly bigint;r jsonb;
begin
 car:=public.mgr_lock();
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 select * into n from public.cw_negotiations where id=p_negotiation and career_id=car.id and buyer_club=own;
 if not found then raise exception 'Negociação não encontrada';end if;
 if p_weekly_wage is null or p_weekly_wage<1 then raise exception 'Salário inválido';end if;
 monthly:=public.cw_monthly(p_weekly_wage);
 demand:=public.cw_salary_demand(car.id,n.player_id,own);
 -- quem oferece o valor semanal pedido (já arredondado) cumpre a pedida mensal
 if p_weekly_wage>=public.cw_weekly(demand) then monthly:=greatest(monthly,demand);end if;
 if monthly<demand then
  if monthly<demand*.75 then
   raise exception using errcode='P6601',message=format('Recusei sua oferta de %s por semana. Ela está muito longe do que considero aceitável; para eu pensar no assunto, os termos precisam melhorar bastante.',public.cw_money_label(public.cw_weekly(monthly))),
    detail=public.cw_weekly(demand)::text;
  end if;
  raise exception using errcode='P6602',message=format('Recusei sua oferta de %s por semana. Peço pelo menos %s por semana. Deseja negociar mais?',public.cw_money_label(public.cw_weekly(monthly)),public.cw_money_label(public.cw_weekly(demand))),
   detail=public.cw_weekly(demand)::text;
 end if;
 r:=public.career_player_offer(p_negotiation,monthly,p_years,0,public.cw_cm_role(car.id,n.player_id,own),0,0,p_request);
 return r||jsonb_build_object('weekly_wage',public.cw_weekly(monthly),'years',p_years);
end $function$;
