-- Prévia de clube (propostas e vagas): clube de liga de fundo fora do mundo da carreira mostra o elenco do catálogo,
-- força do catálogo, liga e país. Nada é gravado.

CREATE OR REPLACE FUNCTION public.cw_club_preview(p_career uuid, p_club text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w public.cw_world;own text;day int;in_world boolean;
begin
 select * into w from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 day:=coalesce(w.elapsed_days,0);
 in_world:=exists(select 1 from public.mgr_players where career_id=p_career and club_id=p_club);
 return jsonb_build_object(
  'club_id',p_club,
  'division',(select co.short_name from public.season_participants pa join public.sim_competitions co on co.id=pa.competition_id and co.kind='league'
    where pa.season_id=w.primary_season and pa.club_id=p_club limit 1)
   ,'league',(select co.short_name from public.sim_competition_clubs cc join public.sim_competitions co on co.id=cc.competition_id and co.kind='league'
    where cc.club_id=p_club order by co.background desc limit 1),
  'country',(select country from public.sim_clubs where id=p_club),
  'strength',case when in_world then public.cw_club_strength(p_career,p_club,null,day) else (select strength from public.sim_clubs where id=p_club) end,
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
    where mp.career_id=p_career and mp.club_id=p_club
    union all
    -- Clube de liga de fundo ainda fora do mundo da carreira: elenco do catálogo, nota calculada na hora (nada é gravado).
    select p.id,coalesce(p.short_name,p.full_name),p.position,ps.sort,p.age,
     (select round(sum(rw.weight*(to_jsonb(a)->>rw.attr)::numeric)/sum(rw.weight))::int from public.sim_player_attrs a join public.sim_role_weights rw on rw.pos=p.position where a.player_id=p.id)
    from public.sim_players p left join public.sim_positions ps on ps.code=p.position
    where not in_world and p.club_id=p_club and p.active and p.career_id is null)x),'[]'::jsonb));
end $function$;
