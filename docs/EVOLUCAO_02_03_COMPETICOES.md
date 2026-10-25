# Etapas 2 e 3 — Competições europeias, Série B e acesso/rebaixamento

As duas etapas usam o mesmo motor novo (formato configurável por competição), por isso foram entregues juntas,
com testes separados para cada uma.

## O que mudou

### Motor de competições configurável
* Cada competição descreve suas **fases** em `sim_competitions.rules.phases` (liga, grupos, fase de liga suíça, mata-mata
  de jogo único ou ida e volta, prorrogação, pênaltis, campo neutro, critério de empate, quem entra em cada fase e o tipo
  de chaveamento). Fonte editável: `data/competitions/competitions.json`.
* **Regiões**: cada temporada do treinador é disputada no país do clube — Brasil (Série A, Série B, Copa do Brasil,
  Libertadores) ou Inglaterra (Premier League, Championship, FA Cup, EFL Cup, Champions League). No meio da temporada as
  propostas vêm do mesmo país; na janela do fim da temporada podem vir do outro (a próxima temporada começa lá).
* **Participantes por temporada** (`season_participants`): a 1ª temporada usa os participantes oficiais; as seguintes
  saem do fim da temporada anterior. Índice único impede um clube em duas divisões na mesma temporada.
* **Acesso e rebaixamento** (`sim_promotion_rules`, configurável por ano) aplicado uma única vez por temporada
  (`season_transitions` com chave única; rodar de novo devolve o mesmo resultado). O histórico das temporadas
  anteriores (jogos, campeões, estatísticas) não é alterado e nenhum jogador é recriado.
* **Vagas continentais**: as vagas do país na Libertadores / Champions passam para os mais bem colocados da liga na
  temporada anterior (mesma quantidade de vagas da edição de referência).
* Objetivos da diretoria, metas das propostas, bônus, mensagens e prêmios passaram a valer para qualquer competição.
* Calendário: a próxima rodada é sempre a do campeonato mais atrasado (rodadas feitas / rodadas previstas), com
  prioridade configurável — igual ao comportamento anterior.

### Premier League 2026/27
20 clubes oficiais, 38 rodadas, desempate oficial (pontos, saldo, gols, confronto direto, gols fora no confronto
direto), 3 rebaixados, 9 reservas no banco (regulamento da liga). Zonas na tabela: top 5 (Champions) e Z3.

### EFL Championship 2026/27
24 clubes, 46 rodadas e o **playoff novo de 6 clubes** (aprovado para 2026/27): 1º e 2º sobem; 5º×8º e 6º×7º em jogo
único na casa do mais bem colocado; semifinais em ida e volta (3º contra o vencedor de pior campanha, 4º contra o outro,
o mais bem colocado decide em casa); final em Wembley. Sobe o vencedor da final.

### FA Cup 2026/27
Mata-mata em jogo único, **sem replays** (abolidos desde 2024/25), prorrogação e pênaltis; semifinal e final em campo
neutro (Wembley).

### EFL Cup (Carabao Cup) 2026/27
Jogo único com pênaltis direto (sem prorrogação) até as quartas; semifinal em ida e volta; final em Wembley com
prorrogação e pênaltis.

### UEFA Champions League 2026/27
36 clubes nos potes oficiais; fase de liga com 8 jogos (2 adversários de cada pote, 4 em casa e 4 fora); desempate
oficial (pontos, saldo, gols, gols fora, vitórias, vitórias fora, pontos/saldo/gols dos adversários, disciplina);
1º–8º direto às oitavas; 9º–24º no playoff (9º/10º × 23º/24º, 11º/12º × 21º/22º, 13º/14º × 19º/20º, 15º/16º × 17º/18º,
cabeça de chave decide em casa); 25º–36º eliminados; oitavas com 1º/2º contra os vencedores do 15º/16º–17º/18º etc.;
chave fixa até a final, 1º e 2º em lados opostos, o mais bem colocado decide em casa; final em campo neutro.
O calendário da fase de liga vem de modelos válidos (gerados por `scripts/gen-swiss-template.py`) com sorteio das vagas
de cada pote a cada temporada, evitando clubes do mesmo país no mesmo jogo.

### Série B 2026 e acesso/rebaixamento no Brasil
20 clubes oficiais, 38 rodadas; **1º e 2º sobem direto; 3º×6º e 4º×5º em playoff de ida e volta** (o mais bem colocado
decide em casa e, com empate no agregado, se classifica — sem pênaltis); os dois vencedores também sobem.
Série A: 4 rebaixados. Total: 4 sobem e 4 caem.

## Dados oficiais e fontes
* Clubes e participantes: Wikipedia (páginas das temporadas 2026/27 da Premier League, Championship, FA Cup, EFL Cup,
  UCL e fase de liga; Série B 2026), tabelas finais de 2025/26 (PL e Championship) e 2025 (Série A e Série B).
* Regulamentos: Sky Sports (playoff de 6 clubes da Championship), TNT Sports (FA Cup sem replays), Band (Série B 2026),
  páginas de cada edição. Todas as fontes estão em `sim_competitions.sources`.
* Elencos: 93 clubes novos em `data/squads/raw/*.txt` (fonte e data em cada arquivo; Wikipedia e, para São Bernardo,
  o site oficial do clube). Total do jogo: 141 clubes e 4.245 jogadores. Os ids dos jogadores que já existiam não mudaram.
* **Força dos clubes** (estimativa de gameplay, não dado oficial) calculada por fórmula a partir de um dado oficial:
  posição na temporada anterior (PL, Championship, Série A/B), acesso da League One / Série C ou coeficiente de clube da
  UEFA (potes 2026/27). Fórmulas em `scripts/build-competitions.mjs`.

## Adaptações (documentadas, não inventadas)
* **Divisões inferiores não modeladas** (League One/Two, Série C, não-liga): por isso
  * FA Cup começa na 3ª fase só com os 24 clubes da Championship (12 jogos) e os 20 da Premier League entram na 4ª fase
    (32 clubes). Na edição real os 44 entram na 3ª fase junto com 20 clubes de divisões inferiores, que ainda não
    estão definidos para 2026/27.
  * EFL Cup: a 1ª e a 2ª fases viraram uma "fase preliminar" com os 24 da Championship; os 20 da Premier League entram
    na 3ª fase (32 clubes), como os clubes em competição europeia na edição real.
  * Rebaixamento da Championship e da Série B não acontece (não há divisão abaixo no jogo): as duas ligas recebem os
    rebaixados de cima e mandam os promovidos.
* Copa do Brasil e grupos da Libertadores seguem a chave de referência de 2026 a cada temporada (como antes).
* Champions/Libertadores de clubes de outros países usam o elenco da edição de referência em todas as temporadas.

## Pendências
* **Escudos dos 93 clubes novos**: o ambiente de desenvolvimento não baixa imagens. Eles aparecem com o escudo desenhado
  nas cores do clube. Para baixar os oficiais: `node scripts/fetch-crests.mjs` na sua máquina (os clubes novos já estão
  na lista do script).
* Nacionalidade não informada pela fonte: Athletic (Sofascore) e São Bernardo (site oficial).
* 52 listas de elenco são anteriores a julho de 2026 ou sem data — ver `data/squads/IMPORT_REPORT.md`.
* Cores de alguns clubes estrangeiros são aproximadas (editáveis em `data/clubs/clubs_evolution.json`).
* Em raros sorteios, a fase de liga da UCL pode ter um jogo entre clubes do mesmo país (o sorteio escolhe a melhor
  combinação entre 300 tentativas).

## Testes executados
* `supabase/evolution/tests/competitions_tests.sql` (T1–T7): dados de referência; calendário inglês (PL 380,
  Championship 552, UCL 144 com 8 jogos/4 em casa/2 por pote); temporada inglesa completa (todas as fases das copas,
  chaves da UCL, playoff da Championship); acesso/rebaixamento inglês (3+3, idempotência, chave única, classificação para
  a UCL, divisão única por temporada); Série A/B com playoff decidido pelo critério do mais bem colocado; regras da fase
  chegando ao motor da partida; equivalência das regras antigas. **Todos passaram.**
* `supabase/manager/tests/manager_tests.sql` (T0–T6) no motor novo: **todos passaram**.
* Simulação completa com o motor de atributos: 2 temporadas na Inglaterra (Sunderland → classificação para a UCL,
  demissão, Bolton), 2 temporadas no Brasil com clube da Série B (Goiás, playoff, acesso) e uma carreira criada ANTES da
  migração (Mirassol) continuada depois dela até a temporada seguinte com Série B. Tempo médio: avançar 0,7 s, partida
  0,5 s, hub 0,09 s (máximo 2,4 s, abaixo do limite de 8 s do Supabase).
* Interface testada no navegador (Playwright) nas duas regiões: abas por formato (Tabela/Playoff/Chave/Rodadas/
  Artilharia), zonas configuradas na tabela, temporada "2026/27" na Inglaterra.
