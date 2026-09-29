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

## 9. Login com Google via Supabase (autenticação real)

### O que foi feito no código
- `lib/supabaseClient.js`: cliente real do Supabase, usando as variáveis de
  ambiente. Se elas não existirem, o app não quebra — mostra um aviso e a
  tela de login exibe uma mensagem amigável em vez do botão simplesmente
  não fazer nada.
- `context/AuthContext.jsx`: guarda a sessão (`user`), expõe
  `signInWithGoogle()` e `signOut()`, e escuta mudanças de sessão
  (`onAuthStateChange`) — inclusive quando você volta do Google.
- `App.jsx`: decide a tela pela sessão real (`Gate`): sem sessão → login;
  checando a sessão (ex.: acabou de voltar do Google) → a tela de
  carregamento de sempre; com sessão → criação de personagem.
- `playerService.js`: a carreira agora é gravada com o `userId` do
  Supabase Auth, e a regra "uma carreira ativa por vez" passou a ser por
  usuário (antes era por navegador).

**Sobre o "sem reload":** o clique em "Entrar com o Google" precisa navegar
de verdade até o Google (é assim que OAuth funciona) e o Google redireciona
de volta para o seu app. Essa ida e volta ao Google não tem como ser
evitada — é diferente da troca de telas dentro do seu app, que continua sem
nenhum reload. Quando o navegador volta do Google, a tela de carregamento
com a bola giratória aparece enquanto o Supabase confirma a sessão, e cai
direto na criação de personagem.

### Dependência nova
```
npm install @supabase/supabase-js
```

### Passo a passo no Supabase
1. **Criar a organização** (a tela que você já viu): dê um nome, escolha o
   plano **Free** e confirme.
2. **Criar o projeto**: nome (ex. `simulation`), uma **senha do banco**
   (guarde essa senha em um lugar seguro — vai precisar dela depois se for
   mexer direto no Postgres) e a região mais perto do Brasil disponível
   (ex. `South America (São Paulo)`). Aguarde o projeto provisionar
   (1–2 minutos).
3. **Pegar a URL e a chave do projeto**: menu **Settings → API**. Copie:
   - **Project URL** → vai em `VITE_SUPABASE_URL`
   - **anon public** (em "Project API keys") → vai em `VITE_SUPABASE_ANON_KEY`
   Cole os dois no arquivo `.env` (baseado no `.env.example`) na raiz do seu
   projeto.
4. **Configurar as URLs de redirecionamento**: menu
   **Authentication → URL Configuration**:
   - **Site URL**: `http://localhost:5173` (enquanto testa localmente; troque
     para o domínio real quando publicar).
   - **Redirect URLs**: adicione `http://localhost:5173/**` (e, mais tarde,
     `https://seu-dominio.com/**`).
5. **Ativar o provider do Google**: menu **Authentication → Providers →
   Google**, ative o toggle. O Supabase mostra ali um **Callback URL (for
   OAuth)**, algo como
   `https://SEU-PROJETO.supabase.co/auth/v1/callback` — copie esse link,
   você vai usar no Google já já. Deixe essa página aberta numa aba; você
   volta nela para colar o Client ID/Secret do Google no passo 7.

> Sobre o GitHub: a integração do Supabase com seu repositório (que você já
> tem conectada) é para deploy/migrations do banco — não interfere em nada
> na configuração de login do Google, são coisas independentes.

### Passo a passo no Google Cloud Console
6. Acesse [console.cloud.google.com](https://console.cloud.google.com/) e
   crie um projeto nesse mesmo (ou um dedicado para o jogo).
7. **Tela de consentimento OAuth**: menu **APIs & Services → OAuth consent
   screen**.
   - Tipo de usuário: **External**.
   - Preencha nome do app (ex. "Seu Jogador, Sua Jornada"), e-mail de
     suporte e e-mail de contato do desenvolvedor.
   - Em "Scopes", os padrões (`email`, `profile`, `openid`) já bastam.
   - Enquanto o app estiver em modo de teste ("Testing"), adicione seu
     próprio e-mail do Google em "Test users" — só quem estiver nessa lista
     consegue logar até você publicar o app de verdade.
8. **Criar as credenciais**: menu **APIs & Services → Credentials →
   Create Credentials → OAuth client ID**.
   - Tipo de aplicação: **Web application**.
   - **Authorized JavaScript origins**: `http://localhost:5173`.
   - **Authorized redirect URIs**: cole o **Callback URL** que você copiou
     do Supabase no passo 5 (`https://SEU-PROJETO.supabase.co/auth/v1/callback`).
   - Clique em criar. O Google vai mostrar um **Client ID** e um
     **Client Secret** — copie os dois.
9. Volte na aba do Supabase (Authentication → Providers → Google) e cole o
   **Client ID** e o **Client Secret** nos campos correspondentes. Salve.

### Testar
```
npm install @supabase/supabase-js
npm run dev
```
Abra `http://localhost:5173`, clique em "Entrar com o Google", escolha sua
conta (precisa ser uma das "Test users" do passo 7) e confirme que volta
para o app já na tela de criação de personagem.

### Quando for publicar o jogo de verdade
Repita os passos 4 (Site URL/Redirect URLs no Supabase) e 8 (Authorized
origins/redirect URIs no Google) trocando `localhost:5173` pelo domínio
real — os dois sistemas precisam saber o endereço final. E quando o app
estiver pronto para todo mundo, mude a tela de consentimento OAuth do
Google de "Testing" para "In production" (o Google pode pedir uma revisão
se usar escopos sensíveis, mas `email`/`profile` são considerados básicos).
