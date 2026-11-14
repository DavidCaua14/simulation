-- MODO ONLINE — Fase 26: clube trocado por bot e ranking só com quem pontuou.
--
-- 1) O FC brunoischin (temporada 5) foi criado por engano: o usuário entrou na liga sem querer e nunca escolheu os
--    craques. O clube vira um bot como os outros (nome de bot, três craques de 76 a 80 e escalação automática), com os
--    resultados já jogados mantidos. O usuário sai da liga e do ranking. Só age se o clube ainda for dele.
-- 2) O ranking geral mostra só quem tem pontos (antes listava todas as carreiras, inclusive as zeradas).

do $$
declare c public.on_clubs;s public.on_seasons;k int;
begin
 select * into c from public.on_clubs where id=53 and name='FC brunoischin' and user_id='a94121b4-bf4d-49df-8105-7dfc309d64c5';
 if c.id is null then return;end if;
 select * into s from public.on_seasons where id=c.season_id;
 update public.on_clubs set user_id=null,name='União Serrana',short='UNI',draft_step=3,prep='{}',prep_streak=0,
  colors=colors||jsonb_build_object('stadium','Serra Dourada do Vale')
  where id=c.id;
 -- os mesmos três craques que um bot recebe ao criar a temporada
 for k in 0..2 loop
  perform public.on_star_add(c.id,s.seed||':'||c.id,k,1+floor(public.sim_hash01(s.seed||':botpick:'||c.id||':'||k)*3)::int,76,80.5,s.id+1);
 end loop;
 perform public.on_auto_lineup(c.id);
 delete from public.on_news where club_id=c.id;
 delete from public.on_ranking where user_id=c.user_id;
end $$;

CREATE OR REPLACE FUNCTION public.ranking_overall(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid:=public.cw_current_career();rr jsonb:=(select rank_rules from public.on_config);
begin
 return(with ranked as(
   select s.*,cr.user_id,row_number() over(order by s.points desc,s.wins desc,s.level desc,s.created_at,s.career_id) as position
   from public.ranking_scores() s join public.careers cr on cr.id=s.career_id
   -- só aparece no ranking quem já pontuou
   where s.points>0),
  full_ as(select r.*,k.name club_name,k.short club_short,k.colors club_colors,
    coalesce(g.matches,0) matches,coalesce(g.gf,0) gf,coalesce(g.ga,0) ga,coalesce(g.clean,0) clean,coalesce(g.human_wins,0) human_wins,
    coalesce(g.prep,0) prep,coalesce(g.league_titles,0) league_titles,coalesce(g.cups,0) cups,
    coalesce(g.pts_match,0) pts_match,coalesce(g.pts_goals,0) pts_goals,coalesce(g.pts_prep,0) pts_prep,coalesce(g.pts_season,0) pts_season
   from ranked r left join public.on_ranking g on g.user_id=r.user_id
   left join lateral(select x.name,x.short,x.colors from public.on_clubs x join public.on_seasons s on s.id=x.season_id and s.status='live'
     where x.user_id=r.user_id limit 1) k on true)
  select jsonb_build_object(
   'entries',coalesce((select jsonb_agg(jsonb_build_object('position',r.position,'nickname',r.nickname,'photo_id',r.photo_id,'avatar',r.avatar,'has_photo',r.has_photo,
     'level',r.level,'club_name',r.club_name,'club_short',r.club_short,'club_colors',r.club_colors,'titles',r.titles,'wins',r.wins,'draws',r.draws,'losses',r.losses,
     'matches',r.matches,'points',r.points,'is_me',r.career_id=me) order by r.position)
    from full_ r where r.position<=least(greatest(coalesce(p_limit,50),1),100)),'[]'::jsonb),
   'me',(select jsonb_build_object('position',r.position,'nickname',r.nickname,'photo_id',r.photo_id,'avatar',r.avatar,'has_photo',r.has_photo,'level',r.level,'xp',r.xp,
     'club_name',r.club_name,'club_short',r.club_short,'club_colors',r.club_colors,'titles',r.titles,'league_titles',r.league_titles,'cups',r.cups,
     'wins',r.wins,'draws',r.draws,'losses',r.losses,'matches',r.matches,'gf',r.gf,'ga',r.ga,'clean',r.clean,'human_wins',r.human_wins,'prep',r.prep,
     'pts_match',r.pts_match,'pts_goals',r.pts_goals,'pts_prep',r.pts_prep,'pts_season',r.pts_season,'points',r.points)
    from full_ r where r.career_id=me),
   'rules',rr,'online',true,
   'total',(select count(*) from ranked)));
end $function$;
