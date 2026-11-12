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
- **Premiação em moedas** (`sim_prizes`; 1 moeda = $ 1 no caixa do clube no modo online; a aba Prêmios de cada competição mostra a tabela). Migração `20261113140000_seasons_prizes_in_online_money.sql`.
  - Brasileirão: 1.000.000 ao campeão, 950 mil ao vice, descendo até 340 mil ao 16º; rebaixados não recebem. 2.500 por vitória, 800 por empate.
  - Copa do Brasil (acumulado): oitavas 60 mil, quartas 150 mil, semifinal 350 mil, vice 800 mil, campeão 1,5 milhão. 3.000 por vitória.
  - Libertadores (acumulado): grupos 250 mil, oitavas 400 mil, quartas 600 mil, semifinal 900 mil, vice 1,5 milhão, campeão 2,5 milhões. 4.000 por vitória, 1.000 por empate.
  - Série B: 150 mil ao campeão. Premier League 1,8 milhão, demais grandes ligas 1 a 1,4 milhão, Champions 3,5 milhões.
  - O prêmio fixo de 400 moedas por título no fim da temporada saiu; as moedas por meta cumprida continuam.
- **Dificuldade.** A IA aproveita menos a vantagem de elenco do técnico (`career_difficulty_levels`: normal de 0,50/1,25 para 0,38/1,32).

## Partida "em andamento" depois do apito final

O último passo da partida (`mgr_match_step`) simula o resto da rodada, avança o calendário e pode fechar a temporada. Com o limite de 8 s do papel `authenticated`, esse passo às vezes era desfeito inteiro e a partida continuava ao vivo no banco. A função agora tem limite próprio de 30 s (o PostgREST aplica o `statement_timeout` da função antes de chamá-la). Início de partida e avanço do mundo ganharam 20 s. A tela espera 3 s antes de repetir um passo que falhou.

## Banco pequeno

O reinício levou as tabelas de temporada ao tamanho de um mundo novo. A manutenção automática (`cw_runtime_maintenance`, a cada 15 minutos) continua compactando temporadas encerradas, estatísticas e finanças antigas.

## Ajustes de 13/11 (segunda rodada)

Migração `20261113160000_seasons_serie_b_start_no_investment.sql`.

- O recomeço traz três propostas sorteadas entre clubes da Série B (reputação inicial 25). As carreiras foram reiniciadas de novo com essa regra.
- Série B paga 1.000 moedas por vitória. Exercícios pré-jogo custam 4.000 moedas.
- Não é mais possível investir moedas no clube do modo Temporadas (`career_club_invest` recusa; a tela não mostra o aporte).
- O modo voltou a ficar liberado para todos (`seasons_require_access` não barra mais).
- Jeff, brunomartins, Edson e davidcaua receberam 1 milhão de moedas na caixa de mensagens.
