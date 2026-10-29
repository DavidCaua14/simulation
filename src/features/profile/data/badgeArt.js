// Arte das insígnias (src/assets/badges/<id da insígnia>.webp). Sem arte, o BadgeGrid usa o ícone vetorial do banco.
const files = import.meta.glob('../../../assets/badges/*.webp', { eager: true, import: 'default' })
export const BADGE_ART = Object.fromEntries(Object.entries(files).map(([path, url]) => [path.split('/').pop().replace('.webp', ''), url]))
