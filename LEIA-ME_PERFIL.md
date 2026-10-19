# Perfil + música de fundo

## 1) Trocar "Mais" por "Perfil" na barra de baixo
Abra `src/features/home/components/BottomTabBar.jsx`, ache o item com id `more`
(label "Mais") e troque:

    // antes
    { id: 'more', label: 'Mais', icon: ... }
    // depois
    { id: 'profile', label: 'Perfil', icon: UserIcon }

Use o ícone de usuário que você já tem em `components/ui/icons` ou importe
`UserIcon` de `features/profile/components/ProfileIcons`.
O App já trata o id `profile` (e também `home` e `tips`).

## 2) Colocar as músicas (passo a passo)

1. **Prepare os arquivos.** Formato `.mp3`, ideal 128 a 192 kbps (3 a 5 MB cada).
   Renomeie para `01.mp3`, `02.mp3` ... `10.mp3` (sem espaços, acentos ou maiúsculas).
   Use só músicas com licença livre (YouTube Audio Library, Pixabay Music,
   Free Music Archive) e guarde o link de onde baixou cada uma.
2. **Copie para a pasta `public/audio/`.** Ela fica na raiz do projeto, ao lado
   do `package.json` (NÃO dentro de `src/`). Se a pasta não existir, crie.

       meu-projeto/
       ├── package.json
       ├── public/
       │   └── audio/
       │       ├── 01.mp3
       │       ├── 02.mp3
       │       └── ... até 10.mp3
       └── src/

3. **Confira `src/features/audio/playlist.js`.** Cada linha aponta para um arquivo:

       { src: 'audio/01.mp3', title: 'Torcida em Festa' },

   Troque o `title` pelo nome que quer exibir. Se o seu arquivo tiver outro nome,
   ajuste o `src` (ex.: `'audio/hino.mp3'`). Tem menos de 10 músicas? Apague as
   linhas que não for usar.
4. **Rode o projeto** (`npm run dev`) e abra o jogo. Toque uma vez em qualquer
   lugar da tela: a música começa (os navegadores só liberam som depois de um toque).
5. **Ajuste o som** em Perfil > Som do jogo (volume, pausar, próxima/anterior).

Trocar uma música depois = substituir o arquivo em `public/audio/` por outro com
o mesmo nome. Não precisa mexer em código.

### Se a música não tocar
- Abra `http://localhost:5173/audio/01.mp3` no navegador. Se não tocar/baixar, o
  arquivo está na pasta errada ou com nome diferente. (A porta pode ser outra.)
- Nome precisa ser idêntico, inclusive maiúsculas/minúsculas (servidores de
  produção diferenciam).
- Abra o Console (F12): mensagens `[audio] não foi possível abrir` mostram qual
  arquivo falhou. Faixa com problema é pulada; se nenhuma abrir, a música para.
- Pausou no Perfil de propósito? A escolha fica salva. Toque em play.
- Em produção, rode `npm run build`: a pasta `public/` é copiada para o site final.
- iPhone/Safari ignora o controle de volume de elementos de áudio (o volume
  segue o botão do aparelho). Se precisar do slider no iPhone, dá para trocar
  por Web Audio (GainNode).

## 3) Pré-visualizar a vitrine de cartas
`src/features/profile/data/cards.js` -> `USE_SAMPLE_CARDS = true` (volte para false em produção).

## 4) Salvar banner/foto na conta (opcional, depois)
Hoje ficam no aparelho (localStorage). Para sincronizar:
    alter table careers add column banner_id text, add column avatar_url text, add column showcase_public boolean default true;
e troque `read`/`write` em `profileStore.js` por leitura/gravação nessas colunas.
