// Opções de banner do perfil.
// type: 'color' hoje. Para adicionar imagens no futuro, basta incluir itens assim:
//   { id: 'estadio-1', name: 'Estádio', type: 'image', src: '/banners/estadio-1.jpg' }
export const BANNERS = [
  { id: 'gramado', name: 'Gramado', type: 'color', value: 'linear-gradient(135deg,#0b4a2a 0%,#1f9d55 100%)' },
  { id: 'noite', name: 'Noite de jogo', type: 'color', value: 'linear-gradient(135deg,#0a1633 0%,#2447a8 100%)' },
  { id: 'ouro', name: 'Ouro', type: 'color', value: 'linear-gradient(135deg,#6b4a06 0%,#e0a82e 100%)' },
  { id: 'rubro', name: 'Rubro', type: 'color', value: 'linear-gradient(135deg,#4d0a12 0%,#d6283a 100%)' },
  { id: 'elite', name: 'Elite', type: 'color', value: 'linear-gradient(135deg,#2a1055 0%,#7a3df0 100%)' },
  { id: 'grafite', name: 'Grafite', type: 'color', value: 'linear-gradient(135deg,#14181f 0%,#454f60 100%)' },
  { id: 'laranja', name: 'Arquibancada', type: 'color', value: 'linear-gradient(135deg,#6b2a05 0%,#f08a24 100%)' },
  { id: 'ciano', name: 'Mar aberto', type: 'color', value: 'linear-gradient(135deg,#053a4a 0%,#12b4cf 100%)' },
]

export const DEFAULT_BANNER_ID = 'gramado'

export function getBanner(id) {
  return BANNERS.find((b) => b.id === id) ?? BANNERS[0]
}

// Converte o banner em estilo CSS (cor/gradiente ou imagem)
export function bannerStyle(banner) {
  if (banner.type === 'image') {
    return { backgroundImage: `url(${banner.src})`, backgroundSize: 'cover', backgroundPosition: 'center' }
  }
  return { background: banner.value }
}
