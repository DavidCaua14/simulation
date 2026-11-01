# Recompensas contadas na Home, mas sem botão de resgate

## Causa

`events_overview` conta todas as conclusões não resgatadas e ainda dentro do prazo. Os cartões de eventos, porém, mostram somente a conclusão do período atual. Uma recompensa diária de ontem pode continuar válida no prazo adicional configurado, mesmo quando a recompensa de hoje já foi resgatada. Nesse caso a Home indicava uma recompensa pronta, mas nenhum cartão oferecia o botão correspondente. Eventos encerrados há mais de sete dias apresentavam o mesmo problema quando o prazo de resgate era maior.

A consulta de diagnóstico encontrou uma recompensa diária de período anterior nessa situação; o resultado não indica que todas as contas estivessem afetadas.

## Correção

- A resposta de `events_overview` mantém os campos existentes e acrescenta `pending_rewards`, com as conclusões válidas que ainda não têm botão nos cartões atuais.
- A seção **Recompensas pendentes** mostra o evento, a data de conclusão, o prazo original, os prêmios e o botão de resgate associado ao ID da conclusão correta.
- Uma conclusão do período atual não aparece novamente nessa seção. Recompensas já recebidas, vencidas ou de eventos cancelados continuam excluídas.
- O contador da Home consulta a mesma visão e se atualiza ao retornar à aba, ao receber a notificação de um resgate e nos próximos prazos de renovação/expiração. Respostas antigas não sobrescrevem respostas mais recentes.
- A sequência diária continua independente: só acrescenta uma recompensa se estiver habilitada, liberada e ainda não resgatada no dia.
- A atualização de prazos da tela de eventos usa um temporizador por vencimento, evitando recarregar repetidamente um evento que já terminou.

Não houve alteração em saldos, datas dos saves, resultados, progresso dos eventos ou resgates históricos. Nenhum prazo foi reduzido e nenhuma recompensa foi paga automaticamente. `event_claim` continua responsável por validar o dono, o prazo e a entrega uma única vez.

## Banco e publicação

Fonte: `supabase/evolution/52_visible_pending_event_rewards.sql` e uma nova migração `*_visible_pending_event_rewards.sql`. A migração substitui somente a função de leitura e suas permissões. Compara hashes e contagens de carreiras, conclusões, progresso, sequência diária e extrato dentro da mesma transação; qualquer diferença aborta a instalação.

Não editar migrações aplicadas nem apagar conclusões para fazer o contador desaparecer. Usar no repositório o mesmo número de versão efetivamente registrado pelo Supabase e conferir separadamente os checks da Vercel e do Supabase Preview.

## Validação

- Migração e reaplicação executadas na cópia local restaurada dos saves, sem mudanças nas linhas públicas preexistentes.
- Teste SQL cobre períodos diários e semanais anteriores, evento antigo com prazo válido, cartões atuais sem duplicação, isolamento entre carreiras e exclusão de recompensas vencidas/canceladas/recebidas.
- Resgate de recompensa antiga, repetição idempotente e contador zero após todos os resgates testados em transação revertida.
- Teste de navegador com API interceptada em 320 e 1280 pixels: Home → recompensa antiga → resgate → Home sem aviso; atualização ao retornar à aba e ao vencer o prazo; sequência diária válida preservada.
- Build de produção e lint dos arquivos alterados aprovados.

Repetir o teste SQL pelo runner `python scripts/test-seasons-db.py --scoped-runtime`, que instala a evolução 52. O teste específico é `supabase/evolution/tests/pending_event_rewards_tests.sql` e só aceita base local descartável com prefixo `simulation_validation_`.

Com Vite em execução em `127.0.0.1:5173`, executar `python tests/pending_rewards_ui_smoke.py`. Todas as chamadas Supabase são interceptadas; nenhuma recompensa real é resgatada.

## Liberação em produção

A migração `20261101161002_visible_pending_event_rewards` foi aplicada em 01/11/2026. A consulta autenticada de verificação retornou uma recompensa devida e uma conclusão antes escondida agora disponível em `pending_rewards`. Os hashes de carreiras, conclusões, progresso, sequência diária e extrato permaneceram iguais antes e depois da implantação. Nenhum resgate foi executado em produção.
