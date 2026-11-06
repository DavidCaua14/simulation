-- Segurança (2026-11-06): funções internas criadas pelas ferramentas de reset/banco híbrido ficaram com o
-- EXECUTE padrão do Postgres (PUBLIC), então qualquer pessoa com a chave pública podia chamá-las pela API
-- passando o id de QUALQUER carreira (ex.: career_reset_world apagava o mundo de outra pessoa;
-- career_begin_coach dava um clube a qualquer carreira). Nenhuma é chamada pelo app: só por outras
-- funções SECURITY DEFINER (que rodam como dono) ou pelo SQL de manutenção.
do $$
declare f regprocedure;
begin
 for f in
  select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in(
   'career_begin_coach','career_begin_unemployed','career_reset_offers','career_reset_world',
   'cw_archive_old_seasons','cw_hybrid_trim','cw_materialize_own_contracts','cw_sim_ai_fixture','cw_vacancies_tick',
   'cw_club_preview','cw_club_strength','cw_club_xi','cw_is_hybrid','cw_league_status','cw_required_reputation',
   'cw_scout_report','sim_player_base_refresh')
 loop
  execute format('revoke all on function %s from public, anon, authenticated', f);
 end loop;
end $$;
