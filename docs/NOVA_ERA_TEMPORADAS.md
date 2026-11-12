# Nova era do modo Temporadas (13/11/2026)

Fontes: `supabase/migrations/20261113120000_seasons_new_era_rules.sql` (regras; pacote em `supabase/releases/temporadas_nova_era.sql`) e `supabase/maintenance/reset/2026-11-nova-era.sql` (reinício, por carreira).

## Reinício

- Todas as carreiras voltaram a 01/01/2026: técnico sem clube, três propostas da Série A, elencos e finanças originais.
- Ficaram: nível, XP, moedas, diamantes, energia, perfil, eventos, apostas e a sala de troféus (`career_trophies`).
- Voltaram ao início: reputação (25), credibilidade (65), confiança da diretoria e da torcida, contadores de jogos e demissões.
- Cada taça da história rendeu moedas, entregues como prêmio na caixa de mensagens: Champions 5.000, Libertadores 4.000, ligas europeias 3.000, Copa do Brasil 2.500, Brasileirão 2.000, copas europeias 1.200, demais 500 a 1.000.
- O ranking geral foi zerado e passou a contar só o modo online (ver `docs/MODO_ONLINE.md`, Fase 11).

## Regras novas

- **Idade congelada e sem aposentadoria.** `cw_dev_rules.retirement_enabled=false`; nenhuma função soma mais os anos passados à idade inicial. Veterano não cai por idade; jovem evolui até o potencial.
- **Sem insatisfação.** Moral fixa e neutra, sem pedido de saída, sem perda de rendimento e sem cobrança da diretoria por vestiário. As funções continuam existindo e devolvem valores neutros.
- **Premiação em moedas** (`sim_prizes`, 1 moeda ≈ R$ 10 mil do prêmio real; a aba Prêmios de cada competição mostra a tabela):
  - Brasileirão: 4.810 ao campeão, 4.570 ao vice, descendo até 1.630 ao 16º; rebaixados não recebem. 30 por vitória, 10 por empate.
  - Copa do Brasil (acumulado): oitavas 346, quartas 819, semifinal 1.764, vice 4.914, campeão 9.114. 40 por vitória.
  - Libertadores (acumulado): grupos 1.620, oitavas 2.295, quartas 3.215, semifinal 4.455, vice 8.235, campeão 16.875. 180 por vitória.
  - Série B: 350 ao campeão. Ligas e copas europeias usam valores reduzidos em relação ao real, para não desequilibrar a economia.
  - O prêmio fixo de 400 moedas por título no fim da temporada saiu; as moedas por meta cumprida continuam.
- **Dificuldade.** A IA aproveita menos a vantagem de elenco do técnico (`career_difficulty_levels`: normal de 0,50/1,25 para 0,38/1,32).

## Partida "em andamento" depois do apito final

O último passo da partida (`mgr_match_step`) simula o resto da rodada, avança o calendário e pode fechar a temporada. Com o limite de 8 s do papel `authenticated`, esse passo às vezes era desfeito inteiro e a partida continuava ao vivo no banco. A função agora tem limite próprio de 30 s (o PostgREST aplica o `statement_timeout` da função antes de chamá-la). Início de partida e avanço do mundo ganharam 20 s. A tela espera 3 s antes de repetir um passo que falhou.

## Banco pequeno

O reinício levou as tabelas de temporada ao tamanho de um mundo novo. A manutenção automática (`cw_runtime_maintenance`, a cada 15 minutos) continua compactando temporadas encerradas, estatísticas e finanças antigas.
