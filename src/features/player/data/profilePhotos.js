// Fotos de perfil disponíveis na criação do personagem (só uma pode ser
// escolhida). Para adicionar mais, coloque o arquivo em assets/photos/ e
// inclua uma linha aqui — a tela se ajusta sozinha ao número de fotos.
// No banco (Supabase) guardamos só o `id`, nunca a imagem em si.
import photo1 from '../assets/photos/photo-1.webp'
import photo2 from '../assets/photos/photo-2.webp'

export const PROFILE_PHOTOS = [
  { id: 'photo-1', src: photo1, label: 'Perfil 1' },
  { id: 'photo-2', src: photo2, label: 'Perfil 2' },
]

export function getProfilePhotoById(photoId) {
  return PROFILE_PHOTOS.find((p) => p.id === photoId)
}
