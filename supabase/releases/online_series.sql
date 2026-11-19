-- Liga a estrutura de séries (fase 35). Rodar uma vez, depois da migração 20261119160000.
-- Troque a data pelo primeiro dia de jogos (manhã e tarde). Os técnicos vão para a Série D com elenco e caixa.
select public.on_series_bootstrap(date 'AAAA-MM-DD');
