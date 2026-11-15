// Laboratório local (só no `npm run dev`, endereço /#lab3d): abre a tela de partida de verdade (MatchLive)
// com um servidor falso que gera lances, para testar o campo 2D/3D sem login nem banco.
import { useMemo, useState } from 'react'
import { ThemeProvider } from '../../context/ThemeContext'
import { AudioProvider } from '../audio/AudioContext'
import MatchLive from '../seasons/components/MatchLive'
import '../../styles/theme.css'
import '../../styles/desktop.css'
import '../../styles/cm-skin.css'
import '../../styles/cm-screens.css'
import '../cards/cards.css'
import '../seasons/seasons.css'
import '../seasons/manager.css'

const F433 = {
  id: '4-3-3',
  name: '4-3-3',
  sort: 1,
  slots: [
    { slot: 'GOL', pos: 'GOL', x: 50, y: 94 },
    { slot: 'LD', pos: 'LD', x: 88, y: 72 },
    { slot: 'ZAG1', pos: 'ZAG', x: 63, y: 80 },
    { slot: 'ZAG2', pos: 'ZAG', x: 37, y: 80 },
    { slot: 'LE', pos: 'LE', x: 12, y: 72 },
    { slot: 'VOL', pos: 'VOL', x: 50, y: 62 },
    { slot: 'MC1', pos: 'MC', x: 70, y: 48 },
    { slot: 'MC2', pos: 'MC', x: 30, y: 48 },
    { slot: 'PD', pos: 'PD', x: 84, y: 24 },
    { slot: 'ATA', pos: 'ATA', x: 50, y: 16 },
    { slot: 'PE', pos: 'PE', x: 16, y: 24 },
  ],
}
const CATALOG = { formations: [F433], byId: { '4-3-3': F433 } }

const NAMES = {
  h: ['Rossi', 'Varela', 'Léo Ortiz', 'Danilo', 'Ayrton', 'Pulgar', 'De la Cruz', 'Arrascaeta', 'Plata', 'Pedro', 'Cebolinha'],
  a: ['Weverton', 'Mayke', 'Gómez', 'Murilo', 'Piquerez', 'Aníbal', 'Raphael', 'Maurício', 'Estêvão', 'Flaco', 'Facundo'],
}
const NUMBERS = [1, 2, 4, 3, 6, 8, 5, 10, 7, 9, 11]

function rng(seed) {
  let s = seed >>> 0
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0
    return s / 4294967296
  }
}

function makePlayers() {
  const out = []
  for (const side of ['h', 'a']) {
    F433.slots.forEach((s, i) => {
      out.push({ id: `${side}${i + 1}`, side, name: NAMES[side][i], number: NUMBERS[i], pos: s.pos, natural: s.pos, slot: s.slot, status: 'on', cond: 100, rating: 6.5, yellow: 0, red: false, injured: false })
    })
  }
  return out
}

function initialData(home, away) {
  return {
    fixture_id: 'lab',
    home,
    away,
    user_side: 'h',
    status: 'live',
    minute: 0,
    competition: 'bra_a',
    stage: 'league',
    round: 1,
    et: false,
    formation: ['4-3-3', '4-3-3'],
    tactics: { h: { style: 'balanced' }, a: { style: 'balanced' } },
    subs: { h: { used: 0, windows: 0 }, a: { used: 0, windows: 0 } },
    max_subs: 5,
    max_windows: 3,
    stats: { poss: [50, 50], corners: [0, 0], fouls: [0, 0], offsides: [0, 0] },
    players: makePlayers(),
    events: [{ seq: 1, minute: 0, kind: 'kickoff' }],
    summary: null,
  }
}

// Servidor falso: a cada etapa de 5 min sorteia lances com probabilidades parecidas com as do motor.
function fakeApi(getData, setData) {
  const rnd = rng(20261114)
  let seq = 1
  const pick = (side) => {
    const list = getData().players.filter((p) => p.side === side && p.status === 'on' && p.pos !== 'GOL')
    return list[Math.floor(rnd() * list.length)]
  }
  const keeper = (side) => getData().players.find((p) => p.side === side && p.pos === 'GOL')
  return {
    async stepMatch({ from, to }) {
      await new Promise((r) => setTimeout(r, 250))
      const prev = getData()
      const evs = []
      const stats = structuredClone(prev.stats)
      for (let m = from + 1; m <= to; m += 1) {
        const side = rnd() < 0.55 ? 'h' : 'a'
        const opp = side === 'h' ? 'a' : 'h'
        const i = side === 'h' ? 0 : 1
        const r = rnd()
        const p = pick(side)
        const ev = (kind, extra = {}) => evs.push({ seq: ++seq, minute: m, kind, side, player: p.id, player_name: p.name, ...extra })
        if (r < 0.035) {
          // assistente: outro jogador do time (como no motor, com id em player2)
          let a = pick(side)
          for (let k = 0; k < 4 && a.id === p.id; k += 1) a = pick(side)
          ev('goal', a.id !== p.id && rnd() < 0.75 ? { player2: a.id, player2_name: a.name } : {})
        }
        else if (r < 0.085) ev('save', { player2: keeper(opp).id, player2_name: keeper(opp).name, detail: rnd() < 0.3 ? 'grande chance' : null })
        else if (r < 0.14) ev('shot_off', { detail: rnd() < 0.25 ? 'bloqueado' : null })
        else if (r < 0.175) {
          stats.fouls[i] += 1
          ev('yellow')
        } else if (r < 0.2) {
          stats.offsides[i] += 1
          ev('offside')
        } else if (r < 0.205) ev('pen_goal')
        if (rnd() < 0.08) stats.corners[i] += 1
      }
      const finished = to >= 90
      if (to === 45) evs.push({ seq: ++seq, minute: 45, kind: 'ht' })
      if (finished) evs.push({ seq: ++seq, minute: 90, kind: 'ft' })
      const sh = 44 + Math.floor(rnd() * 14)
      stats.poss = [sh, 100 - sh]
      const next = { ...prev, minute: to, status: finished ? 'finished' : 'live', stats, events: evs, stop: to === 45 ? 'ht' : null, summary: finished ? {} : null }
      setData(next)
      return next
    },
    async fetchSquad() {
      return { players: getData().players }
    },
  }
}

export default function MatchLab() {
  const params = new URLSearchParams(window.location.search)
  const home = params.get('home') || 'flamengo'
  const away = params.get('away') || 'fluminense'
  const [run, setRun] = useState(0)
  const { initial, api } = useMemo(() => {
    const box = { cur: initialData(home, away) }
    const a = fakeApi(
      () => box.cur,
      (d) => {
        box.cur = d
      },
    )
    return { initial: box.cur, api: a }
    // nova partida a cada "Recomeçar"
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [run])

  return (
    <ThemeProvider>
      <AudioProvider>
        <div className="seasons-screen">
          <MatchLive key={run} initial={initial} catalog={CATALOG} api={api} myClub={{ id: home }} onFinished={() => setRun((n) => n + 1)} notify={(m) => console.warn('[lab]', m)} />
        </div>
      </AudioProvider>
    </ThemeProvider>
  )
}
