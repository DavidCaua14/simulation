// Subida de nível em qualquer tela: guarda o último nível visto por conta (no aparelho) e avisa quando ele aumenta.
// A primeira leitura só memoriza (não anima). O overlay global (LevelUpOverlay) escuta o evento 'game:levelup'.
const key = (userId) => `game:level:${userId}`
const read = (userId) => {
  try {
    const v = Number(localStorage.getItem(key(userId)))
    return Number.isFinite(v) && v > 0 ? v : null
  } catch {
    return null
  }
}
export function rememberLevel(userId, level) {
  if (!userId || !level) return
  try {
    localStorage.setItem(key(userId), String(level))
  } catch {
    /* armazenamento indisponível: sem animação, sem erro */
  }
}
export function reportLevel(userId, level) {
  if (!userId || !level) return
  const last = read(userId)
  rememberLevel(userId, Math.max(level, last || 0))
  if (last && level > last) showLevelUp(last, level)
}
export function showLevelUp(from, to, extra = {}) {
  window.dispatchEvent(new CustomEvent('game:levelup', { detail: { from, to, ...extra } }))
}
