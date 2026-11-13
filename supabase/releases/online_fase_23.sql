-- MODO ONLINE — Fase 23 (cartas na escalação), para o SQL Editor do Supabase. Rode inteiro, uma vez.
begin;
-- MODO ONLINE — Fase 23: cartas na escalação.
-- O campo do online passa a mostrar a carta de cada jogador (normal, especial ou lenda). A escalação dos dois
-- times de um jogo (on_fixture_lineups) agora manda também lenda, nacionalidade e potencial de cada titular.
create or replace function public.on_card_meta(p_player text) returns jsonb
language sql stable security definer set search_path=public as $$
 select coalesce((select jsonb_build_object('legend',p.legend,'nat',p.nat,'pot',p.pot) from public.on_players p where p.id=p_player),
  '{"legend":false}'::jsonb)
$$;
revoke all on function public.on_card_meta(text) from public,anon,authenticated;

do $$ begin
 -- partida aberta: quem está em campo
 perform public.on_patch('public.on_fixture_lineups(bigint)',
  '''slot'',mp.slot,''yellow'',mp.yellow,''starter'',mp.starter) order by mp.slot)',
  '''slot'',mp.slot,''yellow'',mp.yellow,''starter'',mp.starter)||public.on_card_meta(mp.player_id) order by mp.slot)');
 -- vestiário: escalação salva
 perform public.on_patch('public.on_fixture_lineups(bigint)',
  '''slot'',e.key,''yellow'',0,''starter'',true) order by e.key)',
  '''slot'',e.key,''yellow'',0,''starter'',true)||public.on_card_meta(p.id) order by e.key)');
end $$;
insert into supabase_migrations.schema_migrations(version,name) values('20261114210000','online_phase23_lineup_cards') on conflict do nothing;
commit;
