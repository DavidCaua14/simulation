-- =====================================================================
-- MODO CARREIRA (TREINADOR) — ROLLBACK (só se precisar voltar ao modo antigo de jogador)
-- Não apaga as tabelas novas (os dados da carreira de treinador ficam guardados).
-- 1) reativa a temporada de jogador arquivada e devolve o modo antigo
-- 2) depois rode de novo supabase/seasons/03_engine.sql e 04_features.sql (restauram as funções antigas)
-- =====================================================================
update public.career_seasons s set status = 'active'
 where s.mode = 'player' and s.status = 'archived'
   and not exists (select 1 from public.career_seasons x where x.career_id = s.career_id and x.status = 'active' and x.mode = 'player');
update public.career_seasons set status = 'finished' where mode = 'coach' and status = 'active';
-- (opcional) para recomeçar a carreira de treinador do zero numa próxima tentativa:
-- delete from public.mgr_coach;  delete from public.mgr_spells;  delete from public.mgr_players;
