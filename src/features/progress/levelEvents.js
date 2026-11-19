// Subida de nível em qualquer tela: guarda o último nível visto e avisa quando ele aumenta.
// O "visto" vale para a conta (ui_seen no banco): quem abre no PC e depois no celular vê a animação uma vez só.
// O aparelho guarda uma cópia para não perguntar ao banco sem necessidade.
// A primeira leitura só memoriza (não anima). O overlay global (LevelUpOverlay) escuta o evento 'game:levelup'.
import { seenBump } from '../../lib/uiSeen'

const key = (userId) => `game:level:${userId}`
const read = (userId) => {
  try {
    const v = Number(localStorage.getItem(key(userId)))
    return Number.isFinite(v) && v > 0 ? v : null
  } catch {
    return null
  }
}
const remember = (userId, level) => {
  try {
    localStorage.setItem(key(userId), String(level))
  } catch {
    /* armazenamento indisponível: sem animação, sem erro */
  }
}
// outra tela já mostrou a subida (ex.: novidades da atualização): memoriza aqui e na conta
export function rememberLevel(userId, level) {
  if (!userId || !level) return
  remember(userId, level)
  seenBump('level', level).catch(() => {})
}
export function reportLevel(userId, level) {
  if (!userId || !level) return
  const last = read(userId)
  remember(userId, Math.max(level, last || 0))
  if (last && level <= last) return // este aparelho já conhece este nível
  // a conta decide: só anima se nenhum outro aparelho já mostrou esta subida
  seenBump('level', level)
    .then((prev) => {
      if (prev === undefined) { if (last && level > last) showLevelUp(last, level); return }
      if (prev != null && level > prev) showLevelUp(prev, level)
    })
    .catch(() => { if (last && level > last) showLevelUp(last, level) })
}
export function showLevelUp(from, to, extra = {}) {
  window.dispatchEvent(new CustomEvent('game:levelup', { detail: { from, to, ...extra } }))
}
