// Prévia local da escalação das Temporadas: responde mgr_squad e companhia com dados fictícios.
import FORMATIONS from './formations.json'
const POS = ['GOL', 'LD', 'ZAG', 'ZAG', 'LE', 'VOL', 'MC', 'MEI', 'PD', 'PE', 'ATA', 'GOL', 'LD', 'ZAG', 'LE', 'VOL', 'MC', 'MEI', 'PE', 'ATA', 'ATA', 'ZAG', 'MC', 'PD', 'VOL']
const NAMES = ['Agustín Rossi', 'Guillermo Varela', 'Léo Ortiz', 'Léo Pereira', 'Ayrton Lucas', 'Erick Pulgar', 'Jorginho', 'G. de Arrascaeta', 'Luiz Araújo', 'Samuel Lino', 'Pedro', 'Dyogo Alves', 'Emerson Royal', 'Danilo', 'Alex Sandro', 'Saúl Ñíguez', 'Evertton Araújo', 'Nicolás de la Cruz', 'Everton', 'Bruno Henrique', 'Lorran', 'João Victor', 'Jorge Carrascal', 'Michael', 'Allan']
const ALL = ['GOL', 'LD', 'ZAG', 'LE', 'VOL', 'MC', 'MEI', 'PD', 'PE', 'ATA']
const players = POS.map((pos, i) => {
  const ov = 88 - (i % 11) - (i > 10 ? 6 : 0)
  return { id: `p${i}`, short_name: NAMES[i], name: NAMES[i], position: pos, secondary: [], overall: ov, number: i + 1, age: 20 + (i % 14), nationality: 'BRA', club_id: 'flamengo',
    ratings: Object.fromEntries(ALL.map((p) => [p, p === pos ? ov : Math.max(40, ov - 12)])), condition: [100, 94, 88, 76, 64][i % 5], morale: 60, injured_days: i === 13 ? 3 : 0, suspended: i === 17 ? 1 : 0, contract_expires: '2028-06-30' }
})
const f433 = FORMATIONS.find((f) => f.id === '4-3-3') || FORMATIONS[0]
const slots = Object.fromEntries(f433.slots.map((s, i) => [s.slot, players[i].id]))
const lineup = { formation: f433.id, slots, bench: players.slice(11, 21).map((p) => p.id), tactics: {}, issues: [] }
const squad = () => ({ club_id: 'flamengo', players, lineup, rules: { bench: 12 }, squad: { age: 21, limit: 30 }, next_competition: 'brasileirao' })
const RPC = {
  mgr_squad: squad,
  mgr_lineup_save: ({ p_formation, p_slots, p_bench }) => { Object.assign(lineup, { formation: p_formation, slots: p_slots, bench: p_bench }); return { issues: [] } },
  mgr_lineup_auto: squad,
  career_club_dev_read: () => ({ familiarity: [{ formation: f433.id, value: 82 }], energy: { energy: 2, bonus: 0 } }),
}
const json = (b, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } })
const realFetch = window.fetch.bind(window)
window.fetch = async (input, init) => {
  const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url, window.location.href)
  if (!url.pathname.startsWith('/rest/v1/') && !url.pathname.startsWith('/auth/v1/')) return realFetch(input, init)
  if (url.pathname.endsWith('/sim_formations')) return json(FORMATIONS)
  const fn = url.pathname.split('/rpc/')[1]
  return json(RPC[fn] ? RPC[fn](init?.body ? JSON.parse(init.body) : {}) : null)
}
