# Escudos dos clubes e emblemas dos campeonatos

* **Clubes (141, todos os do jogo):** `public/crests/<id>.svg`, a partir da coleção enviada pelo dono do projeto
  (`logos.zip`, separada por país; origem: football-logos.cc — a atribuição dentro de cada SVG foi mantida).
  O mapa clube → arquivo da coleção fica em `data/clubs/crest_sources.json` (revisado um a um, com prévia visual).
* **Campeonatos do modo Temporadas (9):** `public/competitions/<id>.svg` (Série A, Série B, Copa do Brasil,
  Libertadores, Premier League, Championship, FA Cup, EFL Cup, Champions League), dos SVGs enviados à parte. A Copa do
  Brasil usa só o troféu (o logo inteiro é horizontal e ficaria minúsculo no emblema).
* **Competições dos Palpites (15):** mesmos emblemas quando é o mesmo campeonato; as demais (La Liga, Serie A,
  Bundesliga, Ligue 1, Primeira Liga, Eredivisie, Série C, Eurocopa, Copa do Mundo) vêm da coleção —
  `data/competitions/prediction_emblem_sources.json`. Os escudos dos times dos Palpites continuam vindo da API.

## Onde aparecem

* `ClubCrest` (todas as telas: tabela, chaves, partidas, cartas, perfil, propostas…). Sem arquivo, o jogo desenha um
  escudo com as cores do clube. No tema escuro há um contorno claro bem fino para escudos pretos/azul-marinho e, no
  claro, um contorno escuro para escudos brancos — o desenho não muda.
* `CompEmblem` (26 lugares do modo Temporadas): o emblema oficial numa placa clara com filete na cor do torneio,
  legível nos dois temas. Se a imagem não abrir, volta o escudo desenhado.

## Atualizar ou incluir

1. Extraia o `logos.zip` em qualquer pasta.
2. Clube novo: acrescente `"id-do-clube": "pais/Arquivo.svg"` em `data/clubs/crest_sources.json`.
3. `node scripts/import-crests.mjs <pasta>/logos` — copia os arquivos, gera `src/features/club/data/crests.js` e
   `competitionEmblems.js` e avisa clube sem escudo ou arquivo inexistente. Arquivo acima de 150 KB vira WebP de
   256 px se o pacote `sharp` estiver instalado (hoje: Roma, Libertadores, Eurocopa e Copa do Mundo).

`scripts/fetch-crests.mjs` (download pela internet) ficou como legado, só para um clube que não exista na coleção.

Os escudos e emblemas são marcas dos clubes e entidades; o uso no jogo é responsabilidade do dono do projeto.
