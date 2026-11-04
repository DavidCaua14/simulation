// Assistente da primeira temporada: lembrado só neste navegador, por carreira (conveniência, não é progresso).
export const assistantKey = (id) => `sim.assistant.${id}`
export function assistantDone(careerId) {
  try {
    return window.localStorage.getItem(assistantKey(careerId)) === 'done'
  } catch {
    return true
  }
}
