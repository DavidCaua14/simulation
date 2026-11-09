// Mantém vivas as conexões do banco enquanto alguém está jogando.
// O PostgREST fecha conexões paradas há 60 s e uma conexão nova replaneja todas as funções: abrir uma tela
// custava ~900 ms numa conexão nova contra ~120 ms numa aquecida. Uma chamada vazia a cada 12 s evita isso.
// Só roda com a aba visível, com sessão ativa e com uso recente, para uma aba esquecida não gastar o banco.
const PING_MS = 12_000
const ACTIVE_MS = 3 * 60_000 // sem toque/tecla há 3 min: para de chamar até a próxima interação

export function startKeepWarm(client, isSignedIn) {
  if (!client || typeof document === 'undefined') return () => {}
  let lastActive = Date.now()
  let busy = false
  const touch = () => { lastActive = Date.now() }
  const tick = async () => {
    if (busy || document.hidden || !isSignedIn() || Date.now() - lastActive > ACTIVE_MS) return
    busy = true
    try {
      await client.rpc('keep_warm')
    } catch {
      // sem rede ou banco ocupado: a próxima batida tenta de novo
    } finally {
      busy = false
    }
  }
  const events = ['pointerdown', 'keydown']
  events.forEach((e) => window.addEventListener(e, touch, { passive: true }))
  const id = setInterval(tick, PING_MS)
  return () => {
    clearInterval(id)
    events.forEach((e) => window.removeEventListener(e, touch))
  }
}
