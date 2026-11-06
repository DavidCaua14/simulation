-- Ligas de fundo: correções encontradas no teste de ponta a ponta.
-- 3) Ao assumir clube de liga de fundo em outro calendário (ex.: Europa em agosto), o calendário novo já nasce com a liga;
--    antes ele nascia vazio, era encerrado e o técnico só estrearia na temporada seguinte.
-- 2) cw_attach_league materializa (sempre, mesmo se a liga já estiver na temporada) os clubes da liga em lote (antes: uma preparação de finanças por clube, ~5 s).
-- 1) Clube lazy ganha o modelo econômico (cw_club_economy_models) junto com as notas: cw_clubs.monthly_revenue não aceita nulo.

-- Grava notas por posição e valores-base de um clube de nível B (uma vez, vale para todas as carreiras).
create or replace function public.sim_ensure_club_catalog(p_club text)
returns integer language plpgsql security definer set search_path to 'public' as $$
declare n int:=0;
begin
 perform 1 from public.sim_clubs where id=p_club and lazy and catalog_ready_at is null for update;
 if not found then return 0;end if;
 insert into public.sim_player_ratings(player_id,pos,rating,eff)
 select player_id,array_agg(pos order by pos),array_agg(rating order by pos),array_agg(eff order by pos) from(
  with a as materialized (select x.player_id, to_jsonb(x) j from public.sim_player_attrs x join public.sim_players p on p.id=x.player_id where p.club_id=p_club and p.career_id is null)
  select p.id player_id, w.pos,
   round(sum(w.weight*(a.j->>w.attr)::numeric)/sum(w.weight),2) rating,
   round(sum(w.weight*(a.j->>w.attr)::numeric)/sum(w.weight)*greatest(coalesce(max(f.fit),0.5),case when w.pos=any(p.secondary_positions) then 0.97 else 0 end),2) eff
  from public.sim_players p join a on a.player_id=p.id join public.sim_role_weights w on true
  left join public.sim_position_fit f on f.from_pos=p.position and f.to_pos=w.pos
  group by p.id,w.pos,p.secondary_positions) t
 group by player_id
 on conflict(player_id) do nothing;
 get diagnostics n=row_count;
 insert into public.sim_player_base(player_id,rating,age0,age_estimated,potential,contract_years,salary0,role0)
 select x.id,x.rating,x.age0,x.age_estimated,x.potential,x.contract_years,
  greatest(greatest(50,ceil(power(greatest(1,x.rating-45),2)*.65+power(greatest(0,x.rating-75),2)*12))::bigint,
   round(public.cw_base_value(x.rating,x.age0,x.potential)*.0065)::bigint),
  case when x.is_youth then 'prospect' when x.rating>=82 then 'key' when x.rating>=74 then 'starter' else 'rotation' end
 from(select p.id,r.rating,p.is_youth,coalesce(p.age,case when p.is_youth then 19 else 26 end) age0,p.age is null age_estimated,
   least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)::int potential,
   1+(abs(hashtext(p.id)::bigint)%4)::int contract_years
  from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
  where p.career_id is null and p.club_id=p_club)x
 on conflict(player_id) do nothing;
 -- Modelo econômico do clube (mesma conta de 20261103181732_club_financial_scale.sql).
 insert into public.cw_club_economy_models(club_id,catalogue_payroll,monthly_commercial)
 select c.id,coalesce(sum(greatest(80,public.cw_salary_floor(p.id))) filter(where p.id is not null),0),
  greatest(1000,ceil(coalesce(sum(greatest(80,public.cw_salary_floor(p.id))) filter(where p.id is not null),0)*1.12))::bigint
 from public.sim_clubs c left join public.sim_players p on p.club_id=c.id and p.active and p.career_id is null where c.id=p_club group by c.id
 on conflict do nothing;
 update public.sim_clubs set catalog_ready_at=now() where id=p_club;
 return n;
end $$;


-- Liga de fundo entra na temporada da carreira: participantes, partidas e rodadas já vencidas resolvidas pelo modelo de fundo.
create or replace function public.cw_attach_league(p_career uuid, p_season uuid, p_comp text)
returns integer language plpgsql security definer set search_path to 'public' as $$
#variable_conflict use_column
declare co public.sim_competitions;ph jsonb;s public.cw_seasons;w public.cw_world;seed text;n int:=0;r record;step int;g int[];
begin
 select * into co from public.sim_competitions where id=p_comp;
 if co.id is null or not co.background or not co.active then return 0;end if;
 select * into s from public.cw_seasons where season_id=p_season and career_id=p_career;
 if s.season_id is null then raise exception 'Temporada sem calendário regional';end if;
 if s.region<>co.region then raise exception 'Liga % fora do calendário %',p_comp,s.region;end if;
 select * into w from public.cw_world where career_id=p_career;
 -- Clubes da liga no mundo da carreira (idempotente), mesmo quando a liga já nasceu com a temporada.
 if public.cw_is_hybrid(p_career) then
  -- Todos os clubes da liga entram no mundo de uma vez; finanças e contratos numa chamada só.
  insert into public.cw_world_clubs(career_id,club_id) select p_career,cc.club_id from public.sim_competition_clubs cc where cc.competition_id=p_comp
  on conflict do nothing;
  get diagnostics n=row_count;
  if n>0 or exists(select 1 from public.sim_competition_clubs cc where cc.competition_id=p_comp
    and not exists(select 1 from public.cw_clubs c where c.career_id=p_career and c.club_id=cc.club_id)) then
   perform public.cw_initialize_finances(p_career);
  end if;
  n:=0;
 else
  for r in select cc.club_id from public.sim_competition_clubs cc where cc.competition_id=p_comp order by cc.club_id loop
   perform public.cw_materialize_club(p_career,r.club_id);
  end loop;
 end if;
 if exists(select 1 from public.season_competitions where season_id=p_season and competition_id=p_comp) then return 0;end if;
 insert into public.season_participants(season_id,competition_id,club_id,division_key,origin)
  select p_season,p_comp,cc.club_id,co.region||':league','reference' from public.sim_competition_clubs cc where cc.competition_id=p_comp
  on conflict do nothing;
 ph:=public.sim_phase_at(p_comp,1);
 insert into public.season_competitions(season_id,competition_id,stage) values(p_season,p_comp,ph->>'id');
 perform public.sim_phase_create(p_season,p_comp,ph->>'id',null);
 select rt.seed::text into seed from public.cw_runtime rt where rt.career_id=p_career;
 seed:=coalesce(seed,p_career::text);
 step:=greatest(1,330/greatest(coalesce((co.rules->>'calendar_rounds')::int,38)-1,1));
 for r in select f.id,f.home_club,f.away_club,hc.strength hs,ac.strength aws,
   least(s.ends_on+s.calendar_shift,s.starts_on+s.calendar_shift+14+(f.round_no-1)*step) due
  from public.season_fixtures f join public.sim_clubs hc on hc.id=f.home_club join public.sim_clubs ac on ac.id=f.away_club
  where f.season_id=p_season and f.competition_id=p_comp and f.status='pending' loop
  continue when r.due>=w.today;
  g:=public.cw_bg_goals(seed,p_comp,s.year,r.home_club,r.away_club,r.hs,r.aws);
  update public.season_fixtures set home_goals=g[1],away_goals=g[2],status='played',played_at=now(),
   stats=jsonb_build_object('simulation','background','algorithm',1,'yellows',jsonb_build_array(0,0),'reds',jsonb_build_array(0,0))
  where id=r.id;
  insert into public.cw_fixture_dates(fixture_id,season_id,career_id,due_on) values(r.id,p_season,p_career,r.due);
  n:=n+1;
 end loop;
 perform public.cw_schedule(p_season);
 return n;
end $$;


create or replace function public.cw_comp_wanted(p_season uuid, p_comp text)
returns boolean language sql stable security definer set search_path to 'public' as $$
 select not co.background
  or exists(select 1 from public.season_competitions sc where sc.season_id=p_season and sc.competition_id=co.id)
  or exists(select 1 from public.career_seasons s join public.mgr_coach mc on mc.career_id=s.career_id and mc.status='employed'
            join public.sim_competition_clubs cc on cc.club_id=mc.club_id and cc.competition_id=co.id where s.id=p_season)
  -- clube que o técnico está assumindo nesta transação (mgr_offer_respond)
  or exists(select 1 from public.sim_competition_clubs cc where cc.competition_id=co.id and cc.club_id=nullif(current_setting('cw.incoming_club',true),''))
 from public.sim_competitions co where co.id=p_comp
$$;

CREATE OR REPLACE FUNCTION public.mgr_offer_respond(p_offer uuid, p_accept boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
 car public.careers;o public.season_offers;c public.mgr_coach;w public.cw_world;
 target public.career_seasons;sid uuid;spell uuid;region text;
 keep_closed boolean:=false;off_season boolean:=false;
begin
 car:=public.mgr_lock();
 select * into w from public.cw_world where career_id=car.id;
 select * into o from public.season_offers where id=p_offer and career_id=car.id and kind='coach' for update;
 if not found then raise exception 'Proposta inexistente';end if;
 if o.status='accepted' and p_accept then
  return jsonb_build_object('ok',true,'accepted',true,'club_id',o.from_club,'today',w.today,
   'off_season',(select s.status='finished' or w.today<public.cw_start(s.region,s.year) from public.career_seasons s where s.id=w.primary_season),
   'state_version',(select version from public.cw_runtime where career_id=car.id));
 end if;
 if o.status<>'pending' or o.expires_on<w.today then raise exception 'Proposta encerrada';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then raise exception 'Termine a partida em andamento';end if;
 if p_accept then
  region:=public.cw_region(o.from_club);
  -- Calendário criado agora já inclui a liga de fundo do clube que está sendo aceito (cw_comp_wanted).
  perform set_config('cw.incoming_club',o.from_club,true);
  if public.cw_runtime_enabled(car.id) then
   perform public.cw_simulate_due(car.id,24);
   select * into w from public.cw_world where career_id=car.id;
   sid:=public.cw_activate_region(car.id,region);
  else
   select ws.season_id into sid from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id
    where ws.career_id=car.id and ws.region=region and s.status='active' order by ws.starts_on limit 1;
  end if;
  if w.needs_sync then raise exception 'Atualize os resultados do mundo antes de trocar de clube';end if;
  -- A completed current season is a valid employment context during its off-season.
  -- Keep its club, summary, results and sequence untouched; only the coach changes club.
  if sid is null then
   select s.id into sid from public.career_seasons s where s.id=w.primary_season and s.career_id=car.id
    and s.region=region and s.status='finished' and s.year=public.cw_year(region,w.today);
  end if;
  select * into target from public.career_seasons where id=sid and career_id=car.id;
  keep_closed:=coalesce(target.id=w.primary_season and target.status='finished'
   and target.region=region and target.year=public.cw_year(region,w.today),false);
  -- Moving to a country whose year is already closed prepares its next calendar,
  -- without advancing the save date or reopening that country's historical results.
  if target.status='finished' and not keep_closed and public.cw_runtime_enabled(car.id) then
   sid:=public.cw_create_region(car.id,region,greatest(target.year+1,public.cw_year(region,w.today)));
   select * into target from public.career_seasons where id=sid and career_id=car.id;
  end if;
  if sid is null or (target.status is distinct from 'active' and not keep_closed) then
   raise exception 'Atualize o calendário regional antes de assumir o clube';
  end if;
  -- Liga de fundo (nível B): só ganha partidas nesta carreira quando o técnico assume um clube dela.
  perform public.cw_attach_club_leagues(car.id,sid,o.from_club);
  off_season:=keep_closed or w.today<public.cw_start(target.region,target.year);
  if (select cash-public.cw_reserved(car.id,o.from_club) from public.cw_clubs where career_id=car.id and club_id=o.from_club)<coalesce(o.bonus_coins,0)+2*o.salary
   or greatest(0,public.cw_available_budget(car.id,o.from_club)-coalesce(o.bonus_coins,0)-2*o.salary)<coalesce(o.budget_guarantee,0) then
   raise exception 'O clube não pode sustentar os termos do contrato';
  end if;
  select * into c from public.mgr_coach where career_id=car.id;
  if c.status='employed' then perform public.mgr_end_spell(car.id,'left');end if;
  if not keep_closed then perform public.cw_promote_season(car.id,sid,o.from_club);end if;
  perform public.mgr_init_world(car.id);
  perform public.cw_initialize_finances(car.id);
  spell:=public.mgr_start_spell(car.id,o.from_club);
  update public.cw_coach set monthly_salary=o.salary,contract_until=(w.today+make_interval(years=>o.contract_years))::date,
   promised_budget=o.budget_guarantee where career_id=car.id;
  update public.cw_clubs set distress_since=case when financial_risk>=75 then w.today else distress_since end
   where career_id=car.id and club_id=o.from_club;
  insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
   values(car.id,spell,o.from_club,w.today,(w.today+make_interval(years=>o.contract_years))::date,o.salary);
  if o.bonus_coins>0 then
   perform public.cw_cash(car.id,o.from_club,-o.bonus_coins,'coach_signing',o.id::text,'Luvas do treinador');
   perform public.econ_apply(car.id,'coins',o.bonus_coins,'coach_signing',o.id::text);
  end if;
  update public.season_offers set status='accepted',responded_at=now() where id=o.id;
  update public.season_offers set status='expired',responded_at=now() where career_id=car.id and kind='coach' and status='pending';
  perform public.cw_news_add(car.id,'coach-hired:'||spell,'job',public.mgr_club_name(o.from_club)||' anuncia novo treinador',
   'Contrato por '||o.contract_years||' anos. A temporada e os resultados existentes continuam.',98,o.from_club);
 else
  update public.season_offers set status='declined',responded_at=now() where id=o.id;
 end if;
 -- Other tabs must refresh after this employment decision before preparing another advance.
 update public.cw_runtime set version=version+1 where career_id=car.id;
 return jsonb_build_object('ok',true,'accepted',p_accept,'club_id',o.from_club,'off_season',off_season,'today',w.today,
  'state_version',(select version from public.cw_runtime where career_id=car.id));
end $function$;

-- 4) Receita comercial de clube sem modelo econômico (clube lazy ainda não preparado): estimativa pela força,
--    mesma curva dos modelos existentes (força 58 ~ 3,7 mil; 74 ~ 20,7 mil; 88 ~ 94 mil por mês). Clubes com modelo não mudam.
create or replace function public.cw_commercial_income(p_club text)
returns bigint language sql stable security definer set search_path to 'public' as $$
 select coalesce((select monthly_commercial from public.cw_club_economy_models where club_id=p_club),
  (select greatest(1000,round(3681*exp(.108*(strength-58))))::bigint from public.sim_clubs where id=p_club))
$$;
