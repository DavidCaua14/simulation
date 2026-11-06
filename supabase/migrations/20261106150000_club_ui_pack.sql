-- Pacote de interface do clube (2026-11-06):
--  1. Estrutura (instalações) pertence ao clube e começa sempre no nível 1. Ao trocar de clube, as
--     instalações do clube anterior são descartadas (economiza o banco; quem volta recomeça do nível 1).
--  2. Treino livre: gasta 1 energia e aumenta o entrosamento com uma formação sem jogar.
--  3. Olheiros por missão: o treinador escolhe posição e perfil; os olheiros trazem relatórios.
--  4. Busca de mercado com habilidade, idade, valor, situação contratual e ordenação.

-- 1. Estrutura -----------------------------------------------------------------------------------
create or replace function public.cw_dev_ensure_club(p_career uuid, p_club text)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare lvl smallint;form text;
begin
 if p_club is null or not exists(select 1 from public.cw_clubs where career_id=p_career and club_id=p_club) then return;end if;
 -- Instalações: sempre a estrutura inicial (nível 1). Recriadas se foram descartadas numa troca de clube.
 insert into public.cw_facilities(career_id,club_id,kind,level,initial_level)
 select p_career,p_club,k,1,1 from unnest(array['training','youth','medical','stadium']) k on conflict do nothing;
 if exists(select 1 from public.cw_training where career_id=p_career and club_id=p_club) then return;end if;
 select public.cw_level_from_prestige(prestige) into lvl from public.cw_clubs where career_id=p_career and club_id=p_club;
 insert into public.cw_training(career_id,club_id) values(p_career,p_club) on conflict do nothing;
 insert into public.cw_set_pieces(career_id,club_id) values(p_career,p_club) on conflict do nothing;
 insert into public.cw_staff(career_id,club_id,role,level,initial_level)
 select p_career,p_club,r,greatest(1,lvl-case when r in('psychologist','scout') then 1 else 0 end),greatest(1,lvl-case when r in('psychologist','scout') then 1 else 0 end)
 from unnest(array['assistant','fitness','physio','psychologist','scout','youth']) r on conflict do nothing;
 -- A formação em uso já é conhecida pelo elenco: começa entrosada (preserva o rendimento atual).
 select coalesce((select formation from public.mgr_lineups where career_id=p_career and club_id=p_club),
  (select formation from public.mgr_ai_clubs where career_id=p_career and club_id=p_club)) into form;
 if form is not null and exists(select 1 from public.sim_formations where id=form) then
  insert into public.cw_familiarity(career_id,club_id,formation,value) values(p_career,p_club,form,100) on conflict do nothing;
 end if;
end $function$;

-- Troca de clube (ou demissão): a estrutura do clube anterior é descartada.
create or replace function public.cw_coach_facilities_trg()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
begin
 if tg_op='UPDATE' and new.club_id is not distinct from old.club_id and new.status is not distinct from old.status then return null;end if;
 delete from public.cw_facilities where career_id=new.career_id
  and (new.status<>'employed' or new.club_id is null or club_id<>new.club_id);
 return null;
end $function$;
drop trigger if exists cw_coach_facilities on public.mgr_coach;
create trigger cw_coach_facilities after insert or update of club_id, status on public.mgr_coach
 for each row execute function public.cw_coach_facilities_trg();

-- Carreiras atuais: estrutura de clubes antigos descartada; a do clube atual volta ao início.
delete from public.cw_facilities f where not exists(
 select 1 from public.mgr_coach c where c.career_id=f.career_id and c.status='employed' and c.club_id=f.club_id);
update public.cw_facilities set level=1,initial_level=1,target_level=null,started_on=null,building_until=null
 where level<>1 or initial_level<>1 or building_until is not null;

-- 2. Treino livre ---------------------------------------------------------------------------------
-- p_quality (0–1) é o aproveitamento do minijogo do treino; o servidor limita o ganho.
create or replace function public.career_free_training(p_formation text, p_quality numeric default 1)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare car public.careers;own text;today date;before numeric;after numeric;gain int;base numeric;q numeric;fac int;
begin
 car:=public.mgr_lock();
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 if own is null then raise exception 'Você precisa estar em um clube para treinar.';end if;
 if not exists(select 1 from public.sim_formations where id=p_formation) then raise exception 'Formação inválida.';end if;
 if exists(select 1 from public.mgr_matches where career_id=car.id and status='live' and user_side is not null) then
  raise exception 'Termine a partida antes de treinar.';
 end if;
 perform public.cw_dev_ensure_club(car.id,own);
 select w.today into today from public.cw_world w where w.career_id=car.id;
 before:=public.cw_familiarity_value(car.id,own,p_formation);
 if before>=100 then raise exception 'O elenco já domina esta formação.';end if;
 -- energia: primeiro a livre, depois a bônus
 if car.energy>0 then perform public.econ_apply(car.id,'energy',-1,'free_training',p_formation);
 else perform public.econ_apply(car.id,'bonus_energy',-1,'free_training',p_formation);end if;
 fac:=public.cw_fac_level(car.id,own,'training');
 base:=4+floor(fac/2.0)+case when (select focus from public.cw_training where career_id=car.id and club_id=own)='tactical' then 2 else 0 end;
 q:=greatest(0,least(1,coalesce(p_quality,0)));
 gain:=greatest(2,round(base*(.5+.5*q)))::int;
 after:=least(100,before+gain);
 insert into public.cw_familiarity(career_id,club_id,formation,value,last_used) values(car.id,own,p_formation,after,today)
 on conflict(career_id,club_id,formation) do update set value=excluded.value,last_used=excluded.last_used;
 return jsonb_build_object('ok',true,'formation',p_formation,'before',round(before),'after',round(after),'gain',round(after-before),
  'quality',round(q*100),'facility',fac,
  'energy',(select energy from public.careers where id=car.id),'bonus_energy',(select bonus_energy from public.careers where id=car.id));
end $function$;
revoke all on function public.career_free_training(text,numeric) from public, anon;
grant execute on function public.career_free_training(text,numeric) to authenticated;

-- 3. Olheiros por missão ----------------------------------------------------------------------------
-- p_profile: 'prospect' (até 21 anos, maior potencial), 'starter' (pronto para jogar), 'bargain' (sem clube ou fim de contrato)
create or replace function public.career_scout_mission(p_position text default '', p_profile text default 'starter')
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare car public.careers;own text;w public.cw_world;lvl int;busy int;slots int;ready date;team_avg numeric;n int;
begin
 car:=public.mgr_lock();own:=public.cw_dev_own(car.id);
 if own is null then raise exception 'Você precisa estar em um clube para usar os olheiros.';end if;
 if p_profile not in('prospect','starter','bargain') then raise exception 'Perfil inválido.';end if;
 select * into w from public.cw_world where career_id=car.id;
 lvl:=public.cw_staff_level(car.id,own,'scout');
 select count(*) into busy from public.cw_scouting where career_id=car.id and ready_on>w.today;
 slots:=least(3,1+lvl-busy);
 if slots<=0 then raise exception 'Os olheiros já estão com % relatórios em andamento. Aguarde um terminar.',busy;end if;
 ready:=w.today+greatest(2,14-2*lvl);
 select coalesce(avg(r.rating),65) into team_avg from public.mgr_players mp
  join public.sim_players sp on sp.id=mp.player_id join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  where mp.career_id=car.id and mp.club_id=own;
 with cand as(
  select sp.id,r.rating+coalesce(d.d_rating,0) ovr,
   coalesce(cp.age_at_start,sp.age,case when sp.is_youth then 19 else 26 end)+coalesce(floor((w.today-w.started_on)/365.25)::int,0) age,
   coalesce(cp.potential,least(99,round(r.rating)+case when coalesce(sp.age,26)<23 then 12 else 3 end)) pot,
   coalesce(mp.club_id,case when mp.player_id is null then sp.club_id end) club,
   (select ct.expires_on from public.cw_contracts ct where ct.career_id=car.id and ct.player_id=sp.id and ct.status='active') expires
  from public.sim_players sp join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
  left join public.mgr_players mp on mp.career_id=car.id and mp.player_id=sp.id
  left join public.cw_players cp on cp.career_id=car.id and cp.player_id=sp.id
  left join public.cw_player_dev d on d.career_id=car.id and d.player_id=sp.id
  where sp.active and (sp.career_id is null or sp.career_id=car.id)
   and (coalesce(p_position,'')='' or sp.position=p_position)
   and not exists(select 1 from public.cw_scouting s where s.career_id=car.id and s.player_id=sp.id)
   and not exists(select 1 from public.cw_players x where x.career_id=car.id and x.player_id=sp.id and x.retired_on is not null)),
 pick as(
  select c.id from cand c
  where c.club is distinct from own
   and case p_profile
    when 'prospect' then c.age<=21 and c.pot>=c.ovr+5
    when 'starter' then c.ovr>=team_avg-3 and c.age<=31
    else c.club is null or c.expires<=w.today+183 end
  order by case p_profile when 'prospect' then c.pot when 'starter' then c.ovr else c.ovr end
   +public.cw_random(car.id::text||':scout:'||c.id||':'||w.today)*6 desc
  limit slots)
 insert into public.cw_scouting(career_id,player_id,requested_on,ready_on)
 select car.id,id,w.today,ready from pick on conflict(career_id,player_id) do nothing;
 get diagnostics n=row_count;
 if n=0 then raise exception 'Os olheiros não encontraram ninguém com esse perfil. Tente outra posição ou perfil.';end if;
 return jsonb_build_object('ok',true,'found',n,'ready_on',ready);
end $function$;
revoke all on function public.career_scout_mission(text,text) from public, anon;
grant execute on function public.career_scout_mission(text,text) to authenticated;

-- Relatórios com os dados do atleta (posição, idade, habilidade, potencial em faixa, clube e valor).
create or replace function public.cw_scout_report(p_career uuid, p_player text, p_today date)
 returns jsonb language sql stable security definer set search_path to 'public'
as $function$
 select jsonb_build_object('position',sp.position,'short_name',sp.short_name,
  'overall',round(r.rating+coalesce(d.d_rating,0)),
  'age',coalesce(cp.age_at_start,sp.age,case when sp.is_youth then 19 else 26 end)+coalesce(floor((w.today-w.started_on)/365.25)::int,0),
  'potential_range',to_jsonb(public.cw_potential_range(p_career,sp.id,coalesce(cp.potential,least(99,round(r.rating)+case when coalesce(sp.age,26)<23 then 12 else 3 end))::int)),
  'club_id',public.cw_effective_player_club(p_career,sp.id),
  'value',public.cw_player_value(p_career,sp.id))
 from public.sim_players sp join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
 left join public.cw_players cp on cp.career_id=p_career and cp.player_id=sp.id
 left join public.cw_player_dev d on d.career_id=p_career and d.player_id=sp.id
 left join public.cw_world w on w.career_id=p_career
 where sp.id=p_player
$function$;

create or replace function public.career_club_dev_read()
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare car public.careers;own text;w public.cw_world;
begin
 car:=public.mgr_lock();
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 select * into w from public.cw_world where career_id=car.id;
 if own is null then return jsonb_build_object('enabled',public.cw_dev_on(),'employed',false);end if;
 perform public.cw_dev_ensure_club(car.id,own);
 return jsonb_build_object('enabled',public.cw_dev_on(),'employed',true,'club_id',own,'today',w.today,
  'difficulty',(select jsonb_build_object('id',lv.id,'label',lv.label,'description',lv.description,'profile',c.difficulty,
    'profile_label',(select label from public.sim_difficulty_profiles where id=c.difficulty),'can_change',c.difficulty_season is distinct from w.primary_season)
   from public.careers c join public.career_difficulty_levels lv on lv.id=coalesce(c.difficulty_level,'normal') where c.id=car.id),
  'difficulty_levels',(select jsonb_agg(jsonb_build_object('id',id,'label',label,'description',description) order by sort_order) from public.career_difficulty_levels),
  'window_open',public.cw_window_open(public.cw_region(own),w.today),
  'budget',public.cw_available_budget(car.id,own),
  'infrastructure',(select infrastructure from public.cw_clubs where career_id=car.id and club_id=own),
  'training',(select to_jsonb(t)-'career_id' from public.cw_training t where career_id=car.id and club_id=own),
  'facilities',(select jsonb_agg(jsonb_build_object('kind',f.kind,'level',f.level,'initial_level',f.initial_level,'target_level',f.target_level,
    'building_until',f.building_until,'started_on',f.started_on,
    'next_cost',case when f.level<5 then public.cw_facility_cost(f.kind,f.level+1,own) end,
    'next_months',case when f.level<5 then public.cw_facility_months(f.kind,f.level+1) end) order by case f.kind when 'training' then 1 when 'youth' then 2 when 'medical' then 3 else 4 end)
    from public.cw_facilities f where f.career_id=car.id and f.club_id=own),
  'staff',(select jsonb_agg(jsonb_build_object('role',s.role,'level',s.level,'initial_level',s.initial_level,'monthly_salary',s.monthly_salary,'hired_on',s.hired_on,
    'next_salary',case when s.level<5 then public.cw_staff_salary(s.level+1) end) order by s.role)
    from public.cw_staff s where s.career_id=car.id and s.club_id=own),
  'set_pieces',(select jsonb_build_object('penalty',sp.penalty,'free_kick',sp.free_kick,'corner',sp.corner,'captain',sp.captain) from public.cw_set_pieces sp where sp.career_id=car.id and sp.club_id=own),
  'familiarity',(select jsonb_agg(jsonb_build_object('formation',f.id,'value',round(public.cw_familiarity_value(car.id,own,f.id))) order by f.sort)
    from public.sim_formations f),
  'energy',jsonb_build_object('energy',car.energy,'bonus',car.bonus_energy),
  'loans',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'player_id',l.player_id,'player',public.mgr_player_name(l.player_id),'parent_club',l.parent_club,
    'borrower_club',l.borrower_club,'status',l.status,'origin',l.origin,'wage_share',l.wage_share,'fee',l.fee,'role',l.role,'starts_on',l.starts_on,'ends_on',l.ends_on,
    'expires_on',l.expires_on,'response',l.response) order by l.created_on desc),'[]')
    from public.cw_loans l where l.career_id=car.id and own in(l.parent_club,l.borrower_club) and (l.status in('offered','active') or l.created_on>w.today-60)),
  'scouting',(select coalesce(jsonb_agg(jsonb_build_object('player_id',s.player_id,'player',public.mgr_player_name(s.player_id),'requested_on',s.requested_on,'ready_on',s.ready_on,
    'ready',s.ready_on<=w.today)||case when s.ready_on<=w.today then public.cw_scout_report(car.id,s.player_id,w.today) else '{}'::jsonb end
    order by s.ready_on<=w.today desc,s.requested_on desc),'[]')
    from public.cw_scouting s where s.career_id=car.id and s.requested_on>w.today-120),
  'youth',(select coalesce(jsonb_agg(jsonb_build_object('player_id',p.id,'name',p.short_name,'position',p.position,'club_id',mp.club_id) order by p.imported_at desc),'[]')
    from public.sim_players p join public.mgr_players mp on mp.career_id=car.id and mp.player_id=p.id where p.career_id=car.id and mp.club_id=own),
  'reputation',(select jsonb_build_object('reputation',c.reputation,'credibility',cc.credibility,'titles',c.titles,'seasons',c.seasons)
    from public.mgr_coach c left join public.cw_coach cc on cc.career_id=c.career_id where c.career_id=car.id));
end $function$;

-- 4. Busca de mercado -------------------------------------------------------------------------------
-- p_status: '' (todos), 'free' (sem clube), 'expiring' (contrato até 6 meses), 'listed' (à venda), 'affordable' (cabe no orçamento)
-- p_sort: 'overall' | 'value' | 'age' | 'potential'
create or replace function public.career_market_search(
 p_query text default '', p_position text default '', p_min_overall int default null, p_max_overall int default null,
 p_min_age int default null, p_max_age int default null, p_max_value bigint default null, p_status text default '',
 p_sort text default 'overall', p_page int default 0)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
#variable_conflict use_column
declare car uuid:=public.cw_current_career();own text;w public.cw_world;budget bigint;
begin
 if car is null then raise exception 'Carreira ativa não encontrada';end if;
 select * into w from public.cw_world where career_id=car;
 select club_id into own from public.mgr_coach where career_id=car;
 if p_status='affordable' and own is not null then budget:=public.cw_available_budget(car,own);end if;
 return(select coalesce(jsonb_agg((to_jsonb(x)||jsonb_build_object(
   'potential',null,
   'potential_range',to_jsonb(public.cw_potential_range(car,x.id,x.pot::int)),
   'scouted',public.cw_scout_known(car,x.id),
   'scout_ready_on',(select s.ready_on from public.cw_scouting s where s.career_id=car and s.player_id=x.id),
   'regen',x.regen,
   'on_loan',exists(select 1 from public.cw_loans l where l.career_id=car and l.player_id=x.id and l.status='active')))-'pot'-'ord'-'value_f'
  order by x.ord),'[]') from(
  select b.*,coalesce(b.value_f,public.cw_player_value(car,b.id)) value,ct.monthly_salary,ct.expires_on,ct.role,ct.arrears,
   public.cw_salary_demand(car,b.id,own) salary_demand,public.cw_minimum_signing(car,b.id,own) minimum_signing_bonus,
   public.cw_project_reason(car,b.id,own) project_reason,
   coalesce((select sum(st.minutes) from public.mgr_player_stats st join public.career_seasons ss on ss.id=st.season_id where ss.career_id=car and ss.status='active' and st.player_id=b.id),0) minutes
  from(
   select a.*,row_number() over(order by
     case when p_sort='value' then a.value_f end asc nulls last,
     case when p_sort='age' then a.age end asc nulls last,
     case when p_sort='potential' then a.pot end desc nulls last,
     a.overall desc,a.id) ord
   from(
    select sp.id,sp.full_name name,sp.short_name,sp.position,e.club_id,sp.nationality,
     round(pr.rating+coalesce(d.d_rating,0)) overall,round(coalesce(mp.condition,100)) condition,
     coalesce(cp.age_at_start,sp.age,case when sp.is_youth then 19 else 26 end)+coalesce(floor((w.today-w.started_on)/365.25)::int,0) age,
     coalesce(cp.age_estimated,sp.age is null) age_estimated,
     coalesce(cp.potential,least(99,round(pr.rating)+case when coalesce(sp.age,26)<23 then 12 else 3 end)) pot,
     coalesce(cp.morale,65) morale,coalesce(cp.promised_role,'rotation') promised_role,coalesce(cp.transfer_requested,false) transfer_requested,
     coalesce(cp.transfer_listed,false) transfer_listed,
     coalesce(cp.shirt_number,sp.shirt_number) number,sp.career_id is not null regen,
     case when p_sort='value' or p_max_value is not null or p_status='affordable' then public.cw_player_value(car,sp.id) end value_f
    from public.sim_players sp join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
    left join public.mgr_players mp on mp.career_id=car and mp.player_id=sp.id
    left join public.cw_players cp on cp.career_id=car and cp.player_id=sp.id
    left join public.cw_player_dev d on d.career_id=car and d.player_id=sp.id
    cross join lateral(select public.cw_effective_player_club(car,sp.id) club_id)e
    where sp.active and (sp.career_id is null or sp.career_id=car)
     and (cp.retired_on is null)
     and (coalesce(p_query,'')='' or sp.full_name ilike '%'||left(p_query,60)||'%')
     and (coalesce(p_position,'')='' or sp.position=p_position)
     and (p_min_overall is null or pr.rating+coalesce(d.d_rating,0)>=p_min_overall-.5)
     and (p_max_overall is null or pr.rating+coalesce(d.d_rating,0)<p_max_overall+.5)
     and e.club_id is distinct from own
   )a
   where (p_min_age is null or a.age>=p_min_age) and (p_max_age is null or a.age<=p_max_age)
    and (p_max_value is null or a.value_f<=p_max_value)
    and case coalesce(p_status,'')
     when 'free' then a.club_id is null
     when 'expiring' then a.club_id is null or exists(select 1 from public.cw_contracts c2 where c2.career_id=car and c2.player_id=a.id and c2.status='active' and c2.expires_on<=w.today+183)
     when 'listed' then a.transfer_listed
     when 'affordable' then budget is null or a.value_f<=budget
     else true end
  )b
  left join public.cw_contracts ct on ct.career_id=car and ct.player_id=b.id and ct.status='active'
  where b.ord>least(greatest(coalesce(p_page,0),0),200)*30 and b.ord<=(least(greatest(coalesce(p_page,0),0),200)+1)*30
 )x);
end $function$;
revoke all on function public.career_market_search(text,text,int,int,int,int,bigint,text,text,int) from public, anon;
grant execute on function public.career_market_search(text,text,int,int,int,int,bigint,text,text,int) to authenticated;
