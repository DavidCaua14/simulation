-- =====================================================================
-- DESFAZ a evolução 01–08 (competições configuráveis, clube inicial por nacionalidade, livro de transações, loja e roleta). Use só se precisar voltar atrás.
-- Depois de rodar, reaplique supabase/seasons/03_engine.sql, 04_features.sql (get_initial_offers antiga), supabase/manager/03_engine.sql e 04_career.sql
-- para restaurar as funções antigas. Temporadas criadas na Inglaterra ou com Série B são apagadas (não existem no modelo antigo).
-- =====================================================================
begin;
-- evolução 08 (roleta). As cartas ganhas continuam no inventário; o livro de transações é removido logo abaixo (06).
drop function if exists public.wheel_spin(uuid);
drop function if exists public.wheel_catalog();
drop function if exists public.wheel_segment_cards(public.wheel_segments);
drop table if exists public.wheel_spins;
drop table if exists public.wheel_state;
drop table if exists public.wheel_segments;
drop function if exists public.wheel_check_sum();
drop table if exists public.wheel_config;
-- evolução 06 (livro de transações e loja). Os saldos em careers NÃO mudam; as cartas compradas continuam no inventário.
drop trigger if exists econ_ledger_trg on public.careers;
drop function if exists public.shop_buy_card(text, text, uuid);
drop function if exists public.shop_catalog();
drop function if exists public.shop_showcase_cards(text);
drop function if exists public.shop_price(public.cards, text);
drop function if exists public.shop_period(int, timestamptz);
drop function if exists public.wallet_history(int);
drop function if exists public.econ_apply(uuid, text, int, text, text);
drop function if exists public.econ_request_save(uuid, uuid, text, jsonb);
drop function if exists public.econ_request_get(uuid, uuid, text);
drop function if exists public.econ_ledger_trg();
drop function if exists public.econ_tag(text, text);
drop table if exists public.shop_purchases;
drop table if exists public.shop_prices;
drop table if exists public.shop_sections;
drop table if exists public.econ_requests;
drop table if exists public.wallet_ledger;
-- evolução 05 (clube inicial por nacionalidade)
alter table public.careers drop constraint if exists careers_country_fkey;
alter table public.careers drop constraint if exists careers_difficulty_fkey;
alter table public.careers drop column if exists start_option;
alter table public.careers drop column if exists difficulty;
alter table public.season_offers drop column if exists start_option;
alter table public.season_offers drop column if exists difficulty;
drop function if exists public.mgr_difficulty(uuid);
drop function if exists public.sim_start_candidates(jsonb);
drop table if exists public.sim_start_rules;
drop table if exists public.sim_difficulty_profiles;
-- evolução 01–04
delete from public.career_seasons where region <> 'BRA'
   or id in (select season_id from public.season_competitions where competition_id not in ('brasileirao', 'copa_brasil', 'libertadores'));
drop table if exists public.season_transitions;
drop table if exists public.season_participants;
drop function if exists public.sim_promotion_rules_for(text, int);
drop table if exists public.sim_promotion_rules;
delete from public.sim_competition_clubs where competition_id not in ('brasileirao', 'copa_brasil', 'libertadores');
delete from public.sim_competitions where id not in ('brasileirao', 'copa_brasil', 'libertadores');
drop function if exists public.sim_create_season(uuid, text);
drop function if exists public.mgr_make_offer(uuid, uuid, int, boolean, boolean);
commit;
