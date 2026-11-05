-- Evolução 60 — rodada a rodada (referência: Championship Manager 17).
-- O jogador não avança mais o calendário: o botão JOGAR resolve tudo até a data da sua partida.
-- Para isso cada passo do mundo pode cobrir até 14 dias (antes 3). Os serviços de mercado, propostas e
-- empregos já ajustam a probabilidade pelo tamanho do passo (cw_tick_probability), então o ritmo do mundo é o mesmo.
-- Prazos de negociação, contratos, propostas e fechamentos de mês continuam interrompendo o passo na data certa.
begin;
update public.cw_runtime_rules set market_interval=14 where market_interval<14;
commit;
