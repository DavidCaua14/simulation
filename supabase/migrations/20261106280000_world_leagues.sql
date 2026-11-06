-- Torneios > Ligas do mundo: todas as competições do jogo, mesmo as que não estão acontecendo na carreira.
-- Leitura pura: nada é gravado. Liga de fundo sem partidas nesta carreira mostra a tabela calculada (cw_bg_table).

create or replace function public.career_world_leagues()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare car public.careers;
begin
 car:=public.cw_read_career();
 return coalesce((select jsonb_agg(jsonb_build_object(
   'id',co.id,'name',co.name,'short',co.short_name,'kind',co.kind,'region',co.region,'background',co.background,
   'theme',co.theme,'zones',co.rules->'zones',
   'country',(select c.country from public.sim_competition_clubs cc join public.sim_clubs c on c.id=cc.club_id
     where cc.competition_id=co.id group by c.country order by count(*) desc,c.country limit 1),
   'clubs',(select count(*) from public.sim_competition_clubs cc where cc.competition_id=co.id),
   'in_season',exists(select 1 from public.season_competitions sc join public.career_seasons s on s.id=sc.season_id
     where s.career_id=car.id and s.status='active' and sc.competition_id=co.id))
   order by co.background,co.sort_order)
  from public.sim_competitions co where co.active),'[]'::jsonb);
end $$;

create or replace function public.career_world_league_table(p_comp text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare car public.careers;w public.cw_world;co public.sim_competitions;sid uuid;rows jsonb;src text;
begin
 car:=public.cw_read_career();
 select * into co from public.sim_competitions where id=p_comp and active;
 if co.id is null then raise exception 'Campeonato inexistente';end if;
 select * into w from public.cw_world where career_id=car.id;
 select s.id into sid from public.season_competitions sc join public.career_seasons s on s.id=sc.season_id
  where s.career_id=car.id and s.status='active' and sc.competition_id=p_comp order by s.season_no desc limit 1;
 if co.kind<>'league' then
  src:='clubs';
 elsif sid is not null then
  src:='season';
  select jsonb_agg(jsonb_build_object('pos',t.pos,'club_id',t.club_id,'played',t.played,'wins',t.wins,'draws',t.draws,
    'losses',t.losses,'gf',t.gf,'ga',t.ga,'gd',t.gd,'points',t.points) order by t.pos)
   into rows from public.sim_standings(sid,p_comp,null) t;
 elsif co.background then
  src:='projection';
  select jsonb_agg(jsonb_build_object('pos',t.pos,'club_id',t.club_id,'played',t.played,'wins',t.won,'draws',t.drawn,
    'losses',t.lost,'gf',t.gf,'ga',t.ga,'gd',t.gf-t.ga,'points',t.pts) order by t.pos)
   into rows from public.cw_bg_table(car.id,p_comp,coalesce(w.today,current_date)) t;
 else
  src:='clubs';
 end if;
 return jsonb_build_object('id',co.id,'source',src,'today',w.today,'rows',coalesce(rows,'[]'::jsonb),
  'clubs',(select coalesce(jsonb_agg(jsonb_build_object('club_id',c.id,'strength',c.strength) order by c.strength desc,c.name),'[]'::jsonb)
   from public.sim_competition_clubs cc join public.sim_clubs c on c.id=cc.club_id where cc.competition_id=co.id));
end $$;

revoke all on function public.career_world_leagues(), public.career_world_league_table(text) from public, anon;
grant execute on function public.career_world_leagues(), public.career_world_league_table(text) to authenticated;
