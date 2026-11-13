-- MODO ONLINE — Fase 22: lendas caras, e a lenda que passa de 100 é raridade.
-- Lance inicial (a moeda vale $ 1 no lance; um técnico bom junta uns $ 0,5–1 milhão por temporada):
--  • lenda com potencial acima de 100: $ 5 milhões + $ 500 mil por ponto acima de 101 (Messi, pot 107: $ 8 milhões);
--  • demais lendas: $ 800 mil + $ 120 mil por ponto de nota acima de 80 (84: $ 1,28 milhão; 93: $ 2,36 milhões);
--  • destaque (81+) e comum seguem iguais.
-- Leilões já abertos mantêm o preço com que foram criados.
create or replace function public.on_start_price(p public.on_players) returns bigint
language sql immutable set search_path=public as $$
 select case when p.legend and p.pot>100 then 5000000+(p.pot-101)*500000
  when p.legend then 800000+greatest(0,p.level-80)*120000
  when p.level>=81 then 400000+(p.level-80)*40000
  else greatest(500,round(public.on_value(p.ovr,p.age,p.pot)*.4)) end::bigint
$$;
