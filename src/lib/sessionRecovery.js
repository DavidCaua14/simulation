const listeners = new Set()
let rejected = false

export function onSessionExpired(listener) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function resetSessionRecovery() {
  rejected = false
}

export function expireSession() {
  if (rejected) return
  rejected = true
  for (const listener of listeners) listener()
}

export function isSessionError(error) {
  return ['PGRST301', 'PGRST303'].includes(error?.code)
}

// O SDK renova tokens automaticamente antes das requisições. Uma rejeição
// definitiva encerra somente a sessão local, sem repetir uma mutação do jogo.
export function createSessionFetch(fetcher, baseUrl, getCurrentToken = () => null) {
  const base = new URL(baseUrl)
  return async (input, init) => {
    const response = await fetcher(input, init)
    const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url)
    if (url.origin !== base.origin) return response
    const rest = url.pathname.startsWith('/rest/v1/')
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined))
    const sentToken = headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
    const currentToken = getCurrentToken()
    // Uma resposta atrasada da sessão anterior não pode encerrar um login novo.
    if (rest && sentToken && currentToken && sentToken !== currentToken) return response
    const refresh = url.pathname === '/auth/v1/token' && url.searchParams.get('grant_type') === 'refresh_token'
    if ((rest && response.status === 401) || (refresh && [400, 401, 403].includes(response.status))) {
      let error
      try { error = await response.clone().json() } catch { return response }
      if ((rest && isSessionError(error)) || (refresh && [
        'refresh_token_not_found', 'refresh_token_already_used', 'session_not_found', 'invalid_grant',
      ].includes(error?.code ?? error?.error))) expireSession()
    }
    return response
  }
}
