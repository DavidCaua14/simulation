-- Proposta de emprego: força coletiva do clube e elenco por posição, antes de aceitar ou recusar.
-- Só leitura: atende apenas propostas abertas do próprio usuário e não grava nenhuma linha
-- (olhar um clube não aumenta o banco nem aceita a proposta).
create or replace function public.career_offer_club(p_offer uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare car public.careers;o public.season_offers;w public.cw_world;own text;day int;
begin
 car:=public.cw_read_career();
 select * into o from public.season_offers where id=p_offer and career_id=car.id and kind='coach' and status='pending';
 if not found then raise exception 'Proposta inexistente ou encerrada';end if;
 select * into w from public.cw_world where career_id=car.id;
 select club_id into own from public.mgr_coach where career_id=car.id and status='employed';
 day:=coalesce(w.elapsed_days,0);
 return jsonb_build_object(
  'club_id',o.from_club,
  'division',(select co.short_name from public.season_participants sp join public.sim_competitions co on co.id=sp.competition_id and co.kind='league'
    where sp.season_id=w.primary_season and sp.club_id=o.from_club limit 1),
  'strength',public.cw_club_strength(car.id,o.from_club,null,day),
  'current_club',own,
  'current_strength',case when own is not null then public.cw_club_strength(car.id,own,null,day) end,
  'squad',coalesce((select jsonb_agg(jsonb_build_object('id',x.player_id,'name',x.name,'pos',x.pos,'age',x.age,'rating',x.rating)
     order by x.ord,x.rating desc,x.name) from(
    select mp.player_id,coalesce(sp.short_name,sp.full_name) name,sp.position pos,ps.sort ord,
     (cp.age_at_start+floor((w.today-w.started_on)/365.25))::int age,round(r.rating+coalesce(dv.d_rating,0))::int rating
    from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
    left join public.sim_positions ps on ps.code=sp.position
    join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
    left join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id
    left join public.cw_player_dev dv on dv.career_id=mp.career_id and dv.player_id=mp.player_id
    where mp.career_id=car.id and mp.club_id=o.from_club)x),'[]'::jsonb));
end $$;
revoke all on function public.career_offer_club(uuid) from public,anon;
grant execute on function public.career_offer_club(uuid) to authenticated;
