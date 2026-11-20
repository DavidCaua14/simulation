-- MODO ONLINE — Fase 43: chave para fechar o mercado de transferências (on_config.market_off), para todos, inclusive o
-- administrador. Com a chave ligada: nenhum leilão abre, não há lances nem anúncios (on_market_open = falso) e o app mostra
-- "Mercado fechado". Desligar a chave volta ao horário normal (market_open/market_close).
alter table public.on_config add column if not exists market_off boolean not null default false;

do $$ begin
 if position('market_off' in pg_get_functiondef('public.on_market_hours(timestamp with time zone)'::regprocedure))=0 then
  perform public.on_patch('public.on_market_hours(timestamp with time zone)',
   ' select jsonb_build_object(''open'',h.t>=make_time(cfg.market_open,0,0) and h.t<c.close_t,',
   ' select jsonb_build_object(''open'',not cfg.market_off and h.t>=make_time(cfg.market_open,0,0) and h.t<c.close_t,''off'',cfg.market_off,');
 end if;
end $$;
