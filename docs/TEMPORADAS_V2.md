# Temporadas v2 — análise, regras e implantação

## Causas identificadas

- O círculo do calendário alternava o mando pela soma da rodada com o índice da mesa. Ao girar os clubes, as duas alternâncias se anulavam para parte deles, produzindo sequências enormes. O Berger corrigido alterna a mesa fixa e as mesas restantes de forma distinta; o returno é deslocado uma rodada.
- O motor já usava atributos, posições, condição, ritmo e táticas. A vantagem de atributos era amplificada em posse, volume de ataque, qualidade, acerto do chute e conversão. A adequação à posição também era descontada na produção de ataque e novamente em toda a qualidade da finalização. Os coeficientes agora distribuem esses efeitos com menor amplificação.
- Havia duas loterias disciplinares com probabilidades diferentes, sem perfil individual nem árbitro persistido. As duas origens de falta agora usam o mesmo modelo contextual.
- Classificação continental e promoção já existiam, mas participantes herdavam grupos/potes da referência. O sorteio suíço aceitava a melhor tentativa mesmo com conflitos nacionais e não verificava o limite de adversários da mesma associação.
- RLS já separava carreiras; algumas chaves estrangeiras, porém, só validavam IDs isolados, sem garantir que a carreira, a temporada, a passagem do treinador e a partida pertencessem ao mesmo histórico.

## Regras e preservação

**Calendário.** Ligas novas de 2, 4, 6, 20 e 24 clubes foram verificadas: um jogo por clube/rodada, ida/volta sem duplicação, mandos iguais e no máximo dois mandos iguais consecutivos. Ligas existentes conservam IDs, adversários, mandos, resultados e partidas iniciadas. A reparação permuta rodadas inteiramente futuras; o prefixo até a última rodada com jogo disputado ou estado de partida criado fica fixo. Aceita somente redução do custo das sequências acima de dois jogos. Restrições históricas podem impedir eliminar todas as sequências; o algoritmo não promete desfazer o passado. `season_schedule_changes` guarda os números de rodada anteriores.

**Motor.** Novos jogos registram `engine_version=2` e o rigor do árbitro. Jogos abertos antes da migração continuam no motor e na gestão de IA v1. Força individual, adequação à posição, condição, ritmo, formação, goleiro, táticas e mando influenciam as probabilidades. Não há resultado fixado, bônus oculto para o usuário ou repetição automática de uma simulação que falhou. A posse e a conversão foram suavizadas para evitar multiplicar excessivamente a diferença de qualidade. Saídas diretas podem explorar uma pressão alta; passes curtos dependem da capacidade de criação e do adversário; jogo pelos lados usa o jogo aéreo; pressão depende também da resistência.

**IA.** Formação é escolhida pelo encaixe real do elenco, incluindo todas as formações cadastradas. Preferências próximas são desempatadas por carreira/clube. Estilos persistidos: posse, pressão, contra-ataque, jogo pelos lados e equilibrado. A IA muda postura, pressão, ritmo e gestão segundo placar, tempo, cansaço e advertências, além das substituições já existentes. O painel pré-jogo informa o plano provável; a aba Times mostra instruções efetivas durante o jogo.

**Disciplina.** Entradas cautelosas/normais/firmes afetam frequência de faltas e probabilidade de cartões. Os cartões consideram desarme, agressividade, disciplina, condição, reincidência, advertência anterior, contexto e rigor do árbitro. Segundo amarelo registra duas advertências e uma expulsão. `aggression=50` e `discipline=60` são estimativas neutras iniciais configuráveis no catálogo, não dados oficiais inventados sobre atletas reais. Não mudam atributos/progresso da carreira dos usuários.

**Competições.** `sim_qualification_list` centraliza as vagas por classificação final. As quantidades respeitam os formatos já modelados: seis vagas brasileiras nos grupos da Libertadores, cinco inglesas na Champions e 16 vagas nas oitavas da Copa do Brasil. A Copa do Brasil mantém a chave de referência na primeira temporada; nas seguintes usa os 16 primeiros do Brasileirão e novo sorteio. As copas inglesas continuam incluindo os participantes das divisões daquela temporada. Os clubes das ligas estrangeiras não simuladas seguem as referências cadastradas.

Esses formatos são simplificações explícitas do jogo: não simulam estaduais, todas as fases preliminares continentais/nacionais, todas as ligas europeias ou a distribuição real completa de vagas por campeões de outras copas. Não alteram silenciosamente o formato dos torneios em andamento. As regras ficam em `data/competitions/competitions.json` / `sim_competitions.rules`, não em decisões do navegador.

**Sorteios.** Libertadores: quatro potes, um clube de cada pote e nenhuma associação repetida por grupo. Champions: nove clubes por pote, oito rivais diferentes, dois de cada pote (um em casa e um fora), quatro mandos, uma partida por rodada, nenhum compatriota e no máximo dois adversários de cada associação. Vagas da região seguem a classificação final, ocupando os lugares dos potes de referência; estrangeiros conservam os coeficientes de referência. Ordenar tudo apenas por força pode criar potes matematicamente impossíveis.

Os certificados gerados por `scripts/certify-swiss-draws.py` contêm apenas associações por vaga para os modelos de calendário; não fixam clubes, classificados ou resultados. Abrangem as nove distribuições possíveis de associações dos clubes elegíveis da região e oferecem 105 soluções verificadas. Em cada carreira os clubes são sorteados dentro das vagas compatíveis. O servidor verifica as restrições novamente e persiste os confrontos. Configurações novas sem certificado usam busca limitada; se não houver solução válida, a criação inteira falha, sem temporada parcial. Atualizações do catálogo/potes exigem regenerar os certificados.

**Histórico e isolamento.** Classificações finais são congeladas em `season_final_tables`, lidas apenas pelo dono e mostradas no histórico. Promoção, rebaixamento e vagas são calculados a partir dos jogos da própria temporada. Chaves compostas validam carreira/temporada/passagem/partida; o índice auxiliar `season_fixture_slots` impede um clube em duas partidas da mesma rodada. Resultados disputados não podem ser regravados por uma reparação. A criação de temporadas/partidas é serializada e idempotente. O catálogo é compartilhado; calendário, estado dos atletas, confrontos, classificações, decisões e histórico são individuais.

## Validar sem dados reais

Docker local, PostgreSQL 17, sem publicar portas:

```sh
docker run --name simulation-seasons-test -e POSTGRES_HOST_AUTH_METHOD=trust -d postgres:17-bookworm
python scripts/test-seasons-db.py --ui-fixtures /tmp/seasons-ui-fixtures.json
npm run build
# Em um terminal separado:
npm run dev -- --host 127.0.0.1 --port 5173 --strictPort
python tests/seasons_ui_smoke.py /tmp/seasons-ui-fixtures.json
```

Em ambiente gerenciado, usar o socket Docker local e as orientações de proxy/CA do ambiente. O teste cria e remove um banco novo de nome aleatório dentro do container; não aceita URL do Supabase. `support/bootstrap.sql` fornece somente os objetos mínimos de Auth e careers que não estão definidos como instalação inicial no repositório. O pequeno ajuste em `schema.sql` apenas coloca o identificador de saída `position` entre aspas, necessário para instalar a assinatura no PostgreSQL 17.

São executados: instalação, aplicação do pacote transacional sobre uma carreira com partida v1 aberta e resultado antigo, retomada dessa partida, reaplicação das migrações, suíte do treinador existente, suíte de competições existente, integridade/RLS/preservação, classificações entre temporadas, todos os certificados, 300 partidas de calibração e criação concorrente de temporada em duas conexões. As suítes SQL usam dados fictícios e rollback. O teste do navegador intercepta toda a API Supabase e usa apenas as respostas fictícias geradas localmente.

Regenerar dados de referência:

```sh
python -m pip install -r scripts/requirements-swiss.txt
python scripts/certify-swiss-draws.py
node scripts/build-competitions.mjs
```

OR-Tools é uma dependência apenas da geração dos certificados. Nem o cliente nem o banco em produção precisam de Python/OR-Tools.

## Implantar no Supabase dos testadores

1. Manter `public/maintenance.json` com `enabled: true`. Confirmar o bloqueio REST/RPC para testadores conforme `supabase/maintenance/README.md`; a tela sozinha não bloqueia clientes antigos.
2. Obter backup/restauração pelo painel do Supabase. Preservar o código SQL atual das funções personalizadas se o banco tiver modificações fora deste repositório.
3. Executar `supabase/evolution/preflight_seasons.sql` (somente leitura). Todos os contadores de inconsistência precisam ser zero. Qualquer duplicação ou vínculo inválido exige diagnóstico individual; não apagar registros para forçar a migração.
4. Gerar o pacote revisável: `node scripts/build-seasons-release.mjs /workspace/scratch/seasons-v2.sql`.
5. Executar esse pacote no SQL Editor como administrador. Ele reúne `15_season_integrity.sql` a `20_pending_calendar_repair.sql` em uma única transação, confere chaves diferidas e compara hashes dos jogos disputados antes/depois da reparação. Em erro/timeout, a transação é revertida. Não executar os testes/bootstrap/calibração no banco real.
6. Confirmar na conta administrativa: abrir Temporadas, analisar rival, salvar tática, iniciar/retomar partida e consultar o histórico. Só partidas novas usam v2. A interface habilita os controles novos somente quando o hub informa `simulation_version=2`, permitindo publicar o cliente sem antecipar funções ainda inexistentes no banco.
7. Conferir participantes, resultados e saldos dos testadores antes de reabrir o jogo. A manutenção permanece ativa até pedido explícito de liberação.

A `service_role` dá acesso à Data API, mas não instala SQL arbitrário. Para aplicar por automação é necessário Access Token da Management API ou conexão PostgreSQL administrativa, cadastrado nos segredos do ambiente. Nunca colocar essas credenciais no código/SQL nem no chat.

Não usar os antigos `99_rollback.sql` para esta atualização: eles removem estruturas inteiras. Após existir progresso novo, qualquer reversão deve preservar as duas versões do motor e os históricos; restaurar backup exige avaliar os registros criados depois dele.

## Evidência desta alteração

PostgreSQL 17: pacote transacional aplicado sobre carreira legada, reaplicação das seis migrações, continuidade v1, suítes existentes do treinador/competições, integridade/RLS/histórico, 105 certificados e 300 partidas de calibração passaram. Duas conexões simultâneas criaram exatamente uma temporada. O navegador validou análise pré-jogo, plano adversário ao vivo, instruções de entradas e compatibilidade com backend antigo em 390/1280 px. Build aprovado. O lint geral ainda aponta 57 erros preexistentes; os novos componentes e serviços verificados isoladamente passaram. Nenhuma migração foi aplicada ao Supabase real nesta etapa.
