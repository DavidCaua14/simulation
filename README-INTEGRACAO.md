# Como integrar no seu projeto `simulation`

## 1. Copiar arquivos
Copie a pasta `src/` inteira deste pacote para dentro do seu projeto Vite
(`simulation/src`), substituindo `App.jsx` e `main.jsx`. Copie também o
`.env.example` para a raiz do projeto.

Pode apagar (não são mais usados):
- `src/App.css`
- `src/assets/react.svg`, `src/assets/vite.svg`, `src/assets/hero.png`

## 2. Rodar
Nenhuma dependência nova é necessária.

```
npm install
npm run dev
```

## 3. O que mudou nesta rodada

### Full-bleed, igual celular também no desktop
`AppShell` agora ocupa `100dvh` de cima a baixo, sem padding, sem
`border-radius`, sem "cartão flutuando". Em telas largas, a largura fica
travada em 430px (com uma linha sutil nas laterais só para separar do fundo),
mas a altura sempre preenche a tela inteira — exatamente como abrir um app
mobile num navegador de desktop.

### Sem barra de rolagem: fluxo dividido em 4 telas
A criação de jogador virou um wizard (`CreatePlayerWizard.jsx`) com 4 etapas,
cada uma pensada para caber na tela sem precisar rolar:
1. **Avatar** (`steps/AvatarStep.jsx`) — enviar foto ou escolher um avatar
   padrão.
2. **Nickname** (`steps/NicknameStep.jsx`).
3. **Posição** (`steps/PositionStep.jsx`) — campo visual, ver abaixo.
4. **Resumo** (`steps/SummaryStep.jsx`) — número da camisa, idade e
   confirmação final.

Navegação por botão "Voltar"/"Próximo" fixos no rodapé de cada etapa, e
pontinhos de progresso no topo (`components/StepDots.jsx`).

### Avatares novos + upload de foto
Os avatares desenhados à mão saíram. Agora são círculos lisos com cor sólida
(`data/avatarPresets.js`) — visual limpo, no mesmo estilo do resto do app —
e o usuário pode enviar a própria foto (`utils/resizeImage.js` recorta em
quadrado e reduz para 240px antes de salvar, pra não pesar no
`localStorage`). Quando a foto existe, ela tem prioridade sobre o avatar
padrão.

### Posição escolhida no campo
`components/Pitch.jsx` desenha uma escalação (campo verde com linhas, áreas
e círculo central em SVG) e posiciona um botão para cada posição
(`data/pitchLayout.js` tem as coordenadas). O usuário toca na posição do
campo em vez de escolher em uma lista.

## 4. Onde cada regra de negócio já mencionada está modelada
- `playerService.js`: `createPlayer`, `isNicknameTaken`, `hasActiveCareer` —
  hoje em `localStorage`, com os `TODO` mostrando a troca equivalente para
  Supabase (incluindo onde entraria o upload da foto no Supabase Storage).
- Idade fixa em 16 anos e atributos iniciais baixos: dentro de
  `createPlayer`.

## 5. Próximas etapas sugeridas
1. Tela Home (carreira ativa: atributos, nível, XP, time atual) e a decisão
   "continuar carreira" vs. "nova carreira" usando `hasActiveCareer()`.
2. Simulação de partida + ganho de XP.
3. Migração do `playerService.js` para Supabase (schema de `careers`,
   `players`, `duels`) e da foto para Supabase Storage.
