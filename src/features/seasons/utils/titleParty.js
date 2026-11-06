// Título conquistado: tela de festa uma vez por competição e temporada. Nos pontos corridos ela aparece assim
// que o título fica garantido matematicamente (o servidor devolve hub.titles com kind 'clinched' ou 'champion').
const seenKey = (account, season, comp) => `title-party:${account || 'anon'}:${season}:${comp}`

export function pendingTitle(hub, account) {
  const season = hub?.season?.id
  if (!season) return null
  for (const t of hub.titles || []) {
    try {
      if (window.localStorage.getItem(seenKey(account, season, t.competition))) continue
    } catch {
      // sem armazenamento: mostra mesmo assim (no pior caso, a festa repete)
    }
    return t
  }
  return null
}

export function markTitleSeen(account, season, comp) {
  try {
    window.localStorage.setItem(seenKey(account, season, comp), '1')
  } catch {
    // segue sem lembrar
  }
}
