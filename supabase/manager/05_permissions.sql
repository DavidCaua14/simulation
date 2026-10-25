-- =====================================================================
-- MODO CARREIRA (TREINADOR) — 5/5: PERMISSÕES
-- O app só chama as funções "públicas" abaixo; todo o resto é interno (security definer).
-- =====================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'mgr\_%' or p.proname like 'sim\_%')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('mgr_hub', 'mgr_status', 'mgr_squad', 'mgr_lineup_save', 'mgr_lineup_auto', 'mgr_match_start',
                     'mgr_match_step', 'mgr_advance', 'mgr_offer_respond', 'mgr_resign', 'mgr_season_next', 'mgr_history',
                     'mgr_match_report', 'mgr_top_scorers', 'mgr_messages_read') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;

-- classificação continua acessível pela função antiga (que confere o dono da temporada)
grant execute on function public.season_standings(uuid, text, text) to authenticated;
