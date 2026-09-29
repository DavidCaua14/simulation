# Como integrar no seu projeto `simulation`

## 1. Copiar arquivos
Copie a pasta `src/` deste pacote para dentro do seu projeto Vite
(`simulation/src`), substituindo `App.jsx` e `main.jsx`. Copie também o
`.env.example` para a raiz do projeto.

Pode apagar (não são mais usados): `src/App.css`, `src/assets/react.svg`,
`src/assets/vite.svg`, `src/assets/hero.png`.

## 2. Dependências
Só o **lucide-react** (ícones). O 3D foi removido do fluxo, então, se você
instalou antes, pode desinstalar:

```
npm install lucide-react
npm uninstall three @react-three/fiber @react-three/drei   # opcional
npm run dev
```

## 3. Tela de criação de personagem (`features/player/CreateCharacterScreen.jsx`)
Tudo em uma tela só, como uma "ficha de RPG":

- **Cartão do personagem** (`components/CharacterCard.jsx`): retrato redondo
  com moldura, selo de nível (NV 1), placa de nome com a bandeira e barra de
  XP. Atualiza ao vivo conforme você preenche.
- **Ficha** (linhas listradas, rótulo à esquerda e valor à direita, como a
  caixa de dados de jogador do PES/Bomba Patch):
  - **Foto**: escolhe só uma, sempre redonda (`data/profilePhotos.js`).
  - **Username**: único (3 a 16 caracteres; letras, números e `_`).
  - **Idade**: de 18 a 45 anos (`data/gameConstants.js`), com botões − / +.
  - **Nacionalidade**: Brasil e Inglaterra (`data/countries.js`); define os
    times iniciais no futuro.
- Botão **Iniciar carreira** fixo embaixo, habilitado só com tudo válido.
- Sem barra de rolagem visível: em janelas muito baixas o conteúdo ainda rola
  por toque/roda do mouse, mas o botão nunca sai da tela.

### Trocar/adicionar fotos de perfil
Coloque o arquivo em `features/player/assets/photos/` e adicione uma linha em
`data/profilePhotos.js`. A tela se ajusta ao número de fotos. As duas atuais
são as imagens que você enviou, recortadas no rosto e convertidas para WebP
(~40 KB cada). No banco guardamos só o `id` da foto (`photoId`).

## 4. Dados do personagem (`playerService.js`)
Hoje em `localStorage`, com os `TODO` mostrando a troca para Supabase. Ao
criar: `nickname`, `photoId`, `country`, `age`, `level: 1`, `xp: 0`,
`skills` iniciais baixas e `accessories: []` (loja futura). `position` e
`jerseyNumber` ficam `null` por enquanto. As regras de idade e username único
também são validadas no serviço, não só na tela.

## 5. Visual
Paleta a partir das fotos (vermelho/brasa + dourado de RPG), tema escuro
grafite e claro em cinza, alternável pelo botão no topo (o padrão agora é o
escuro). Fontes: Rajdhani (títulos) e Inter (texto). O app continua em
formato de celular, de cima a baixo, também no desktop.

## 6. Guardado para depois
`components/Pitch.jsx`, `data/pitchLayout.js` e `data/positions.js` (campo com
as 11 posições) não estão mais na criação, mas ficam prontos para quando a
posição voltar a ser escolhida.

## 7. Próximas etapas sugeridas
1. Tela inicial (Home) do personagem e a regra de 1 carreira ativa por vez
   (`hasActiveCareer()`).
2. Escolha de posição e número da camisa.
3. Progressão real: curva de XP, tarefas e partidas.
4. Migração do `playerService.js` para Supabase.

## 8. Tela de login (`features/auth/LoginScreen.jsx`)
Recriação da referência que você mandou: fundo do estádio (a foto que você
enviou, comprimida em `features/auth/assets/login-bg.webp`), emblema
"SEU JOGADOR / SUA JORNADA" com coroa e bola, "ENTRE EM CAMPO", os 4
destaques com ícone (Evoluir/Defender/Conquistar/Viver a jornada) e o botão
branco "Entrar com o Google" com o logo oficial nas 4 cores.

**O login não é real** — o botão só simula a entrada. `App.jsx` controla 3
telas (`login` → `entering` → `character`): ao clicar, mostra a tela de
carregamento própria do jogo (`components/layout/AppLoadingScreen.jsx`, bola
girando nas cores do sistema) por ~0,9s e troca para a criação de
personagem — sem nenhum reload de página. Quando o login com Google for
implementado de verdade, a troca de tela é feita no `handleLogin` do
`App.jsx`.

Pontos onde não dá pra cravar 100% idêntico ao mockup: o emblema do topo é
recriado em CSS/SVG (forma de escudo, coroa e bola), não é a mesma
ilustração pixel a pixel; e o título usa a mesma fonte do resto do app
(Rajdhani) em vez de uma fonte de pôster à parte, pra manter consistência
visual com as outras telas.
