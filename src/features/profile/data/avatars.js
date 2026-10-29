// Avatares que se ganham no jogo (src/assets/avatars/<id>.webp). Só quem tem o avatar pode usá-lo (o banco confere).
const files = import.meta.glob('../../../assets/avatars/*.webp', { eager: true, import: 'default' })
export const AVATAR_ART = Object.fromEntries(Object.entries(files).map(([path, url]) => [path.split('/').pop().replace('.webp', ''), url]))
