// Conta as chamadas que estouram o limite de tempo do banco (erro 57014, statement_timeout).
// O Supabase não expõe mais esses cancelamentos nos logs; o app informa cada um em
// public.report_rpc_timeout, uma vez por função a cada 30 s. Nunca altera a resposta original.
const RPC_PATH = '/rest/v1/rpc/'
const lastReport = new Map()

export function createTimeoutReportFetch(fetcher, baseUrl) {
  const base = new URL(baseUrl)
  return async (input, init) => {
    const response = await fetcher(input, init)
    if (response.status < 500) return response
    try {
      const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url)
      if (url.origin !== base.origin || !url.pathname.startsWith(RPC_PATH)) return response
      const fn = url.pathname.slice(RPC_PATH.length)
      if (fn === 'report_rpc_timeout' || !/^[a-z0-9_]{1,80}$/.test(fn)) return response
      const body = await response.clone().json()
      if (body?.code !== '57014') return response
      const now = Date.now()
      if (now - (lastReport.get(fn) ?? 0) < 30000) return response
      lastReport.set(fn, now)
      const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined))
      headers.set('Content-Type', 'application/json')
      fetcher(`${base.origin}${RPC_PATH}report_rpc_timeout`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ p_fn: fn }),
      }).catch(() => {})
    } catch {
      // O relatório é opcional: qualquer falha aqui é ignorada.
    }
    return response
  }
}
