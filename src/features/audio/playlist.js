// ─────────────────────────────────────────────────────────────────────────────
// PLAYLIST DO JOGO  (arquivos de música locais)
//
// 1) Coloque os arquivos .mp3 na pasta  public/audio/  (na raiz do projeto).
// 2) Aqui, `src` é o caminho dentro dessa pasta:  'audio/01.mp3'
//    (também funciona um link direto https://... para um .mp3 hospedado).
// 3) `title` é o nome que aparece no Perfil.
//
// - Ao terminar uma faixa, toca a próxima; depois da última, volta à primeira.
// - Arquivo que não existir ou não abrir é pulado sozinho.
// - Quer menos de 10 músicas? Apague as linhas que não vai usar.
// ─────────────────────────────────────────────────────────────────────────────
export const PLAYLIST = [
  { src: 'audio/01.mp3', title: 'Faixa 1' },
  { src: 'audio/02.mp3', title: 'Faixa 2' },
  { src: 'audio/03.mp3', title: 'Faixa 3' },
  { src: 'audio/04.mp3', title: 'Faixa 4' },
  // { src: 'audio/05.mp3', title: 'Clássico de Domingo' },
  // { src: 'audio/06.mp3', title: 'Entrada em Campo' },
  // { src: 'audio/07.mp3', title: 'Camisa 10' },
  // { src: 'audio/08.mp3', title: 'Decisão por Pênaltis' },
  // { src: 'audio/09.mp3', title: 'Volta Olímpica' },
  // { src: 'audio/10.mp3', title: 'Campeões da Rua' },
]

// Volume inicial (0–100). Baixo de propósito: o jogador sobe se quiser.
export const DEFAULT_VOLUME = 15
