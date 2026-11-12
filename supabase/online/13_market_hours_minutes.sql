-- MODO ONLINE — Fase 12: mercado das 08:00 às 18:30 (fechamento com minutos).
-- market_close_min guarda os minutos do fechamento; as janelas de destaque e lenda continuam de 5 horas (08–13 e 13–18).
alter table public.on_config add column if not exists market_close_min smallint not null default 0;
update public.on_config set market_open=8,market_close=18,market_close_min=30;

create or replace function public.on_market_hours(p_now timestamptz default now()) returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('open',h.t>=make_time(cfg.market_open,0,0) and h.t<c.close_t,
  'open_hour',cfg.market_open,'close_hour',cfg.market_close,
  'open_label',to_char(make_time(cfg.market_open,0,0),'HH24:MI'),'close_label',to_char(c.close_t,'HH24:MI'),
  'closes_at',(h.d+c.close_t) at time zone h.tz,
  'opens_at',(case when h.t<make_time(cfg.market_open,0,0) then h.d else h.d+1 end+make_time(cfg.market_open,0,0)) at time zone h.tz)
 from public.on_config cfg
 cross join lateral(select make_time(least(cfg.market_close,23),case when cfg.market_close>=24 then 59 else cfg.market_close_min end,0) close_t) c
 cross join lateral(select coalesce((select s.tz from public.on_seasons s where s.status='live'),'America/Sao_Paulo') tz) z
 cross join lateral(select (p_now at time zone z.tz)::time t,(p_now at time zone z.tz)::date d,z.tz) h
$$;

do $$ begin
 -- mensagens e limites passam a usar o horário com minutos
 perform public.on_patch('public.on_bid_as(integer,bigint,bigint,timestamp with time zone)',
  'raise exception ''Mercado fechado. Reabre às %h.'',lpad((select market_open from public.on_config)::text,2,''0'');end if;',
  'raise exception ''Mercado fechado. Reabre às %.'',public.on_market_hours(p_now)->>''open_label'';end if;');
 perform public.on_patch('public.on_lot_create(text,bigint)',
  'raise exception ''Mercado fechado. Reabre às %h.'',lpad(h->>''open_hour'',2,''0'');end if;',
  'raise exception ''Mercado fechado. Reabre às %.'',h->>''open_label'';end if;');
 perform public.on_patch('public.on_lot_create(text,bigint)',
  'raise exception ''O mercado fecha às %h: anuncie com pelo menos % minutos de antecedência'',lpad(h->>''close_hour'',2,''0''),v_min;',
  'raise exception ''O mercado fecha às %: anuncie com pelo menos % minutos de antecedência'',h->>''close_label'',v_min;');
 perform public.on_patch('public.on_market_tick(timestamp with time zone,boolean)',
  ' v_close:=(v_day+make_time(cfg.market_close%24,0,0)+case when cfg.market_close>=24 then interval ''1 day'' else interval ''0'' end) at time zone s.tz;',
  ' v_close:=(public.on_market_hours(p_now)->>''closes_at'')::timestamptz;');
 perform public.on_patch('public.on_market_tick(timestamp with time zone,boolean)',
  ' if v_hour<cfg.market_open or v_hour>=cfg.market_close then return;end if; -- mercado fechado',
  ' if not public.on_market_open(p_now) then return;end if; -- mercado fechado');
end $$;
