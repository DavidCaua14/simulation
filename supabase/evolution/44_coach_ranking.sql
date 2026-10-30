-- EVOLUÇÃO 44: ranking geral dos treinadores (substitui o ranking de palpites na tela inicial).
-- Pontos de ranking (todos os jogadores cadastrados com carreira ativa):
--   nível × 100 + XP ÷ 10                      (progressão no jogo)
--   títulos × 500 + vitórias × 20 + empates × 7 (desempenho no modo Temporadas)
--   reputação de técnico × 15                    (0–100: prestígio construído na carreira)
--   eventos concluídos × 25                      (participação)
--   demissões × −150                             (punição por campanhas ruins)
-- Desempate: nível, vitórias e quem se cadastrou primeiro. Só dados públicos saem (apelido, nível, clube, números).
begin;

create or replace function public.ranking_scores()
returns table(career_id uuid,nickname text,photo_id text,level int,club_id text,titles int,wins int,draws int,losses int,
 reputation numeric,events int,fired int,points bigint,created_at timestamptz)
language sql stable security definer set search_path=public as $$
 select c.id,c.nickname,c.photo_id,c.level,
  case when mc.status='employed' then mc.club_id end,
  coalesce(mc.titles,0),coalesce(mc.wins,0),coalesce(mc.draws,0),coalesce(mc.losses,0),round(coalesce(mc.reputation,0),1),
  coalesce(ev.n,0)::int,coalesce(mc.fired_count,0),
  (c.level*100+floor(coalesce(c.xp,0)/10.0)+coalesce(mc.titles,0)*500+coalesce(mc.wins,0)*20+coalesce(mc.draws,0)*7
   +round(coalesce(mc.reputation,0)*15)+coalesce(ev.n,0)*25-coalesce(mc.fired_count,0)*150)::bigint,
  c.created_at
 from public.careers c
 left join public.mgr_coach mc on mc.career_id=c.id
 left join (select e.career_id,count(*) n from public.event_completions e group by e.career_id) ev on ev.career_id=c.id
 where c.status='active'
$$;

create or replace function public.ranking_overall(p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare me uuid:=public.cw_current_career();
begin
 return(with ranked as(
   select s.*,row_number() over(order by s.points desc,s.level desc,s.wins desc,s.created_at,s.career_id) as position from public.ranking_scores() s)
  select jsonb_build_object(
   'entries',coalesce((select jsonb_agg(jsonb_build_object('position',r.position,'nickname',r.nickname,'photo_id',r.photo_id,'level',r.level,'club_id',r.club_id,
     'titles',r.titles,'wins',r.wins,'draws',r.draws,'losses',r.losses,'reputation',r.reputation,'events',r.events,'points',r.points,'is_me',r.career_id=me) order by r.position)
    from ranked r where r.position<=least(greatest(coalesce(p_limit,50),1),100)),'[]'::jsonb),
   'me',(select jsonb_build_object('position',r.position,'nickname',r.nickname,'level',r.level,'club_id',r.club_id,'titles',r.titles,'wins',r.wins,
     'draws',r.draws,'losses',r.losses,'reputation',r.reputation,'events',r.events,'points',r.points) from ranked r where r.career_id=me),
   'total',(select count(*) from ranked)));
end $$;

revoke all on function public.ranking_scores() from public,anon,authenticated;
revoke all on function public.ranking_overall(int) from public,anon;
grant execute on function public.ranking_overall(int) to authenticated;
notify pgrst,'reload schema';
commit;
