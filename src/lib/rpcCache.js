// Cache de leituras do modo carreira (2026-11-06): evita ir ao banco toda vez que uma tela abre.
// O banco continua dono do save; aqui só guardamos, em memória, a última resposta de cada leitura.
//
// Regra de validade: o save só muda quando o próprio app escreve (o jogo é de um jogador só).
// Toda chamada RPC que NÃO está na lista de leituras conta como escrita e marca o cache inteiro como velho
// ("época" nova). Assim, uma função nova do servidor nunca fica presa num cache errado: por padrão ela invalida.
// Também invalidam: escrita direta em tabela, troca de conta e voltar à aba depois de um tempo
// (o jogador pode ter jogado em outro aparelho).
const RPC_PATH = '/rest/v1/rpc/'

// Leituras puras do save (conferidas no banco: não gravam nada além de materialização idempotente).
const CAREER_READS = new Set([
  'career_hub_read', 'mgr_squad', 'career_negotiations', 'career_shortlist', 'career_club_dev_read', 'career_drills',
  'mgr_opponent_report', 'career_market_search', 'career_player_search', 'career_calendar', 'career_finance_history',
  'mgr_history', 'mgr_top_scorers', 'season_standings', 'career_offer_club', 'career_vacancies', 'career_vacancy_club',
  'mgr_player_detail', 'mgr_match_report', 'career_wage_demand', 'career_news',
])
// Chamadas que não mudam o save: passam direto, sem cache e sem invalidar.
const NEUTRAL = new Set(['keep_warm', 'report_rpc_timeout','mgr_status', 'career_world_status', 'events_overview', 'ranking_overall'])

const MAX_AGE_MS = 10 * 60 * 1000 // rede de segurança: nenhuma leitura fica mais de 10 min sem conferir
const HIDDEN_RESET_MS = 2 * 60 * 1000 // voltou à aba depois de 2 min: confere tudo de novo
const MAX_ENTRIES = 300

let epoch = 0
const entries = new Map() // chave -> { epoch, at, expiresAt, status, headers, body }
const inflight = new Map() // chave -> Promise da mesma leitura em andamento

export function invalidateRpcCache() {
  epoch++
  entries.clear()
  inflight.clear()
}

// Recarga de energia: o hub muda com o tempo, sem escrita. Vale só até o próximo reset.
function expiresFor(fn, body) {
  if (fn !== 'career_hub_read') return Infinity
  try {
    const at = Date.parse(JSON.parse(body)?.career?.next_reset_at)
    return Number.isFinite(at) ? at : Infinity
  } catch {
    return Infinity
  }
}

function remember(key, value) {
  if (entries.size >= MAX_ENTRIES) entries.delete(entries.keys().next().value)
  entries.set(key, value)
}

const respond = (e) => new Response(e.body, { status: e.status, headers: e.headers })

export function createRpcCache(fetcher, baseUrl, { now = () => Date.now() } = {}) {
  const base = new URL(baseUrl)
  return async (input, init) => {
    let url
    try {
      url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url)
    } catch {
      return fetcher(input, init)
    }
    if (url.origin !== base.origin || !url.pathname.startsWith('/rest/v1/')) return fetcher(input, init)
    const method = (init?.method || (input instanceof Request ? input.method : 'GET')).toUpperCase()

    if (!url.pathname.startsWith(RPC_PATH)) {
      // Leitura de tabela passa direto; escrita em tabela muda o save.
      if (method === 'GET' || method === 'HEAD') return fetcher(input, init)
      invalidateRpcCache()
      try {
        return await fetcher(input, init)
      } finally {
        invalidateRpcCache()
      }
    }

    const fn = url.pathname.slice(RPC_PATH.length)
    if (NEUTRAL.has(fn)) return fetcher(input, init)
    if (!CAREER_READS.has(fn) || (typeof init?.body !== 'string' && init?.body != null)) {
      // Escrita: invalida antes (leituras em andamento não gravam resultado velho) e depois.
      invalidateRpcCache()
      try {
        return await fetcher(input, init)
      } finally {
        invalidateRpcCache()
      }
    }

    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined))
    const key = `${headers.get('Authorization') || ''}|${fn}|${url.search}|${init?.body || ''}`
    const hit = entries.get(key)
    const t = now()
    if (hit && hit.epoch === epoch && t - hit.at < MAX_AGE_MS && t < hit.expiresAt) return respond(hit)
    if (inflight.has(key)) return respond(await inflight.get(key))

    const started = epoch
    const job = (async () => {
      const response = await fetcher(input, init)
      const body = await response.text()
      const e = { epoch: started, at: now(), expiresAt: Infinity, status: response.status, headers: [...response.headers], body }
      if (response.ok) {
        e.expiresAt = expiresFor(fn, body)
        // Só guarda se nenhuma escrita aconteceu enquanto a leitura estava no ar.
        if (started === epoch) remember(key, e)
      }
      return e
    })()
    inflight.set(key, job)
    try {
      return respond(await job)
    } finally {
      if (inflight.get(key) === job) inflight.delete(key)
    }
  }
}

// Voltar ao jogo depois de um tempo fora: o save pode ter mudado em outro aparelho.
if (typeof document !== 'undefined') {
  let hiddenAt = null
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) hiddenAt = Date.now()
    else if (hiddenAt != null && Date.now() - hiddenAt >= HIDDEN_RESET_MS) invalidateRpcCache()
  })
}
