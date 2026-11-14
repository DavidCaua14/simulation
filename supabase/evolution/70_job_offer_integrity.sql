-- Evolução 70: proposta de emprego que chega ao técnico sempre pode ser aceita.
--
-- Problema (produção, 14/11/2026): mgr_make_offer escolhia o clube, gravava a proposta e mandava o e-mail
-- "Proposta: <clube>"; só depois conferia o prestígio do clube contra a reputação/credibilidade do técnico e, se o
-- clube estivesse acima do alcance, marcava a proposta como expirada. O e-mail ficava na caixa apontando para uma
-- proposta morta ("Proposta encerrada" ao aceitar). Um técnico desempregado de reputação baixa recebeu 53 de 72
-- propostas assim e não conseguia voltar ao mercado.
--
-- Agora: proposta acima do alcance é apagada junto com o e-mail (nunca chega ao técnico). Desempregado tenta de novo
-- com clubes menores, até quatro vezes, e sempre alcança os clubes de prestígio até 60. Propostas mortas antigas e
-- seus e-mails são limpos.
create or replace function public.mgr_make_offer(p_career uuid, p_season uuid, p_day integer, p_force_weak boolean default false, p_any_region boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare result jsonb;oid uuid;d date;cred numeric;club text;reg text;pay bigint;budget bigint;bonus int;try int;weak boolean:=p_force_weak;unemployed boolean;
begin
 if not exists(select 1 from public.cw_world where career_id=p_career) then return public.mgr_make_offer_before_world(p_career,p_season,p_day,p_force_weak,p_any_region);end if;
 select credibility into cred from public.cw_coach where career_id=p_career;
 select status='unemployed' into unemployed from public.mgr_coach where career_id=p_career;
 -- Clubes de outra região contratam técnico de fora sobretudo na pré-temporada ou na janela deles (evolução 34).
 select public.cw_region((select club_id from public.mgr_coach where career_id=p_career)) into reg;
 select today into d from public.cw_world where career_id=p_career;
 for try in 1..case when unemployed then 4 else 1 end loop
  -- A financial dismissal reduces the reach of the next search, including forced low-tier searches.
  result:=public.mgr_make_offer_before_world(p_career,p_season,p_day,weak or cred<45,
   random()<case when public.cw_foreign_hiring(case when coalesce(reg,(select region from public.career_seasons where id=p_season))='ENG' then 'BRA' else 'ENG' end,d) then 1 else .25 end);
  if result is null then return null;end if;
  oid:=(result->>'id')::uuid;club:=result->>'club_id';perform public.cw_materialize_club(p_career,club);
  -- Alcance do técnico; desempregado sempre alcança a faixa mais baixa do mundo (só 2 clubes têm força até 55,
  -- então reputação muito baixa deixava o técnico sem nenhum clube possível).
  if (select prestige from public.cw_clubs where career_id=p_career and club_id=club)>greatest(55+(select reputation from public.mgr_coach where career_id=p_career)*.32+(cred-65)*.18,
      case when unemployed then 60 else 0 end) then
   -- clube acima do alcance: a proposta não chega ao técnico (sem proposta morta e sem e-mail)
   delete from public.season_offers where id=oid;
   delete from public.mgr_messages where career_id=p_career and kind='offer' and club_id=club and created_at>=now();
   weak:=true;
   continue;
  end if;
  pay:=greatest(70,round((select prestige from public.cw_clubs where career_id=p_career and club_id=club)*2.5+cred));
  budget:=greatest(0,public.cw_available_budget(p_career,club));
  select least(bonus_coins,greatest(0,budget/50)::int) into bonus from public.season_offers where id=oid;
  budget:=greatest(0,budget-bonus-2*pay);
  update public.season_offers set salary=pay,contract_years=2,budget_guarantee=budget,expires_on=public.cw_deadline(d),expires_day=p_day+(select max_negotiation_days from public.cw_rules),
  bonus_coins=bonus,pitch=replace(pitch,'na próxima temporada','na temporada em andamento') where id=oid;
  perform public.cw_news_add(p_career,'job-offer:'||oid,'job',public.mgr_club_name(club)||' procura novo treinador','Proposta de contrato por duas temporadas. Salário e orçamento podem ser negociados em Carreira.',95,club);
  return result||jsonb_build_object('salary',pay,'contract_years',2,'budget_guarantee',budget,'expires_on',public.cw_deadline(d));
 end loop;
 return null;
end $function$;
revoke all on function public.mgr_make_offer(uuid,uuid,integer,boolean,boolean) from public,anon,authenticated;

-- Limpeza: propostas que nasceram mortas (sem salário nem prazo) e o e-mail que cada uma deixou.
delete from public.mgr_messages m using public.season_offers o
 where o.kind='coach' and o.status='expired' and o.salary is null and o.expires_on is null and o.responded_at<=o.created_at+interval '30 seconds'
   and m.career_id=o.career_id and m.kind='offer' and m.club_id=o.from_club
   and m.created_at between o.created_at and o.created_at+interval '30 seconds';
delete from public.season_offers o
 where o.kind='coach' and o.status='expired' and o.salary is null and o.expires_on is null and o.responded_at<=o.created_at+interval '30 seconds';
