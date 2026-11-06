-- Propostas e vagas de clubes das ligas de fundo (nível B). Ver docs/banco-hibrido.md, seção "Ligas de fundo".
alter table public.cw_job_rules add column if not exists foreign_daily_chance numeric not null default 0.04;
comment on column public.cw_job_rules.foreign_daily_chance is 'Chance diária de checar demissões numa liga de fundo (tabela calculada, cw_bg_table).';

CREATE OR REPLACE FUNCTION public.mgr_region_league_clubs(p_career uuid, p_region text)
 RETURNS TABLE(o_club text, o_league text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_res jsonb;
begin
  -- temporada ativa da região: participantes atuais
  if exists (select 1 from public.career_seasons s where s.career_id = p_career and s.region = p_region and s.status = 'active') then
    return query
      select sp.club_id, sp.competition_id from public.season_participants sp
        join public.career_seasons s on s.id = sp.season_id
       where s.career_id = p_career and s.region = p_region and s.status = 'active' and sp.division_key is not null
      union all
      select cc.club_id, cc.competition_id from public.sim_competition_clubs cc
        join public.sim_competitions c on c.id = cc.competition_id
       where c.region = p_region and c.kind = 'league' and c.active and c.background
         and not exists (select 1 from public.season_participants sp join public.career_seasons s on s.id = sp.season_id
                          where s.career_id = p_career and s.region = p_region and s.status = 'active' and sp.club_id = cc.club_id);
    return;
  end if;
  -- última transição da região (quem subiu/caiu no fim da última temporada jogada lá)
  select t.result into v_res from public.season_transitions t
   where t.career_id = p_career and t.region = p_region order by t.year desc, t.id desc limit 1;
  if v_res is not null then
    return query
      select x.value #>> '{}', l.key from jsonb_each(v_res -> 'leagues') l cross join lateral jsonb_array_elements(l.value) x;
    return;
  end if;
  return query
    select cc.club_id, cc.competition_id from public.sim_competition_clubs cc
      join public.sim_competitions c on c.id = cc.competition_id
     where c.region = p_region and c.kind = 'league' and c.active;
end;
$function$;

CREATE OR REPLACE FUNCTION public.cw_required_reputation(p_career uuid, p_club text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select greatest(0,round((coalesce(c.prestige,s.strength)-55-(coalesce(k.credibility,(select credibility from public.cw_coach where career_id=p_career),65)-65)*.18)/.32,1))
 from public.sim_clubs s left join public.cw_clubs c on c.career_id=p_career and c.club_id=s.id left join public.cw_coach k on k.career_id=c.career_id
 where s.id=p_club
$function$;

CREATE OR REPLACE FUNCTION public.cw_vacancies_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;r public.cw_job_rules;own text;rep numeric;cred numeric;comp record;t record;a record;
 req numeric;pay bigint;budget bigint;oid uuid;days int;prestige numeric;
begin
 select * into w from public.cw_world where career_id=p_career;
 if w.career_id is null then return;end if;
 select * into r from public.cw_job_rules;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 select reputation into rep from public.mgr_coach where career_id=p_career;
 select coalesce(credibility,65) into cred from public.cw_coach where career_id=p_career;

 -- vagas vencidas: a IA contratou outro técnico
 for a in select v.id,v.club_id,ap.id app from public.cw_job_vacancies v left join public.cw_job_applications ap on ap.vacancy_id=v.id
  where v.career_id=p_career and v.closes_on<w.today and not v.closed loop
  if a.app is not null then
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Vaga preenchida',
    public.mgr_club_name(a.club_id)||' contratou outro treinador antes de responder à sua candidatura.',a.club_id);
  end if;
  update public.cw_job_vacancies set closed=true where id=a.id;
  delete from public.cw_job_applications where vacancy_id=a.id;
 end loop;
 delete from public.cw_job_vacancies where career_id=p_career and closed and closes_on<w.today-60;

 -- respostas das candidaturas
 for a in select ap.id,ap.vacancy_id,v.club_id from public.cw_job_applications ap join public.cw_job_vacancies v on v.id=ap.vacancy_id
  where ap.career_id=p_career and ap.answer_on<=w.today loop
  req:=public.cw_required_reputation(p_career,a.club_id);
  select coalesce(c.prestige,s.strength) into prestige from public.sim_clubs s left join public.cw_clubs c on c.career_id=p_career and c.club_id=s.id where s.id=a.club_id;
  if rep>=req then
   pay:=greatest(70,round(coalesce(prestige,50)*2.5+cred));
   budget:=greatest(0,public.cw_available_budget(p_career,a.club_id)-2*pay);
   insert into public.season_offers(career_id,season_id,from_club,kind,status,pitch,salary,contract_years,budget_guarantee,expires_on,expires_day,bonus_coins,context)
   values(p_career,w.primary_season,a.club_id,'coach','pending',
    'Sua candidatura convenceu a diretoria. Queremos você no comando.',pay,2,budget,public.cw_deadline(w.today),
    w.elapsed_days+(select max_negotiation_days from public.cw_rules),0,jsonb_build_object('source','application'))
   returning id into oid;
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Candidatura aceita: '||public.mgr_club_name(a.club_id),
    format('A diretoria aprovou seu nome: sua reputação (%s) atende ao porte do clube (pede %s). A proposta está em Carreira > Propostas.',round(rep),round(req)),a.club_id);
   delete from public.cw_job_applications where id=a.id;
   update public.cw_job_vacancies set closed=true,closes_on=w.today where id=a.vacancy_id;
  else
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Candidatura recusada: '||public.mgr_club_name(a.club_id),
    format('A diretoria preferiu um nome mais experiente. Para o porte do clube, ela pede reputação %s; a sua é %s (credibilidade %s também pesa).',
     round(req),round(rep),round(cred)),a.club_id);
   delete from public.cw_job_applications where id=a.id;
   update public.cw_job_vacancies set rejected=true where id=a.vacancy_id;
  end if;
 end loop;

 -- demissões da IA: clube muito abaixo da posição esperada pela força
 for comp in select sc.competition_id from public.season_competitions sc join public.sim_competitions co on co.id=sc.competition_id
  where sc.season_id=w.primary_season and co.kind='league' loop
  for t in select s.club_id,s.pos,s.played,
    rank() over(order by c.prestige desc,s.club_id) expected
   from public.sim_standings(w.primary_season,comp.competition_id,null) s join public.cw_clubs c on c.career_id=p_career and c.club_id=s.club_id loop
   continue when t.club_id is not distinct from own or t.played<r.min_played or t.pos-t.expected<r.fire_gap;
   continue when exists(select 1 from public.cw_job_vacancies v where v.career_id=p_career and v.club_id=t.club_id);
   continue when public.cw_random(p_career::text||':fire:'||t.club_id||':'||w.today)>=r.fire_daily_chance;
   days:=r.vacancy_min_days+floor(public.cw_random(p_career::text||':vacancy:'||t.club_id||':'||w.today)*(r.vacancy_max_days-r.vacancy_min_days+1))::int;
   insert into public.cw_job_vacancies(career_id,club_id,opened_on,closes_on,reason)
   values(p_career,t.club_id,w.today,w.today+days,format('%sº lugar, abaixo do esperado',t.pos)) on conflict do nothing;
   perform public.cw_news_add(p_career,'ai-fired:'||t.club_id||':'||w.today,'job',public.mgr_club_name(t.club_id)||' demite o treinador',
    format('Com o time em %sº lugar, a diretoria abriu a vaga. Candidaturas em Carreira > Propostas.',t.pos),90,t.club_id);
  end loop;
 end loop;

 -- Ligas de fundo (nível B): uma checagem sorteada por dia, pela tabela calculada (nada é gravado além da vaga).
 if rep>=(select foreign_reputation from public.cw_runtime_rules)
  and public.cw_random(p_career::text||':bgfire:'||w.today)<r.foreign_daily_chance then
  select co.id into comp from public.sim_competitions co
   where co.background and co.active and co.kind='league'
    and not exists(select 1 from public.season_competitions sc where sc.season_id=w.primary_season and sc.competition_id=co.id)
   order by public.cw_random(p_career::text||':bgcomp:'||w.today||':'||co.id) limit 1;
  if comp.id is not null then
   for t in select b.club_id,b.pos,b.played,rank() over(order by c.strength desc,b.club_id) expected
    from public.cw_bg_table(p_career,comp.id,w.today) b join public.sim_clubs c on c.id=b.club_id
    order by public.cw_random(p_career::text||':bgpick:'||w.today||':'||b.club_id) loop
    continue when t.club_id is not distinct from own or t.played<r.min_played or t.pos-t.expected<r.fire_gap;
    continue when exists(select 1 from public.cw_job_vacancies v where v.career_id=p_career and v.club_id=t.club_id);
    days:=r.vacancy_min_days+floor(public.cw_random(p_career::text||':vacancy:'||t.club_id||':'||w.today)*(r.vacancy_max_days-r.vacancy_min_days+1))::int;
    insert into public.cw_job_vacancies(career_id,club_id,opened_on,closes_on,reason)
    values(p_career,t.club_id,w.today,w.today+days,format('%sº lugar, abaixo do esperado',t.pos)) on conflict do nothing;
    perform public.cw_news_add(p_career,'ai-fired:'||t.club_id||':'||w.today,'job',public.mgr_club_name(t.club_id)||' demite o treinador',
     format('Com o time em %sº lugar, a diretoria abriu a vaga. Candidaturas em Carreira > Propostas.',t.pos),80,t.club_id);
    exit;
   end loop;
  end if;
 end if;
end $function$;

CREATE OR REPLACE FUNCTION public.career_vacancies()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare car public.careers;w public.cw_world;own text;rep numeric;lim int;
begin
 car:=public.cw_read_career();
 select * into w from public.cw_world where career_id=car.id;
 select club_id,reputation into own,rep from public.mgr_coach where career_id=car.id and status='employed';
 if rep is null then select reputation into rep from public.mgr_coach where career_id=car.id;end if;
 select max_open_applications into lim from public.cw_job_rules;
 return jsonb_build_object(
  'limit',lim,
  'open_applications',(select count(*) from public.cw_job_applications a where a.career_id=car.id),
  'reputation',round(rep,1),
  'vacancies',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'club_id',v.club_id,'reason',v.reason,
    'closes_in',greatest(0,v.closes_on-w.today),'required_reputation',public.cw_required_reputation(car.id,v.club_id),
    'strength',case when exists(select 1 from public.mgr_players mp where mp.career_id=car.id and mp.club_id=v.club_id)
      then public.cw_club_strength(car.id,v.club_id,null,coalesce(w.elapsed_days,0)) else (select strength from public.sim_clubs where id=v.club_id) end,
    'country',(select country from public.sim_clubs where id=v.club_id),
    'division',(select co.short_name from public.season_participants pa join public.sim_competitions co on co.id=pa.competition_id and co.kind='league'
      where pa.season_id=w.primary_season and pa.club_id=v.club_id limit 1)
     ,'league',(select co.short_name from public.sim_competition_clubs cc join public.sim_competitions co on co.id=cc.competition_id and co.kind='league'
      where cc.club_id=v.club_id order by co.background desc limit 1),
    'applied',a.id is not null,'rejected',v.rejected,'answer_in',case when a.id is not null then greatest(0,a.answer_on-w.today) end)
    order by v.closes_on,v.club_id)
   from public.cw_job_vacancies v left join public.cw_job_applications a on a.vacancy_id=v.id and a.career_id=car.id
   where v.career_id=car.id and not v.closed and v.club_id is distinct from own),'[]'::jsonb));
end $function$;
