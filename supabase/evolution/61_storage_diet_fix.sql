-- Evolução 61 — correção da limpeza de partidas da evolução 59.
-- Medição em produção depois da 59: mgr_match_players continuava com ~46 mil linhas. As datas de jogos passados já tinham
-- sido apagadas por uma limpeza anterior (evolução 38), e a regra da 59 exigia a data para reconhecer a partida antiga.
-- Agora uma partida encerrada sem data registrada também conta como antiga. Partidas ao vivo nunca são tocadas.
begin;

create or replace function public.cw_prune_career(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare today date;own text;
begin
 perform public.cw_prune_career_before_v59(p_career);
 select w.today into today from public.cw_world w where w.career_id=p_career;
 if today is null then return;end if;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 -- Partidas encerradas há mais de 45 dias, ou sem data registrada (datas passadas já foram limpas antes):
 -- o relatório usa placar, estatísticas e lances guardados (mgr_match_report).
 delete from public.mgr_match_players mp using public.mgr_matches m
  where m.career_id=p_career and m.status='finished' and mp.fixture_id=m.fixture_id
   and not exists(select 1 from public.cw_fixture_dates fd where fd.fixture_id=m.fixture_id and fd.due_on>=today-45);
 delete from public.mgr_match_events e using public.mgr_matches m
  where m.career_id=p_career and m.status='finished' and e.fixture_id=m.fixture_id
   and not exists(select 1 from public.cw_fixture_dates fd where fd.fixture_id=m.fixture_id and fd.due_on>=today-45)
   and e.kind not in('goal','pen_goal','own_goal','so_goal','so_miss','yellow','red','second_yellow','pen_miss','sub','injury');
 delete from public.mgr_matches m
  where m.career_id=p_career and m.status='finished'
   and not exists(select 1 from public.cw_fixture_dates fd where fd.fixture_id=m.fixture_id and fd.due_on>=today-45);
 -- Datas auxiliares de temporadas encerradas e de jogos já disputados, e decisões diárias da IA já passadas.
 delete from public.cw_club_dates cd using public.season_fixtures f,public.career_seasons cs
  where cd.career_id=p_career and cd.fixture_id=f.id and f.season_id=cs.id and cs.career_id=p_career and cs.status<>'active';
 delete from public.cw_club_dates cd using public.season_fixtures f
  where cd.career_id=p_career and cd.fixture_id=f.id and f.status='played' and cd.due_on<today-7;
 delete from public.cw_ai_days where career_id=p_career and on_date<today-1;
 -- Histórico de evolução só do seu elenco (12 meses).
 update public.cw_player_dev d set history='[]' where d.career_id=p_career and d.history<>'[]'::jsonb
  and not exists(select 1 from public.mgr_players mp where mp.career_id=p_career and mp.player_id=d.player_id and mp.club_id=own);
 update public.cw_player_dev d set history=(select coalesce(jsonb_agg(e order by o),'[]') from(
   select e,o from jsonb_array_elements(d.history) with ordinality x(e,o) order by o desc limit 12)y)
  where d.career_id=p_career and jsonb_array_length(d.history)>12;
 -- Mensagens lidas antigas e histórico de propostas encerradas antigas.
 delete from public.mgr_messages where career_id=p_career and read and created_at<now()-interval '180 days';
 delete from public.cw_offer_history h using public.cw_negotiations n
  where h.negotiation_id=n.id and n.career_id=p_career and n.status in('completed','rejected','expired','cancelled','failed_funds') and n.created_on<today-180;
end $$;

revoke all on function public.cw_prune_career(uuid) from public,anon,authenticated;

do $$ declare rc record;begin
 for rc in select cr.id from public.careers cr where exists(select 1 from public.cw_world w where w.career_id=cr.id)
  and not exists(select 1 from public.mgr_matches m where m.career_id=cr.id and m.status='live') order by cr.id loop
  perform public.cw_prune_career(rc.id);
 end loop;
end $$;

notify pgrst,'reload schema';
commit;
