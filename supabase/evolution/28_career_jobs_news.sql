begin;
-- Preserve mature board/objective calculations; add contract and credibility effects around them.
do $$begin
 if to_regprocedure('public.mgr_fire_before_world(uuid,text)') is null then alter function public.mgr_fire(uuid,text) rename to mgr_fire_before_world;end if;
 if to_regprocedure('public.mgr_end_spell_before_world(uuid,text)') is null then alter function public.mgr_end_spell(uuid,text) rename to mgr_end_spell_before_world;end if;
 if to_regprocedure('public.mgr_make_offer_before_world(uuid,uuid,integer,boolean,boolean)') is null then alter function public.mgr_make_offer(uuid,uuid,int,boolean,boolean) rename to mgr_make_offer_before_world;end if;
end $$;
create or replace function public.mgr_end_spell(p_career uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
 update public.cw_coach_contracts set ended_on=(select today-1 from public.cw_world where career_id=p_career)
 where career_id=p_career and ended_on is null and spell_id=(select spell_id from public.mgr_coach where career_id=p_career);
 perform public.mgr_end_spell_before_world(p_career,p_reason);
end $$;
create or replace function public.mgr_fire(p_career uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c public.mgr_coach;financial boolean:=p_reason ilike '%financeir%';
begin
 select * into c from public.mgr_coach where career_id=p_career;
 if c.status<>'employed' then return;end if;
 perform public.mgr_fire_before_world(p_career,p_reason);
 update public.cw_coach set credibility=greatest(0,credibility-case when financial then 22 else 9 end),financial_dismissals=financial_dismissals+case when financial then 1 else 0 end where career_id=p_career;
 perform public.cw_news_add(p_career,'dismissal:'||c.spell_id,'job','Diretoria encerra o contrato do treinador',
  public.mgr_club_name(c.club_id)||': '||p_reason||'. A credibilidade e o acesso a novas propostas foram afetados.',100,c.club_id);
end $$;
create or replace function public.mgr_make_offer(p_career uuid,p_season uuid,p_day int,p_force_weak boolean default false,p_any_region boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare result jsonb;oid uuid;d date;cred numeric;club text;pay bigint;budget bigint;bonus int;
begin
 if not exists(select 1 from public.cw_world where career_id=p_career) then return public.mgr_make_offer_before_world(p_career,p_season,p_day,p_force_weak,p_any_region);end if;
 select credibility into cred from public.cw_coach where career_id=p_career;
 -- A financial dismissal reduces the reach of the next search, including forced low-tier searches.
 result:=public.mgr_make_offer_before_world(p_career,p_season,p_day,p_force_weak or cred<45,true);
 if result is null then return null;end if;
 oid:=(result->>'id')::uuid;club:=result->>'club_id';select today into d from public.cw_world where career_id=p_career;
 if (select prestige from public.cw_clubs where career_id=p_career and club_id=club)>55+(select reputation from public.mgr_coach where career_id=p_career)*.32+(cred-65)*.18 then
  update public.season_offers set status='expired',responded_at=now() where id=oid;return null;
 end if;
 pay:=greatest(70,round((select prestige from public.cw_clubs where career_id=p_career and club_id=club)*2.5+cred));
 budget:=greatest(0,public.cw_available_budget(p_career,club));
 select least(bonus_coins,greatest(0,budget/50)::int) into bonus from public.season_offers where id=oid;
 budget:=greatest(0,budget-bonus-2*pay);
 update public.season_offers set salary=pay,contract_years=2,budget_guarantee=budget,expires_on=public.cw_deadline(d),expires_day=p_day+(select max_negotiation_days from public.cw_rules),
 bonus_coins=bonus,pitch=replace(pitch,'na próxima temporada','na temporada em andamento') where id=oid;
 perform public.cw_news_add(p_career,'job-offer:'||oid,'job',public.mgr_club_name(club)||' procura novo treinador','Proposta de contrato por duas temporadas. Salário e orçamento podem ser negociados em Carreira.',95,club);
 return result||jsonb_build_object('salary',pay,'contract_years',2,'budget_guarantee',budget,'expires_on',public.cw_deadline(d));
end $$;
create or replace function public.cw_jobs_tick(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w public.cw_world;c public.mgr_coach;off jsonb;wait_days int;
begin
 select * into w from public.cw_world where career_id=p_career;select * into c from public.mgr_coach where career_id=p_career;
 update public.season_offers set status='expired',responded_at=now() where career_id=p_career and kind='coach' and status='pending' and expires_on<w.today;
 wait_days:=w.elapsed_days-coalesce(c.unemployed_day,w.elapsed_days);
 if (select count(*) from public.season_offers where career_id=p_career and kind='coach' and status='pending')<3 and
 ((c.status='unemployed' and (random()<.10+c.reputation*.003 or wait_days>=10)) or (c.status='employed' and random()<.004+c.reputation*.00015)) then
  off:=public.mgr_make_offer(p_career,w.primary_season,w.elapsed_days,c.status='unemployed' and wait_days>=10,true);
 end if;
 if c.status='employed' and (select contract_until from public.cw_coach where career_id=p_career)<w.today then
  perform public.mgr_end_spell(p_career,'expired');
  perform public.cw_news_add(p_career,'coach-expired:'||c.spell_id,'job','Contrato do treinador encerrado','O vínculo com '||public.mgr_club_name(c.club_id)||' chegou ao fim. Você está disponível para novas propostas.',100,c.club_id);
 end if;
 if c.status='employed' and (select contract_until from public.cw_coach where career_id=p_career) between w.today and w.today+60 then
  perform public.cw_news_add(p_career,'coach-renew:'||c.spell_id,'contract','Seu contrato entra nos meses finais','Negocie a renovação em Carreira antes do encerramento do vínculo.',95,c.club_id);
 end if;
end $$;
create or replace function public.career_job_negotiate(p_offer uuid,p_salary bigint,p_years int,p_budget bigint,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;o public.season_offers;prev jsonb;limit_salary bigint;available bigint;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'job_negotiate');if prev is not null then return prev;end if;
 select * into o from public.season_offers where id=p_offer and career_id=car.id and kind='coach' and status='pending' for update;
 if not found or o.expires_on<(select today from public.cw_world where career_id=car.id) or o.negotiation_round>=2 then raise exception 'Negociação de emprego indisponível';end if;
 if p_salary is null or p_salary not between 1 and 100000 or p_years is null or p_years not between 1 and 5 or p_budget is null or p_budget not between 0 and 100000000 then raise exception 'Condições de emprego inválidas';end if;
 limit_salary:=round(o.salary*(1.12+(select reputation from public.mgr_coach where career_id=car.id)/1000));available:=greatest(0,public.cw_available_budget(car.id,o.from_club)-o.bonus_coins-2*p_salary);
 if p_salary>limit_salary*1.3 or p_budget>available or p_years>3 then
  update public.season_offers set salary=limit_salary,contract_years=2,budget_guarantee=greatest(0,public.cw_available_budget(car.id,o.from_club)-o.bonus_coins-2*limit_salary),negotiation_round=negotiation_round+1,pitch='A diretoria apresentou sua contraproposta. O caixa limita o orçamento prometido.' where id=o.id;
 else update public.season_offers set salary=p_salary,contract_years=p_years,budget_guarantee=p_budget,negotiation_round=negotiation_round+1,pitch='A diretoria aprovou os termos negociados. O contrato está pronto para assinatura.' where id=o.id;end if;
 return public.econ_request_save(car.id,p_request,'job_negotiate',jsonb_build_object('ok',true));
end $$;
create or replace function public.career_coach_renew(p_years int,p_salary bigint,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare car public.careers;c public.mgr_coach;d date;until_date date;prev jsonb;
begin
 car:=public.mgr_lock();prev:=public.econ_request_get(car.id,p_request,'coach_renew');if prev is not null then return prev;end if;
 select * into c from public.mgr_coach where career_id=car.id;select today into d from public.cw_world where career_id=car.id;
 if c.status<>'employed' or c.board_confidence<45 or p_years is null or p_years not between 1 and 3 or p_salary is null or p_salary<1 or p_salary>(select monthly_salary*1.2 from public.cw_coach where career_id=car.id) or (select financial_risk from public.cw_clubs where career_id=car.id and club_id=c.club_id)>=75 then raise exception 'A diretoria não aceita estas condições de renovação';end if;
 until_date:=((select greatest(contract_until,d) from public.cw_coach where career_id=car.id)+make_interval(years=>p_years))::date;
 if until_date>(d+interval '5 years')::date then raise exception 'O prazo total do vínculo não pode superar cinco anos';end if;
 -- Keep the old salary immutable: renew salary after the current contract ends, or extend at the existing salary.
 if p_salary<>(select monthly_salary from public.cw_coach where career_id=car.id) then raise exception 'A renovação antecipada mantém o salário atual';end if;
 update public.cw_coach set contract_until=until_date where career_id=car.id;
 update public.cw_coach_contracts set expires_on=until_date where career_id=car.id and spell_id=c.spell_id and ended_on is null;
 perform public.cw_news_add(car.id,'coach-renewed:'||p_request,'job','Diretoria renova com o treinador','Novo prazo contratual: '||until_date||'.',90,c.club_id);
 return public.econ_request_save(car.id,p_request,'coach_renew',jsonb_build_object('ok',true));
end $$;
create or replace function public.cw_archive_match()
returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
 if new.status<>'finished' or old.status='finished' or not exists(select 1 from public.cw_world where career_id=new.career_id) then return new;end if;
 insert into public.cw_appearances(career_id,fixture_id,season_id,competition_id,player_id,club_id,on_date,minutes,goals,assists,rating,starter)
 select new.career_id,new.fixture_id,new.season_id,f.competition_id,mp.player_id,mp.club_id,coalesce(fd.due_on,w.today),mp.minutes,mp.goals,mp.assists,mp.rating,mp.starter
 from public.mgr_match_players mp join public.season_fixtures f on f.id=mp.fixture_id join public.cw_world w on w.career_id=new.career_id left join public.cw_fixture_dates fd on fd.fixture_id=f.id
 where mp.fixture_id=new.fixture_id and mp.minutes>0 on conflict do nothing;
 return new;
end $$;
drop trigger if exists cw_archive_match_trg on public.mgr_matches;
create trigger cw_archive_match_trg after update of status on public.mgr_matches for each row execute function public.cw_archive_match();

-- Competition awards are derived from stored final tables and individual match statistics.
create or replace function public.cw_competition_news()
returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s public.career_seasons;co public.sim_competitions;mvp record;runner text;scorer record;
begin
 if new.status<>'finished' or (tg_op='UPDATE' and old.status='finished') then return new;end if;
 select * into s from public.career_seasons where id=new.season_id;
 if not exists(select 1 from public.cw_world where career_id=s.career_id) then return new;end if;
 select * into co from public.sim_competitions where id=new.competition_id;
 runner:=new.runner_up_club;
 if co.kind='league' then select club_id into runner from public.sim_standings(s.id,co.id,null) where pos=2;end if;
 with contributions as (
  select a.player_id,a.club_id,count(*)::int as apps,sum(a.goals)::int as goals,sum(a.assists)::int as assists,sum(a.rating) as rating_sum
   from public.cw_appearances a where a.season_id=s.id and a.competition_id=co.id and a.minutes>0 group by a.player_id,a.club_id
  union all
  select st.player_id,st.club_id,st.apps,st.goals,st.assists,st.rating_sum from public.cw_stats_opening st where st.season_id=s.id and st.competition_id=co.id
 ), scores as (
  select player_id,club_id,sum(apps)::int as apps,sum(goals)::int as goals,sum(assists)::int as assists,round(sum(rating_sum)/greatest(sum(apps),1),2) as rating from contributions
  where club_id=new.champion_club group by player_id,club_id
 ) select * into mvp from scores where apps>=greatest(1,(select max(apps)/3 from scores)) order by rating desc,goals desc,assists desc,player_id limit 1;
 select st.player_id,sum(st.goals)::int as goals into scorer from public.mgr_player_stats st where st.season_id=s.id and st.competition_id=co.id group by st.player_id order by sum(st.goals) desc,sum(st.assists) desc,st.player_id limit 1;
 perform public.cw_news_add(s.career_id,'champion:'||s.id||':'||co.id,'title',public.mgr_club_name(new.champion_club)||' conquista '||co.name,
 'Campeão: '||public.mgr_club_name(new.champion_club)||coalesce('. Vice: '||public.mgr_club_name(runner),'')||coalesce('. Melhor atleta da equipe campeã: '||public.mgr_player_name(mvp.player_id)||' (nota '||mvp.rating||')','')||case when scorer.goals>0 then '. Artilheiro: '||public.mgr_player_name(scorer.player_id)||' ('||scorer.goals||' gols)' else '' end||'.',85,new.champion_club,mvp.player_id,s.id,
 jsonb_build_object('competition',co.id,'champion',new.champion_club,'runner_up',runner,'mvp',to_jsonb(mvp),'top_scorer',to_jsonb(scorer)));
 perform public.cw_cash(s.career_id,new.champion_club,case when co.kind='continental' then 30000 when co.kind='league' then 20000 else 10000 end,'competition_prize',s.id||':'||co.id,'Premiação por título: '||co.name);
 if runner is not null then perform public.cw_cash(s.career_id,runner,case when co.kind='continental' then 15000 when co.kind='league' then 10000 else 5000 end,'competition_runner',s.id||':'||co.id,'Premiação por vice: '||co.name);end if;
 if new.champion_club=(select club_id from public.mgr_coach where career_id=s.career_id) and s.id=(select primary_season from public.cw_world where career_id=s.career_id) then update public.cw_coach set credibility=least(100,credibility+4) where career_id=s.career_id;end if;
 return new;
end $$;
drop trigger if exists cw_competition_news_trg on public.season_competitions;
create trigger cw_competition_news_trg after insert or update of status on public.season_competitions for each row execute function public.cw_competition_news();
create or replace function public.cw_result_news()
returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c uuid;winner text;loser text;diff numeric;previous int;sc public.sim_competitions;leader record;second_team record;
begin
 if new.status<>'played' or (tg_op='UPDATE' and old.status='played') then return new;end if;
 select career_id into c from public.career_seasons where id=new.season_id;
 if not exists(select 1 from public.cw_world where career_id=c) then return new;end if;
 select * into sc from public.sim_competitions where id=new.competition_id;
 winner:=case when new.home_goals>new.away_goals then new.home_club when new.away_goals>new.home_goals then new.away_club else new.tie_winner end;
 loser:=case when winner=new.home_club then new.away_club when winner=new.away_club then new.home_club end;
 select b.strength-a.strength into diff from public.sim_clubs a,public.sim_clubs b where a.id=winner and b.id=loser;
 if diff>=12 then perform public.cw_news_add(c,'upset:'||new.id,'result',public.mgr_club_name(winner)||' surpreende favorito',new.home_goals||' × '||new.away_goals||': '||public.mgr_club_name(new.home_club)||' e '||public.mgr_club_name(new.away_club)||'.',65,winner,null,new.season_id,jsonb_build_object('fixture_id',new.id));end if;
 if new.tie_winner is not null and new.stage not in('league','group','swiss') then perform public.cw_news_add(c,'knockout:'||new.id,'result',public.mgr_club_name(new.tie_winner)||' avança de fase',public.mgr_club_name(loser)||' deixa a disputa de '||sc.name||'.',60,new.tie_winner,null,new.season_id,jsonb_build_object('fixture_id',new.id));end if;
 if new.player_match then perform public.cw_news_add(c,'user-result:'||new.id,'result',public.mgr_club_name(new.home_club)||' '||new.home_goals||' × '||new.away_goals||' '||public.mgr_club_name(new.away_club),sc.name||' · Rodada '||new.round_no||'.',90,new.coach_club,null,new.season_id,jsonb_build_object('fixture_id',new.id));end if;
 if sc.kind='league' and new.round_no>=8 and not exists(select 1 from public.season_fixtures fx where fx.season_id=new.season_id and fx.competition_id=new.competition_id and fx.round_no=new.round_no and fx.status='pending') then
  select * into leader from public.sim_standings(new.season_id,new.competition_id,null) where pos=1;
  select * into second_team from public.sim_standings(new.season_id,new.competition_id,null) where pos=2;
  if leader.points-second_team.points<=2 then perform public.cw_news_add(c,'race:'||new.season_id||':'||sc.id||':'||new.round_no,'race','Disputa pela liderança de '||sc.name,
   public.mgr_club_name(leader.club_id)||' e '||public.mgr_club_name(second_team.club_id)||' terminaram a rodada '||new.round_no||' separados por até dois pontos.',50,leader.club_id,null,new.season_id);end if;
 end if;
 select max(abs(f.home_goals-f.away_goals)) into previous from public.season_fixtures f join public.career_seasons s on s.id=f.season_id where s.career_id=c and f.status='played' and f.id<>new.id;
 if abs(new.home_goals-new.away_goals)>greatest(coalesce(previous,0),4) then perform public.cw_news_add(c,'record:'||new.id,'record','Maior goleada desta carreira',public.mgr_club_name(new.home_club)||' '||new.home_goals||' × '||new.away_goals||' '||public.mgr_club_name(new.away_club)||'. Recorde entre as partidas já disputadas nesta carreira.',75,winner,null,new.season_id);end if;
 return new;
end $$;
drop trigger if exists cw_result_news_trg on public.season_fixtures;
create trigger cw_result_news_trg after insert or update of status on public.season_fixtures for each row execute function public.cw_result_news();
commit;
