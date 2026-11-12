-- MODO ONLINE — Fase 14: nada no mercado passa do horário de fechamento.
--  • Leilão que abriria depois do fechamento é retirado (sobras das regras antigas de destaque/lenda à noite).
--  • O último leilão comum do dia termina no fechamento (antes o mercado ficava vazio na última meia hora).
--  • Lance perto do fechamento não empurra o relógio para depois dele.
do $$ begin
 perform public.on_patch('public.on_market_tick(timestamp with time zone,boolean)',
  '  continue when v_end>v_close;',
  '  v_end:=least(v_end,v_close);'||chr(10)||'  continue when v_end<p_now+interval ''15 minutes'';');
 perform public.on_patch('public.on_market_tick(timestamp with time zone,boolean)',
  ' if not public.on_market_open(p_now) then return;end if; -- mercado fechado',
  ' -- leilão do mercado marcado para depois do fechamento: sai (o jogador sem clube vai junto)
 delete from public.on_players p using public.on_lots l where l.player_id=p.id and l.season_id=s.id and l.status=''open'' and l.seller is null
  and l.best_club is null and p.club_id is null and l.opens_at>=(public.on_market_hours(l.opens_at)->>''closes_at'')::timestamptz;
 if not public.on_market_open(p_now) then return;end if; -- mercado fechado');
 perform public.on_patch('public.on_bid_as(integer,bigint,bigint,timestamp with time zone)',
  '  ends_at=least(hard_end,p_now+(select bid_extend from public.on_config)) where id=l.id;',
  '  ends_at=least(hard_end,p_now+(select bid_extend from public.on_config),greatest(l.ends_at,(public.on_market_hours(p_now)->>''closes_at'')::timestamptz)) where id=l.id;');
end $$;
