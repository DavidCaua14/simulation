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

## 10. Corrigindo o redirecionamento do login (volta pra tela de login em vez de criar personagem)

Isso é configuração, não código. O motivo quase certo: o **Site URL** foi
configurado, mas a **Redirect URLs** (é uma lista separada, na mesma
página) não tem a URL do seu app da Vercel. Sem isso, o Supabase, por
segurança, redireciona de volta sem anexar a sessão — daí o app não vê
ninguém logado e mostra o login de novo.

**Como corrigir:**
1. Vá em **Authentication → URL Configuration**
   (`https://supabase.com/dashboard/project/nkdbixmfsochlprcvkxl/auth/url-configuration`).
2. No campo **Redirect URLs** (abaixo do Site URL), adicione, cada uma em
   uma linha:
   - `https://simulation-teal-gamma.vercel.app/**`
   - `http://localhost:5173/**` (pra continuar testando local)
3. Salve.
4. Teste de novo numa aba anônima (evita sessão/cache antigos atrapalharem).

O resto da sua configuração (Site URL, Origens JavaScript no Google, URI de
redirecionamento apontando pro callback do Supabase) já está certo — só
faltou esse item.

## 11. Onde ficam guardados os dados (e como conferir)

**Importante:** até esta atualização, só o **login** passava pelo Supabase.
Nickname, idade, foto, nível, XP etc. ainda estavam só no `localStorage` do
seu navegador — nunca saíam dali. A partir de agora isso mudou: o
personagem é salvo de verdade no banco do Supabase.

### 1. Rodar a criação da tabela (só uma vez)
Abra **SQL Editor** no painel do Supabase
(`https://supabase.com/dashboard/project/nkdbixmfsochlprcvkxl/sql/new`),
cole o conteúdo do arquivo `supabase/schema.sql` (está no zip) e clique em
**Run**. Isso cria:
- a tabela `careers` (nickname, foto, país, idade, nível, xp, skills,
  acessórios...);
- a regra "1 carreira ativa por usuário" e "nickname único", garantidas
  pelo próprio banco (não só pela tela);
- **Row Level Security**: cada usuário só enxerga e só edita as próprias
  carreiras — mesmo alguém mexendo direto na API, não consegue ver dados de
  outro jogador;
- uma função (`is_nickname_taken`) que permite checar se um nickname já
  existe sem violar essa proteção.

### 2. Conferir se está gravando
- **Usuários que logaram**: **Authentication → Users**
  (`.../auth/users`) — aparece cada conta Google que já entrou.
- **Personagens criados**: **Table Editor → careers**
  (`.../editor`) — cada linha é uma carreira, já com `nickname`, `level`,
  `xp`, `skills` etc. Dá pra ver em tempo real: crie um personagem no app e
  atualize essa tabela.
- Repare que o `user_id` de cada linha bate com o `id` de um usuário lá em
  Authentication → Users — é esse vínculo que faz a regra "1 carreira ativa
  por usuário" funcionar.

### 3. O que muda no código
`playerService.js` trocou de `localStorage` para consultas reais
(`supabase.from('careers')...`). A checagem de username disponível virou
assíncrona de verdade (chama o banco com um pequeno atraso de 450ms depois
que você para de digitar, pra não disparar uma consulta a cada tecla) —
`CreateCharacterScreen.jsx` mostra "Verificando disponibilidade..." nesse
intervalo.

Já testei esse fluxo simulando as respostas do Supabase (nickname
indisponível, disponível, e até o caso de dois usuários tentarem o mesmo
nickname ao mesmo tempo) — os três casos tratam o erro corretamente sem
travar a tela.

### 4. Dependência
Nenhuma nova — já usa o `@supabase/supabase-js` que você instalou no passo
anterior.

## 12. Login volta pra tela de login mesmo com o token na URL

Se depois de corrigir as Redirect URLs (seção 10) o comportamento virou
"a URL volta com `#access_token=...`, mas o app mostra a tela de login de
novo" — eu reproduzi exatamente esse cenário aqui (mesmo formato de token,
mesma sequência) contra o código deste projeto, e funcionou: a sessão foi
reconhecida e a tela trocou para a criação de personagem. Ou seja, o
código em si funciona; o problema está em um destes três pontos, nesta
ordem de probabilidade:

### 1. A Vercel pode não estar com a versão mais nova do código
Confira em **Vercel → seu projeto → Deployments**: o deployment mais
recente precisa ser DEPOIS de você ter colocado os arquivos
`AuthContext.jsx` / `App.jsx` / `LoginScreen.jsx` no seu repositório do
GitHub (commit + push) — a Vercel não pega os arquivos de um zip sozinha,
só redeploya quando detecta um novo commit na branch conectada (`main`,
pelo que vi no seu print). Clique no deployment mais recente e confira a
mensagem/hash do commit.

### 2. Sessão antiga travada no navegador
Como você testou várias vezes enquanto ainda estava quebrado, pode ter
ficado uma sessão corrompida guardada no navegador. Teste de novo numa
**aba anônima/privada** (ou DevTools → Application → Storage →
**Clear site data** no seu domínio da Vercel) antes de clicar em
"Entrar com o Google" de novo.

### 3. Erro específico que só aparece no seu ambiente
Com a atualização desta rodada, o `AuthContext.jsx` agora imprime no
console do navegador exatamente o que está acontecendo. Teste de novo
com o **DevTools aberto (F12) → aba Console**, e procure linhas
começando com `[auth]`. Eu deveria ver algo assim quando funciona:
```
[auth] evento: INITIAL_SESSION usuário seu@email.com
[auth] sessão inicial: logado como seu@email.com
[auth] evento: SIGNED_IN usuário seu@email.com
```
Se aparecer algo diferente (um erro em vermelho, ou nenhuma linha
`[auth]` nenhuma), me manda o print do console — isso aponta direto pra
causa.

## 13. Tela de propostas de clube (entre criar personagem e a Home)

Depois de criar o personagem, antes da tela inicial, o jogador passa pela
tela de propostas (`features/club/ClubOfferScreen.jsx`):

- O **empresário** (retrato gerado a partir da imagem que você mandou,
  recortado em `features/club/assets/agent-photo.webp`) manda uma sequência
  de mensagens em formato de chat, aparecendo uma a uma — **sem nenhum
  loading** nessa parte, é só o ritmo da conversa (`ChatBubble.jsx`).
- Depois das mensagens, aparecem as **3 propostas** (Botafogo, Fluminense,
  Flamengo — escudos em `features/club/assets/`, recortados e centralizados
  a partir dos arquivos que você enviou). Tocar numa card seleciona; o botão
  "Fechar com [clube]" só libera depois de escolher.
- Ao confirmar: o empresário manda uma última mensagem, e **só então**
  aparece o loading personalizado (o mesmo componente usado em outras
  partes do app) enquanto o clube é salvo de verdade no Supabase.

### Vínculo com o clube
`features/club/clubService.js` grava o clube escolhido direto na carreira
(`careers.club_id`, nova coluna — veja a seção 13.1 abaixo). Esse é o campo
que vai alimentar o futuro modo de simular partidas e a troca de clube:
trocar de time, mais pra frente, é só chamar essa mesma função de novo com
outro `clubId`.

Os clubes disponíveis (nome, escudo, texto da proposta) ficam em
`features/club/data/clubs.js` — adicionar um 4º clube é só incluir uma
entrada ali e colocar o escudo em `assets/`.

### 13.1 Atualizar o banco (rodar uma vez)
Como você já tinha criado a tabela `careers` antes dessa tela existir,
precisa adicionar a coluna nova. Abra o **SQL Editor** no Supabase e rode:
```sql
alter table public.careers add column if not exists club_id text;
```
(Esse comando já está incluído no `supabase/schema.sql` atualizado, caso
prefira rodar o arquivo inteiro de novo — é seguro, não duplica nada.)

### Fluxo completo (já testado)
`App.jsx` guarda a carreira em memória enquanto o jogador avança: cria o
personagem → (sem clube ainda) mostra as propostas → (clube escolhido)
mostra a Home. Tudo sem reload, trocando de componente React.

Testei esse fluxo inteiro simulando as respostas do Supabase: criação do
personagem, as 4 mensagens aparecendo em sequência sem loading, as 3
propostas, seleção, e o salvamento do `club_id` — a "Home" (ainda
provisória, ver seção 14) mostra o clube certo depois.

## 14. Tela inicial (Home) — provisória
`features/home/HomeScreen.jsx` é só um placeholder pra fechar o fluXO por
enquanto: mostra o cartão do personagem e o clube atual. Treinos, partidas,
elenco e troca de clube ficam para a próxima etapa.
