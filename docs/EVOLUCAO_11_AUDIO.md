# Etapa 11 — Áudio e imersão

O sistema de música que já existia foi mantido (mesmas faixas em `public/audio`, mesmo player que não para ao trocar
de tela, preferências salvas). Foram acrescentados efeitos sonoros, controles separados e a ambientação das partidas.

## Efeitos sonoros — origem e licença
**Todos os efeitos são sintetizados no próprio jogo** com a Web Audio API (`src/features/audio/sfx.js`: osciladores e
ruído filtrado). São criação original — nenhuma gravação de terceiros, nenhuma questão de licença.
Quando houver gravações licenciadas, basta colocá-las em `public/audio/sfx/` e apontar em `sfxConfig.js`; se o arquivo
falhar, o jogo volta ao som sintetizado.

**Recursos de áudio pendentes (opcionais, melhorariam a imersão):** gravação de comemoração e de lamento de torcida,
loop de ambiente de estádio (30–60 s) e apito real de árbitro. As 4 faixas de música em `public/audio` já existiam
antes desta etapa; a licença delas **não está documentada no projeto** — confirme a origem antes de publicar.

## Onde há som (com critério — não em todo elemento)
| Ação | Som |
|---|---|
| Botões principais (`.gx-btn`) | clique curto |
| Selecionar carta (coleção, carta em destaque) | seleção |
| Abrir telas (Loja, Cartas, Perfil, Amigos, Temporadas, Palpites) | deslize suave |
| Compra confirmada (loja, mercado, anúncio, energia, visual) | moedas |
| Recompensa (caixa aberta, prêmio da roleta) | fanfarra; carta rara/Épica: fanfarra maior |
| Subida de nível (pós-jogo) e insígnia nova (perfil) | fanfarra de conquista |
| Convite de amizade novo (em tempo real) | notificação |
| Início da partida | apito |

Cliques repetidos do mesmo som em menos de 60 ms não se empilham.

## Partida
Ao abrir a partida ao vivo:
1. a música é **pausada, abaixada (25%) ou mantida**, conforme a preferência "Música durante a partida";
2. começa a **ambientação de estádio** (torcida contínua que "respira");
3. cada lance toca **no momento em que aparece na tela** (o mesmo relógio da narração), e só lances que o motor gerou:
   apito inicial, apito duplo no intervalo e na prorrogação, apito triplo no fim; gol do seu time = explosão da torcida,
   gol do adversário = comemoração menor e lamento; amarelo = apito + murmúrio; vermelho/segundo amarelo = apito + vaia;
   impedimento/lesão = apito curto; pênalti perdido e grande chance = "uhhh". Sem gol não há comemoração; sem
   expulsão não há som de expulsão; chute comum e substituição não fazem barulho;
4. a torcida fica mais intensa depois de lances fortes e nos minutos finais de jogo apertado;
5. ao sair da partida a ambientação para e a música volta conforme a preferência.
Partida retomada não repete os sons dos lances que já tinham passado.

## Controles (Perfil → Som do jogo)
Escolher a faixa (lista) · tocar/pausar · anterior/próxima · **volume da música** · **volume dos efeitos** (separado,
com botão de teste) · **silenciar o jogo** (música e efeitos) · música durante a partida (pausar/abaixar/manter) ·
torcida e estádio liga/desliga. Tudo salvo no aparelho (`localStorage`, como já era).

## Navegadores
Nenhum som é tocado antes de um gesto do usuário: o motor de efeitos só é criado no primeiro toque/tecla; antes disso
os pedidos de som são ignorados sem erro. A música continua com a regra antiga (tenta tocar; se bloqueada, começa no
primeiro toque) — e, com "pausar na partida", um toque no meio do jogo não religa a música. O player é único
(acima de todas as telas), então trocar de tela nunca cria uma segunda instância.

## Testes (navegador real, Chromium, medindo o sinal na saída com um analisador)
* Antes do gesto: nenhum contexto de áudio criado. Depois: **os 16 efeitos produzem sinal** (nenhum mudo).
* Silenciar: saída 0. Volume de efeitos e de música independentes.
* Partida com "pausar": música pausada na entrada, um toque no meio do jogo **não** a religa, ambientação tocando
  (RMS ≈ 0,03), música volta no fim, ambientação vai a 0.
* Mapa lance → som: gol do usuário ≠ gol do adversário, amarelo, vermelho; chute comum e substituição sem som.
* Partida real no modo Temporadas até o apito final: ambientação durante o jogo, silêncio depois, nenhum erro.
