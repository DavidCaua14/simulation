-- Busca de mercado e busca de atletas planejadas a cada chamada.
-- A partir da sexta chamada na mesma conexão o PostgreSQL trocava o plano por um genérico, que não aproveita os
-- filtros vazios: a busca passava de ~0,5 s para mais de 20 s e estourava o limite de 8 s.
-- O SQL da consulta é o mesmo, apenas executado com EXECUTE ... USING. Saída comparada com a versão anterior em
-- 20 combinações de filtros, em duas carreiras: idêntica.
CREATE OR REPLACE FUNCTION public.career_market_search(p_query text DEFAULT ''::text, p_position text DEFAULT ''::text, p_min_overall integer DEFAULT NULL::integer, p_max_overall integer DEFAULT NULL::integer, p_min_age integer DEFAULT NULL::integer, p_max_age integer DEFAULT NULL::integer, p_max_value bigint DEFAULT NULL::bigint, p_status text DEFAULT ''::text, p_sort text DEFAULT 'overall'::text, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare res jsonb;car uuid:=public.cw_current_career();own text;w public.cw_world;budget bigint;
begin
 if car is null then raise exception 'Carreira ativa não encontrada';end if;
 select * into w from public.cw_world where career_id=car;
 select club_id into own from public.mgr_coach where career_id=car;
 if p_status='affordable' and own is not null then budget:=public.cw_available_budget(car,own);end if;
 -- Consulta dinâmica: planejada com os filtros reais a cada chamada. O plano genérico em cache levava mais de 20 s.
 execute $q$select coalesce(jsonb_agg((to_jsonb(x)||jsonb_build_object(
   'potential',null,
   'potential_range',to_jsonb(public.cw_potential_range($1,x.id,x.pot::int)),
   'scouted',public.cw_scout_known($1,x.id),
   'scout_ready_on',(select s.ready_on from public.cw_scouting s where s.career_id=$1 and s.player_id=x.id),
   'regen',x.regen,
   'on_loan',exists(select 1 from public.cw_loans l where l.career_id=$1 and l.player_id=x.id and l.status='active')))-'pot'-'ord'-'value_f'
  order by x.ord),'[]') from(
  select b.*,coalesce(b.value_f,public.cw_player_value($1,b.id)) value,ct.monthly_salary,ct.expires_on,ct.role,ct.arrears,
   public.cw_salary_demand($1,b.id,$2) salary_demand,public.cw_minimum_signing($1,b.id,$2) minimum_signing_bonus,
   public.cw_project_reason($1,b.id,$2) project_reason,
   coalesce((select sum(st.minutes) from public.mgr_player_stats st join public.career_seasons ss on ss.id=st.season_id where ss.career_id=$1 and ss.status='active' and st.player_id=b.id),0) minutes
  from(
   select a.*,row_number() over(order by
     case when $14='value' then a.value_f end asc nulls last,
     case when $14='age' then a.age end asc nulls last,
     case when $14='potential' then a.pot end desc nulls last,
     a.overall desc,a.id) ord
   from(
    select sp.id,sp.full_name name,sp.short_name,sp.position,e.club_id,sp.nationality,
     round(pr.rating+coalesce(d.d_rating,0)) overall,round(coalesce(mp.condition,100)) condition,
     coalesce(cp.age_at_start,sp.age,case when sp.is_youth then 19 else 26 end)+coalesce(floor(($3-$4)/365.25)::int,0) age,
     coalesce(cp.age_estimated,sp.age is null) age_estimated,
     coalesce(cp.potential,least(99,round(pr.rating)+case when coalesce(sp.age,26)<23 then 12 else 3 end)) pot,
     coalesce(cp.morale,65) morale,coalesce(cp.promised_role,'rotation') promised_role,coalesce(cp.transfer_requested,false) transfer_requested,
     coalesce(cp.transfer_listed,false) transfer_listed,
     coalesce(cp.shirt_number,sp.shirt_number) number,sp.career_id is not null regen,
     case when $14='value' or $12 is not null or $13='affordable' then public.cw_player_value($1,sp.id) end value_f
    from public.sim_players sp join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
    left join public.mgr_players mp on mp.career_id=$1 and mp.player_id=sp.id
    left join public.cw_players cp on cp.career_id=$1 and cp.player_id=sp.id
    left join public.cw_player_dev d on d.career_id=$1 and d.player_id=sp.id
    cross join lateral(select public.cw_effective_player_club($1,sp.id) club_id)e
    where sp.active and (sp.career_id is null or sp.career_id=$1)
     and (cp.retired_on is null)
     and (coalesce($6,'')='' or sp.full_name ilike '%'||left($6,60)||'%')
     and (coalesce($7,'')='' or sp.position=$7)
     and ($8 is null or pr.rating+coalesce(d.d_rating,0)>=$8-.5)
     and ($9 is null or pr.rating+coalesce(d.d_rating,0)<$9+.5)
     and e.club_id is distinct from $2
   )a
   where ($10 is null or a.age>=$10) and ($11 is null or a.age<=$11)
    and ($12 is null or a.value_f<=$12)
    and case coalesce($13,'')
     when 'free' then a.club_id is null
     when 'expiring' then a.club_id is null or exists(select 1 from public.cw_contracts c2 where c2.career_id=$1 and c2.player_id=a.id and c2.status='active' and c2.expires_on<=$3+183)
     when 'listed' then a.transfer_listed
     when 'affordable' then $5 is null or a.value_f<=$5
     else true end
  )b
  left join public.cw_contracts ct on ct.career_id=$1 and ct.player_id=b.id and ct.status='active'
  where b.ord>least(greatest(coalesce($15,0),0),200)*30 and b.ord<=(least(greatest(coalesce($15,0),0),200)+1)*30
 )x$q$ into res using car,own,w.today,w.started_on,budget,p_query,p_position,p_min_overall,p_max_overall,p_min_age,p_max_age,p_max_value,p_status,p_sort,p_page;
 return res;
end $function$;

CREATE OR REPLACE FUNCTION public.career_player_search_before_v58(p_query text DEFAULT ''::text, p_position text DEFAULT ''::text, p_region text DEFAULT ''::text, p_club text DEFAULT ''::text, p_max_value bigint DEFAULT NULL::bigint, p_page integer DEFAULT 0, p_country text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare res jsonb;car uuid:=public.cw_current_career();own text;w public.cw_world;
begin
 if car is null then raise exception 'Carreira ativa não encontrada';end if;
 select * into w from public.cw_world where career_id=car;
 select club_id into own from public.mgr_coach where career_id=car;
 -- Consulta dinâmica: planejada com os filtros reais a cada chamada. O plano genérico em cache levava mais de 20 s.
 execute $q$select coalesce(jsonb_agg(to_jsonb(x) order by x.overall desc,x.id),'[]') from(
 select b.*,public.cw_player_value($1,b.id) value,ct.monthly_salary,ct.expires_on,ct.role,ct.arrears,
 public.cw_salary_demand($1,b.id,$2) salary_demand,public.cw_minimum_signing($1,b.id,$2) minimum_signing_bonus,
 public.cw_project_reason($1,b.id,$2) project_reason,
 coalesce((select sum(st.minutes) from public.mgr_player_stats st join public.career_seasons ss on ss.id=st.season_id where ss.career_id=$1 and ss.status='active' and st.player_id=b.id),0) minutes
 from(
 select sp.id,sp.full_name name,sp.short_name,sp.position,e.club_id,sp.nationality,round(pr.rating) overall,
 round(coalesce(mp.condition,100)) condition,
 coalesce(cp.age_at_start,sp.age,case when sp.is_youth then 19 else 26 end)+coalesce(floor(($3-$4)/365.25)::int,0) age,
 coalesce(cp.age_estimated,sp.age is null) age_estimated,coalesce(cp.potential,least(99,round(pr.rating)+case when coalesce(sp.age,26)<23 then 12 else 3 end)) potential,
 coalesce(cp.morale,65) morale,coalesce(cp.promised_role,'rotation') promised_role,coalesce(cp.transfer_requested,false) transfer_requested,
 coalesce(cp.shirt_number,sp.shirt_number) number
 from public.sim_players sp join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
 left join public.mgr_players mp on mp.career_id=$1 and mp.player_id=sp.id
 left join public.cw_players cp on cp.career_id=$1 and cp.player_id=sp.id
 cross join lateral(select public.cw_effective_player_club($1,sp.id) club_id)e
 left join public.sim_clubs sc on sc.id=e.club_id
 where sp.active and (coalesce($5,'')='' or sp.full_name ilike '%'||left($5,60)||'%')
 and (coalesce($11,'')='' or sc.country=upper($11))
 and (coalesce($6,'')='' or sp.position=$6)
 and (coalesce($7,'')='' or public.cw_region(e.club_id)=$7 or($7='free' and e.club_id is null))
 and (coalesce($8,'')='' or e.club_id=case when $8='mine' then $2 else $8 end)
 and ($9 is null or public.cw_player_value($1,sp.id)<=$9)
 order by pr.rating desc,sp.id limit 30 offset least(greatest(coalesce($10,0),0),200)*30)b
 left join public.cw_contracts ct on ct.career_id=$1 and ct.player_id=b.id and ct.status='active')x$q$ into res using car,own,w.today,w.started_on,p_query,p_position,p_region,p_club,p_max_value,p_page,p_country;
 return res;
end $function$;
