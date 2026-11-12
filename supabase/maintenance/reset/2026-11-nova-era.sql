-- Reinício do modo Temporadas — nova era (2026-11-12).
-- Pré-requisito: migração 20261113120000_seasons_new_era_rules aplicada (career_trophies, sim_prizes).
--
-- Mantém: conta (nível, XP, moedas, diamantes, energia), perfil, eventos, apostas e a sala de troféus.
-- Reinicia: mundo de cada carreira (clubes, elencos, contratações, finanças, calendário) em 01/01/2026, técnico sem
-- clube com reputação e credibilidade iniciais, e o ranking geral (que passa a contar só o modo online).
-- Bônus: moedas pelo histórico de títulos (valor simbólico por taça), entregues como prêmio na caixa de mensagens.
--
-- Uso: rodar este arquivo (cria as funções e faz a parte comum) e depois, para cada carreira, em chamadas separadas:
--   select public.career_new_era(id) from public.careers where id='<carreira>';
-- Cada carreira é uma transação curta; repetir a chamada não duplica o bônus.

-- Valor simbólico de uma taça, em moedas.
create or replace function public.career_trophy_bonus(p_competition text) returns int
language sql stable security definer set search_path=public as $$
 select case
  when p_competition='ucl' then 5000 when p_competition='libertadores' then 4000
  when p_competition in('eng_premier','esp_laliga','ita_seriea','ger_bundesliga','fra_ligue1') then 3000
  when p_competition='copa_brasil' then 2500 when p_competition='brasileirao' then 2000
  when co.kind='league' and coalesce(co.division,1)>1 then 500
  when co.kind='league' then 800 when co.region='ENG' then 1200 else 500 end
 from(select 1) x left join public.sim_competitions co on co.id=p_competition
$$;

create or replace function public.career_new_era(p_career uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_coins int;v_titles int;v_legacy int;n int;
begin
 perform set_config('statement_timeout','600s',true);
 perform 1 from public.careers where id=p_career for update;
 if exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null) then raise exception 'Partida em andamento';end if;
 -- 1. sala de troféus: arquiva as taças de todas as passagens
 insert into public.career_trophies(career_id,competition,year,club_id,era)
 select sp.career_id,x->>'competition',(x->>'year')::int,sp.club_id,'2026-11'
 from public.mgr_spells sp cross join lateral jsonb_array_elements(coalesce(sp.titles,'[]'::jsonb)) x
 where sp.career_id=p_career on conflict do nothing;
 -- 2. bônus pelo histórico: por taça arquivada + títulos do legado anterior (sem competição registrada: 1000 cada)
 select count(*),coalesce(sum(public.career_trophy_bonus(t.competition)),0) into v_titles,v_coins from public.career_trophies t where t.career_id=p_career;
 select coalesce((lg.previous->>'titles')::int,0) into v_legacy from public.career_legacy lg where lg.career_id=p_career;
 v_legacy:=coalesce(v_legacy,0);v_coins:=v_coins+1000*v_legacy;v_titles:=v_titles+v_legacy;
 if v_coins>0 and not exists(select 1 from public.player_notices where career_id=p_career and title='Bônus da sala de troféus') then
  insert into public.player_notices(career_id,kind,title,body,reward)
  values(p_career,'reward','Bônus da sala de troféus',
   format('O modo Temporadas recomeçou em 2026 e as suas taças continuam na sala de troféus. Pelos %s título(s) da sua história você recebe %s moedas.',v_titles,v_coins),
   jsonb_build_object('coins',v_coins));
 end if;
 -- 3. mundo e dados do técnico (as taças ficam; reputação e credibilidade voltam ao início)
 delete from public.cw_season_rewards where career_id=p_career;
 delete from public.cw_player_unrest where career_id=p_career;
 delete from public.cw_job_applications where career_id=p_career;
 delete from public.cw_job_vacancies where career_id=p_career;
 delete from public.mgr_club_bans where career_id=p_career;
 perform public.career_reset_world(p_career);
 update public.mgr_coach m set reputation=25,board_confidence=60,fan_mood=60,rank_penalty=0,squad_warned=0,
  titles=(select count(*) from public.career_trophies t where t.career_id=m.career_id) where m.career_id=p_career;
 update public.cw_coach set credibility=65,monthly_salary=145,contract_until=null,promised_budget=0,last_pay_on=null,last_finance_warning=null,financial_dismissals=0
  where career_id=p_career;
 update public.career_legacy set legacy_points=0 where career_id=p_career;
 -- 4. mundo novo em 2026: técnico sem clube e propostas da Série A, como no primeiro acesso
 if exists(select 1 from public.careers where id=p_career and status='active') then
  perform public.career_begin_unemployed(p_career);
  n:=public.career_reset_offers(p_career);
 end if;
 return jsonb_build_object('career',p_career,'titles',v_titles,'coins',v_coins,'offers',n,
  'today',(select today from public.cw_world where career_id=p_career));
end $$;
revoke all on function public.career_new_era(uuid),public.career_trophy_bonus(text) from public,anon,authenticated;

-- Parte comum: ranking geral zerado (passa a contar só o modo online).
delete from public.on_ranking;
insert into public.econ_reason_map(fn,reason,label) values('on_rank_hook','online_match_reward','Vitória no modo online')
on conflict do nothing;
