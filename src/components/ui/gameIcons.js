// Ilustrações dos ícones do jogo (src/assets/icons/<nome>.webp).
const files = import.meta.glob('../../assets/icons/*.webp', { eager: true, import: 'default' })
export const GAME_ICONS = Object.fromEntries(Object.entries(files).map(([path, url]) => [path.split('/').pop().replace('.webp', ''), url]))
