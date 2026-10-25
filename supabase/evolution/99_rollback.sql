-- =====================================================================
-- DESFAZ a evolução 01–04 (competições configuráveis). Use só se precisar voltar atrás.
-- Depois de rodar, reaplique supabase/seasons/03_engine.sql, 04_features.sql, supabase/manager/03_engine.sql e 04_career.sql
-- para restaurar as funções antigas. Temporadas criadas na Inglaterra ou com Série B são apagadas (não existem no modelo antigo).
-- =====================================================================
begin;
delete from public.career_seasons where region <> 'BRA'
   or id in (select season_id from public.season_competitions where competition_id not in ('brasileirao', 'copa_brasil', 'libertadores'));
drop table if exists public.season_transitions;
drop table if exists public.season_participants;
drop table if exists public.sim_promotion_rules;
delete from public.sim_competition_clubs where competition_id not in ('brasileirao', 'copa_brasil', 'libertadores');
delete from public.sim_competitions where id not in ('brasileirao', 'copa_brasil', 'libertadores');
drop function if exists public.sim_create_season(uuid, text);
drop function if exists public.mgr_make_offer(uuid, uuid, int, boolean, boolean);
commit;
