-- MODO ONLINE — Fase 13: prêmios em moedas e confronto direto no ranking.
--  • Vitória rende win_coins (5.000) e empate draw_coins (1.500) na conta do técnico.
--  • Fim de temporada: o técnico recebe moedas pela colocação (league_coins) e pela copa (cup_coin_prizes); o caixa
--    do clube dele não recebe prêmio. Investir no clube é escolha do técnico. Bots continuam recebendo em caixa.
--  • Ranking: vencer outro técnico vale mais (human) e perder para outro técnico tira pontos (human_loss).
--  • Energia de treino comprada com moedas na escala nova.
alter table public.on_config add column if not exists cup_coin_prizes int[] not null default array[250000,120000,60000];
update public.on_config set win_coins=5000,draw_coins=1500,train_energy_cost=5000,
 league_coins=array[500000,400000,320000,260000,210000,170000,140000,110000,90000,70000,55000,40000],
 cup_coin_prizes=array[250000,120000,60000],
 rank_rules=rank_rules||'{"human":20,"human_loss":15}'::jsonb;

-- moedas de fim de temporada: colocação na liga + campanha na copa
create or replace function public.on_season_coins(p_pos int,p_cup text) returns int
language sql stable security definer set search_path=public as $$
 select coalesce(c.league_coins[p_pos],0)+coalesce(c.cup_coin_prizes[case p_cup when 'champion' then 1 when 'final' then 2 when 'sf' then 3 end],0)
 from public.on_config c
$$;
revoke all on function public.on_season_coins(int,text) from public,anon,authenticated;

do $$ begin
 perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',
  '  perform public.on_money(r.club_id,cfg.league_prizes[r.pos],''prize'',format(''%sº lugar na liga'',r.pos));',
  '  if r.user_id is null then perform public.on_money(r.club_id,cfg.league_prizes[r.pos],''prize'',format(''%sº lugar na liga'',r.pos));end if;');
 perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',
  '  if r.cup is not null then','  if r.cup is not null and r.user_id is null then');
 perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',
  'set coins=coins+cfg.league_coins[r.pos]+case when r.cup=''champion'' then cfg.cup_coins else 0 end',
  'set coins=coins+public.on_season_coins(r.pos,r.cup)');
 perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',
  '    r.pos,cfg.league_prizes[r.pos],cfg.league_coins[r.pos]+case when r.cup=''champion'' then cfg.cup_coins else 0 end));',
  '    r.pos,public.on_season_coins(r.pos,r.cup)));');
 perform public.on_patch('public.on_season_end(smallint,timestamp with time zone)',
  '''Fim de temporada: %sº lugar. Prêmio de $ %s e %s moedas na sua conta.''',
  '''Fim de temporada: %sº lugar. Prêmio de %s moedas na sua conta.''');
 -- ranking: derrota para outro técnico tira pontos
 perform public.on_patch('public.on_rank_hook(bigint)',
  '   when drew then (rr->>''draw'')::int else 0 end;',
  '   when drew then (rr->>''draw'')::int
   when o.user_id is not null then -coalesce((rr->>''human_loss'')::int,0) else 0 end;');
end $$;
