-- A valid job offer can be signed after the regional season has finished.
-- Installation changes function definitions only; existing saves/offers are not rewritten.
begin;

create or replace function public.mgr_offer_respond(p_offer uuid,p_accept boolean)
returns jsonb language plpgsql security definer set search_path=public as $function$
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

revoke all on function public.mgr_offer_respond(uuid,boolean) from public,anon;
grant execute on function public.mgr_offer_respond(uuid,boolean) to authenticated;
commit;
