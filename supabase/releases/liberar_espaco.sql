-- LIBERAR ESPAÇO EM DISCO (rode DEPOIS de banco_enxuto.sql). Cole no SQL Editor e clique em Run, sozinho numa aba.
-- Apagar linhas não diminui o arquivo do banco: o VACUUM FULL reescreve as tabelas e devolve o espaço ao Supabase.
-- Não altera nenhum dado. Cada tabela fica bloqueada por alguns segundos enquanto é reescrita: prefira um horário
-- com poucos jogadores. É um único comando (não pode rodar dentro de transação).
vacuum (full, analyze) public.cw_finance, public.cw_appearances, public.cw_ai_days, public.cw_club_dates, public.mgr_match_players,
 public.cw_news, public.cw_players, public.cw_contracts, public.mgr_players, public.cw_negotiations, public.cw_offer_history,
 public.mgr_matches, public.season_fixtures, public.season_fixture_slots, public.cw_fixture_dates,
 public.mgr_match_events, public.cw_stats_opening, public.mgr_player_stats;
-- Opcional (aba separada): o histórico do agendador pertence ao Supabase. Se o comando abaixo der erro de permissão,
-- ignore; as linhas antigas já são apagadas todo dia e o espaço é reaproveitado.
-- vacuum full cron.job_run_details;
