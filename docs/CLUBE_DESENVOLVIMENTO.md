# Desenvolvimento do clube, transmissão 2.5D e nova interface

Decisões do treinador (respostas 1A–29A). O APK de referência serviu só para comparar mecânicas; nomes, textos e arte dele não são usados.

## O que muda no jogo

| Sistema | Regra |
| --- | --- |
| Evolução (3C, 4A, 25A) | Todo mês cada atleta evolui pelo potencial, pela idade, pelos minutos jogados, pelo CT, pelo auxiliar e pela intensidade do treino. Um jovem de 18 anos com potencial 85, jogando, leva de 3 a 4 temporadas para chegar perto do teto. Depois dos 30 anos vem o declínio, primeiro no físico. |
| Treino (9A) | O foco semanal do time escolhe quais atributos crescem mais: equilibrado, físico, ataque, defesa, tático ou bola parada. A intensidade (leve, normal ou forte) muda o ritmo em 15%. |
| Nova posição (7A) | O treino individual leva cerca de um ano. A posição aprendida passa a render como posição secundária (0,97). |
| Entrosamento (10A) | Cada jogo numa formação aumenta o entrosamento; formações sem uso perdem um pouco por mês. A formação que já estava em uso começa em 100, então o rendimento atual não cai. |
| Bola parada (11A) | Você escolhe os cobradores. O cobrador de pênalti bate sempre que estiver em campo. O foco em bola parada aumenta a precisão. |
| Instalações (12A–14A) | CT, base, departamento médico e estádio, cada um do nível 1 ao 5. A diretoria aprova a obra pelo caixa e pelo risco financeiro e, quando recusa, explica o que fazer. O fundo de infraestrutura é usado primeiro. Obras demoram meses, e o estádio arrecada 15% menos durante a obra. |
| Comissão (15A) | Auxiliar, preparador físico, fisioterapeuta, psicólogo, olheiro-chefe e técnico da base. A equipe original não gera custo extra; cada contratação acima dela entra na folha mensal do clube. |
| Base (2A, 5A) | No início de cada temporada a base revela de 1 a 3 jovens. Eles são **fictícios**, existem só naquela carreira e aparecem marcados. Veteranos se aposentam por idade e nível. |
| Empréstimos (16A) | Você pode pedir um atleta (fora dos 14 principais do clube de origem) definindo a parte do salário que paga e o papel prometido. Também pode liberar atletas do seu elenco para receber propostas. O jogador volta ao clube de origem no fim da temporada. |
| Olheiros (6B, 17A) | Atletas de outros clubes aparecem com atributos aproximados e potencial em faixa. O relatório do olheiro revela os valores exatos. |
| Diretoria (21A) | Não libera um dos três melhores atletas que queira ficar, nem deixa o elenco abaixo de 18 jogadores. |
| Recusas (19A) | Toda recusa explica o motivo e diz como melhorar. |
| Reputação (20A) | O painel Clube mostra a faixa de clubes que hoje procuram você e quanto falta para a próxima. |
| Dificuldade (24A) | Novo perfil "Difícil": diretoria e torcida mais exigentes, sua evolução 15% mais lenta e rivais mais fortes no mercado. Nenhum resultado é sorteado a favor da IA. |
| IA (26A) | Segue as mesmas regras de evolução, base, aposentadoria e obras, processada em lote. |
| Monetização (23A) | Nada disso pode ser comprado com energia, moedas ou diamantes. |

## Interface

- **Transmissão 2.5D:** campo, estádio e atletas do kit, com a projeção do manifesto. As camisas são recoloridas com as cores do clube. Os lances reais do motor viram jogadas encenadas, com avisos em fila: gol, cartões, impedimento, lesão e substituição. O placar da transmissão só muda quando o gol aparece em campo. A pausa e as velocidades existentes continuam valendo, e o botão de TV desliga a transmissão.
- **Celular:** cara de jogo, sem barra de rolagem e no modo escuro, com a transmissão no topo da partida.
- **Computador (≥ 1024 px):** menu lateral no estilo de jogo de gestão e painéis em grade. Na partida, a transmissão fica à esquerda e lances, estatísticas e times à direita.
- **Time › Clube:** treino, estrutura, comissão, base, empréstimos e olheiros, com a arte do kit de instalações.
- **Avisos (28A):** a escalação e o pré-jogo mostram titulares cansados, indisponíveis ou fora de posição.
- **Assistente (29A):** acompanha a primeira visita ao modo, é opcional e tem botão para pular.

## Preservação

A evolução de cada atleta fica guardada como **diferença por carreira** em `cw_player_dev`. O catálogo (`sim_player_attrs`) não muda. Sem diferença registrada, todas as funções devolvem exatamente o valor anterior.

A instalação não altera nenhuma linha existente. A migração compara, carreira por carreira, todas as tabelas (só nas colunas que já existiam) e aborta se encontrar qualquer diferença. Partidas em andamento continuam no estado em que estavam.

Falhas nos serviços novos (mês, dia, preparo e fim de partida) ficam registradas em `cw_dev_errors` e nunca travam o avanço do calendário. O interruptor geral é `cw_dev_rules.enabled`.

## Instalar no Supabase

1. Faça um backup do projeto.
2. Execute o arquivo **inteiro** `supabase/migrations/20261104233000_club_development.sql`. Ele roda numa única transação e é gerado por `node scripts/build-club-development.mjs` a partir de `supabase/evolution/58_club_development.sql`.
3. O cliente já publicado funciona antes e depois da migração. Enquanto ela não for aplicada, a aba Clube mostra um aviso.

## Testes

Use somente um banco local descartável:

```sh
python scripts/test-seasons-db.py --scoped-runtime --skip-existing-tests
```

Os testes reaplicam as migrações 45–58 e conferem a preservação. Depois rodam todas as suítes existentes e `club_development_tests.sql`, que cobre evolução, mês idempotente, treino, nova posição, obras, comissão, névoa e relatório, empréstimo de ida e volta, veto, partida com atributos evoluídos e cobrador, base e aposentadoria. Os testes de concorrência também passam.

Prévia visual da transmissão, só em desenvolvimento: `npm run dev` e abra `/tests/preview/match25d.html`.

Os assets foram regenerados com `python3 scripts/build-kit-assets.py <kit 2.5D> <kit instalações>`.
