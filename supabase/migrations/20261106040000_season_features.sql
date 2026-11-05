-- Fase 4: objetivos (a meta da liga decide a demissão), vagas com candidatura, prêmio de fim de temporada.
-- Os ajustes em funções existentes (mgr_season_end, mgr_after_user_match, cw_jobs_tick, career_hub_read)
-- ficam em 20261106050000_season_features_patches.sql, gerado a partir das definições em produção.

begin;

-- 1. Situação da meta da liga do técnico: posição, meta e risco (ok, atenção, perigo)
create or replace function public.cw_league_status(p_career uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare w public.cw_world;c public.mgr_coach;o public.mgr_objectives;pos int;played int;n int;
begin
 select * into w from public.cw_world where career_id=p_career;
 select * into c from public.mgr_coach where career_id=p_career;
 if w.career_id is null or c.status is distinct from 'employed' then return null;end if;
 select * into o from public.mgr_objectives where career_id=p_career and season_id=w.primary_season and club_id=c.club_id
  and kind='league_pos' order by priority desc limit 1;
 if not found then return null;end if;
 select t.pos,t.played into pos,played from public.sim_standings(w.primary_season,o.competition_id,null) t where t.club_id=c.club_id;
 select count(*) into n from public.season_participants where season_id=w.primary_season and competition_id=o.competition_id;
 return jsonb_build_object('competition_id',o.competition_id,'target',o.target,'label',o.label,'status',o.status,
  'pos',pos,'played',played,'teams',n,'gap',pos-o.target,'tolerance',2,
  'risk',case when coalesce(played,0)<3 or pos<=o.target then 'ok' when pos<=o.target+2 then 'attention' else 'danger' end);
end $$;

-- 2. Prêmio de fim de temporada: pago uma única vez por temporada (chave primária = temporada)
create table if not exists public.cw_season_rewards(
 season_id uuid primary key references public.career_seasons(id) on delete cascade,
 career_id uuid not null references public.careers(id) on delete cascade,
 club_id text,
 coins integer not null default 0,
 reputation numeric not null default 0,
 detail jsonb not null default '{}'::jsonb,
 seen boolean not null default false,
 created_at timestamptz not null default now());
alter table public.cw_season_rewards enable row level security;
revoke all on public.cw_season_rewards from anon,authenticated;

create or replace function public.career_season_reward_seen(p_season uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.careers;
begin
 c:=public.cw_read_career();
 update public.cw_season_rewards set seen=true where season_id=p_season and career_id=c.id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.career_season_reward_seen(uuid) from public,anon;
grant execute on function public.career_season_reward_seen(uuid) to authenticated;

-- 3. Vagas: nascem quando a IA demite um técnico; a candidatura só ocupa linha enquanto está aberta
create table if not exists public.cw_job_vacancies(
 id uuid primary key default gen_random_uuid(),
 career_id uuid not null references public.careers(id) on delete cascade,
 club_id text not null references public.sim_clubs(id),
 opened_on date not null,
 closes_on date not null,
 reason text not null,
 unique(career_id,club_id));
create table if not exists public.cw_job_applications(
 id uuid primary key default gen_random_uuid(),
 career_id uuid not null references public.careers(id) on delete cascade,
 vacancy_id uuid not null references public.cw_job_vacancies(id) on delete cascade,
 applied_on date not null,
 answer_on date not null,
 unique(career_id,vacancy_id));
alter table public.cw_job_vacancies enable row level security;
alter table public.cw_job_applications enable row level security;
revoke all on public.cw_job_vacancies,public.cw_job_applications from anon,authenticated;

create table if not exists public.cw_job_rules(
 id boolean primary key default true check(id),
 max_open_applications integer not null default 3,
 answer_min_days integer not null default 3,
 answer_max_days integer not null default 7,
 vacancy_min_days integer not null default 10,
 vacancy_max_days integer not null default 20,
 fire_gap integer not null default 6,
 fire_daily_chance numeric not null default .03,
 min_played integer not null default 8);
insert into public.cw_job_rules default values on conflict do nothing;
alter table public.cw_job_rules enable row level security;
revoke all on public.cw_job_rules from anon,authenticated;

-- Reputação mínima que o clube pede, pela mesma régua das propostas (mgr_make_offer)
create or replace function public.cw_required_reputation(p_career uuid,p_club text) returns numeric
language sql stable security definer set search_path=public as $$
 select greatest(0,round((c.prestige-55-(coalesce(k.credibility,65)-65)*.18)/.32,1))
 from public.cw_clubs c left join public.cw_coach k on k.career_id=c.career_id
 where c.career_id=p_career and c.club_id=p_club
$$;

-- Força coletiva e elenco de um clube (proposta aberta ou vaga aberta da própria carreira). Só leitura.
create or replace function public.cw_club_preview(p_career uuid,p_club text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare w public.cw_world;own text;day int;
begin
 select * into w from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 day:=coalesce(w.elapsed_days,0);
 return jsonb_build_object(
  'club_id',p_club,
  'division',(select co.short_name from public.season_participants pa join public.sim_competitions co on co.id=pa.competition_id and co.kind='league'
    where pa.season_id=w.primary_season and pa.club_id=p_club limit 1),
  'strength',public.cw_club_strength(p_career,p_club,null,day),
  'current_club',own,
  'current_strength',case when own is not null then public.cw_club_strength(p_career,own,null,day) end,
  'squad',coalesce((select jsonb_agg(jsonb_build_object('id',x.player_id,'name',x.name,'pos',x.pos,'age',x.age,'rating',x.rating)
     order by x.ord,x.rating desc,x.name) from(
    select mp.player_id,coalesce(sp.short_name,sp.full_name) name,sp.position pos,ps.sort ord,
     (cp.age_at_start+floor((w.today-w.started_on)/365.25))::int age,round(r.rating+coalesce(dv.d_rating,0))::int rating
    from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
    left join public.sim_positions ps on ps.code=sp.position
    join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
    left join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
    left join public.cw_player_dev dv on dv.career_id=mp.career_id and dv.player_id=mp.player_id
    where mp.career_id=p_career and mp.club_id=p_club)x),'[]'::jsonb));
end $$;

create or replace function public.career_offer_club(p_offer uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare car public.careers;o public.season_offers;
begin
 car:=public.cw_read_career();
 select * into o from public.season_offers where id=p_offer and career_id=car.id and kind='coach' and status='pending';
 if not found then raise exception 'Proposta inexistente ou encerrada';end if;
 return public.cw_club_preview(car.id,o.from_club);
end $$;

create or replace function public.career_vacancy_club(p_vacancy uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare car public.careers;v public.cw_job_vacancies;
begin
 car:=public.cw_read_career();
 select * into v from public.cw_job_vacancies where id=p_vacancy and career_id=car.id;
 if not found then raise exception 'Vaga encerrada';end if;
 return public.cw_club_preview(car.id,v.club_id);
end $$;

create or replace function public.career_vacancies() returns jsonb
language plpgsql stable security definer set search_path=public as $$
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
    'strength',public.cw_club_strength(car.id,v.club_id,null,coalesce(w.elapsed_days,0)),
    'division',(select co.short_name from public.season_participants pa join public.sim_competitions co on co.id=pa.competition_id and co.kind='league'
      where pa.season_id=w.primary_season and pa.club_id=v.club_id limit 1),
    'applied',a.id is not null,'answer_in',case when a.id is not null then greatest(0,a.answer_on-w.today) end)
    order by v.closes_on,v.club_id)
   from public.cw_job_vacancies v left join public.cw_job_applications a on a.vacancy_id=v.id and a.career_id=car.id
   where v.career_id=car.id and v.club_id is distinct from own),'[]'::jsonb));
end $$;

create or replace function public.career_vacancy_apply(p_vacancy uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare car public.careers;v public.cw_job_vacancies;w public.cw_world;r public.cw_job_rules;own text;days int;
begin
 car:=public.mgr_lock();
 select * into r from public.cw_job_rules;
 select * into w from public.cw_world where career_id=car.id;
 select * into v from public.cw_job_vacancies where id=p_vacancy and career_id=car.id;
 if not found or v.closes_on<w.today then raise exception 'Vaga encerrada';end if;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 if v.club_id is not distinct from own then raise exception 'Você já treina este clube';end if;
 if exists(select 1 from public.cw_job_applications where career_id=car.id and vacancy_id=v.id) then raise exception 'Candidatura já enviada';end if;
 if (select count(*) from public.cw_job_applications where career_id=car.id)>=r.max_open_applications then
  raise exception 'Limite de % candidaturas abertas. Aguarde uma resposta.',r.max_open_applications;
 end if;
 days:=r.answer_min_days+floor(public.cw_random(car.id::text||':apply:'||v.id)*(r.answer_max_days-r.answer_min_days+1))::int;
 insert into public.cw_job_applications(career_id,vacancy_id,applied_on,answer_on) values(car.id,v.id,w.today,w.today+days);
 update public.cw_runtime set version=version+1 where career_id=car.id;
 return public.career_vacancies();
end $$;

revoke all on function public.career_offer_club(uuid),public.career_vacancy_club(uuid),public.career_vacancies(),public.career_vacancy_apply(uuid) from public,anon;
grant execute on function public.career_offer_club(uuid),public.career_vacancy_club(uuid),public.career_vacancies(),public.career_vacancy_apply(uuid) to authenticated;

-- Diário: a IA demite técnicos de clubes muito abaixo do esperado (abre vaga), vagas vencidas são preenchidas
-- pela IA e candidaturas vencidas recebem resposta.
create or replace function public.cw_vacancies_tick(p_career uuid) returns void
language plpgsql security definer set search_path=public as $$
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
  where v.career_id=p_career and v.closes_on<w.today loop
  if a.app is not null then
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Vaga preenchida',
    public.mgr_club_name(a.club_id)||' contratou outro treinador antes de responder à sua candidatura.',a.club_id);
  end if;
  delete from public.cw_job_vacancies where id=a.id;
 end loop;

 -- respostas das candidaturas
 for a in select ap.id,ap.vacancy_id,v.club_id from public.cw_job_applications ap join public.cw_job_vacancies v on v.id=ap.vacancy_id
  where ap.career_id=p_career and ap.answer_on<=w.today loop
  req:=public.cw_required_reputation(p_career,a.club_id);
  select c.prestige into prestige from public.cw_clubs c where c.career_id=p_career and c.club_id=a.club_id;
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
   delete from public.cw_job_vacancies where id=a.vacancy_id;
  else
   perform public.mgr_msg(p_career,w.primary_season,w.elapsed_days,'board','Candidatura recusada: '||public.mgr_club_name(a.club_id),
    format('A diretoria preferiu um nome mais experiente. Para o porte do clube, ela pede reputação %s; a sua é %s (credibilidade %s também pesa).',
     round(req),round(rep),round(cred)),a.club_id);
   delete from public.cw_job_applications where id=a.id;
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
end $$;

commit;
