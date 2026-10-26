# Etapa 12 — Eventos recorrentes, sequência diária e administração

Migração: `supabase/evolution/13_events.sql` (idempotente; desfeita por `evolution/99_rollback.sql`).
Testes: `evolution/tests/events_tests.sql` (E1–E8) e `evolution/tests/events_concurrency.sh`.

## O que existia antes

* A aba/atalho **Eventos** existia só como botão bloqueado ("Em breve"); não havia tabela nem regra de eventos.
* As únicas recompensas recorrentes eram as caixas diárias da Home (`cards/`), que continuam iguais.

## Como funciona

| Parte | Onde |
|---|---|
| Eventos configuráveis (nome, descrição, banner, categoria, início/fim em UTC, fuso, repetição, nível mínimo, limite de conclusões, prazo de resgate, estado) | `events` |
| Objetivos (tipo + meta + filtros) | `event_objectives`, tipos em `event_objective_kinds` |
| Recompensas (moedas, diamantes, energia bônus, caixa, carta, cosmético, insígnia) | `event_rewards` |
| Progresso por jogador e período | `event_progress` |
| Conclusão (uma por evento × jogador × período), prazo e o que foi entregue | `event_completions` |
| Sequência diária | `streak_config`, `streak_rewards`, `player_streaks` |
| Quem administra | `admins` |

**Progresso só vem de fatos reais registrados pelo servidor** (gatilhos), nunca do navegador:

| Tipo | Gatilho | Filtros aceitos |
|---|---|---|
| Jogar / vencer / marcar gols / não sofrer gols | partida do treinador passa a `played` (`season_fixtures`) | competição, país (BRA/ENG), força mínima do adversário* |
| Abrir caixas | `reward_boxes` → `opened` | raridade |
| Cartas novas | nova linha em `user_cards` | raridade |
| Vender no mercado | `market_listings` → `sold` | — |
| Fazer palpites | novo bilhete em `tickets` | — |

\* "Não sofrer gols" não aceita força mínima. Vitória nos pênaltis conta como vitória de quem avançou.

**Períodos.** Evento diário vira à meia-noite e semanal na segunda-feira 00:00, no fuso do evento (padrão
`America/Sao_Paulo`); os horários ficam em UTC no banco. Evento sem repetição tem um período único. Concluído o período,
novas partidas não contam de novo até o próximo.

**Resgate.** `event_claim` trava a carreira, entrega tudo uma vez e grava o que entregou. Clique duplo ou duas abas
devolvem a mesma resposta (`replayed`) sem pagar de novo (testado com duas conexões simultâneas). Moedas/diamantes/energia
entram no extrato com o motivo `event_reward`; caixas chegam na caixa de entrada (origem `event`). O prazo padrão é de 48 h
depois do fim do período (24 h nos diários). Evento cancelado não aceita progresso nem resgate.

**Sequência diária.** 7 dias com recompensas crescentes (dia 3 e 6: caixa básica; dia 5: +1 diamante; dia 7: 200 moedas,
2 diamantes e caixa Destaque). Libera com **uma partida concluída ou um palpite no dia** (Brasília). Pular um dia recomeça do
dia 1. Motivo no extrato: `daily_streak`.

**Insígnias novas** (regra da Etapa 9): Participante (1 evento resgatado), Frequentador (10), Semana completa (7 dias de
sequência) e Mata-gigantes 2026 (recompensa do evento temático).

## Eventos já cadastrados (publicados)

| Evento | Tipo | Período | Objetivos | Recompensa |
|---|---|---|---|---|
| Entre em campo | diário | 25/10/2026 → 31/12/2027 | 1 partida | 60 moedas |
| Vitória do dia | diário | idem | 1 vitória | 100 moedas + caixa Básica |
| Ataque afiado | diário | idem | 3 gols | 80 moedas |
| Semana vencedora | semanal | idem | 5 vitórias + 10 partidas | caixa Destaque + 3 diamantes |
| Colecionador da semana | semanal | idem | 10 caixas + 3 cartas novas | 150 moedas + 1 diamante |
| Desafio dos Gigantes | temático | 02/11/2026 00:00 → 09/11/2026 00:00 (Brasília) | 2 vitórias e 6 gols contra clubes de força 80+ | emblema Chama + insígnia + 500 moedas (1 vez) |

Nenhum evento exige diamantes para ser concluído.

## Administração

Aba **Admin** dentro de Eventos (aparece só para quem está em `admins`; o servidor confere de novo em cada chamada):
criar/editar rascunho, publicar, cancelar. Validações no servidor: tipo de objetivo do catálogo, só os filtros previstos para
o tipo, competição/raridade/cosmético/insígnia/carta existentes, força 1–99, fuso válido, fim depois do início, pelo menos
um objetivo e uma recompensa. Evento publicado que já começou não pode ter objetivos/recompensas alterados — cancele e crie
outro (evita mudar a regra de quem já está jogando). As datas do formulário são em horário de Brasília (UTC−3).

## Tela

* **Eventos**: sequência diária no topo; "Acontecendo agora", "Em breve" (próximos 30 dias) e "Encerrados recentemente"
  (7 dias, para resgatar dentro do prazo). Cada evento mostra objetivos com barra de progresso, recompensas, tempo até
  renovar/terminar (datas reais do servidor) e o botão **Resgatar**. A tela recarrega sozinha quando um período vira.
* **Histórico**: últimas 30 recompensas resgatadas.
* **Home**: o atalho Eventos e a aba Eventos foram liberados; o atalho mostra um contador discreto quando há recompensa
  pronta (evento concluído ou sequência liberada).

## Limitações conhecidas

* Progresso conta a partir da publicação do evento: partidas anteriores não entram.
* Objetivos de partida valem para o modo Temporadas (treinador). Palpites contam no momento em que o bilhete é feito
  (não exigem acerto).
* Novos tipos de objetivo exigem um gatilho no banco (uma migração), de propósito — o painel não executa código.
* Notificação push fora do jogo não existe; o aviso é o contador na Home.
