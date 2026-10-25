import { useCallback, useMemo, useState } from 'react'
import { ArrowDown, ArrowUp, RotateCcw } from 'lucide-react'
import Pitch, { PlayerToken } from './Pitch'
import TacticsPanel from './TacticsPanel'
import useDragSwap from '../hooks/useDragSwap'
import { lineupStrength, ovrTone } from '../utils/managerUtils'

const SCARCITY = { GOL: 1, ZAG: 2, LD: 3, LE: 3, VOL: 4, ATA: 5, MC: 6, MEI: 7, PD: 8, PE: 8 }

// redistribui quem está em campo nas vagas da nova formação (cada um onde rende mais)
function remap(slots, formation, byId) {
  const pool = Object.values(slots || {}).filter((id) => byId[id])
  const next = {}
  const order = [...formation.slots].sort((a, b) => SCARCITY[a.pos] - SCARCITY[b.pos])
  for (const s of order) {
    let best = null
    for (const id of pool) if (!best || (byId[id].ratings?.[s.pos] ?? 0) > (byId[best].ratings?.[s.pos] ?? 0)) best = id
    if (best) {
      next[s.slot] = best
      pool.splice(pool.indexOf(best), 1)
    }
  }
  return next
}

// Estado inicial do editor a partir da partida (quem está em campo, em que vaga, e quem pode entrar)
export function draftFromMatch(players, side, formation) {
  const slots = {}
  const injured = []
  for (const p of players) {
    if (p.side !== side || !p.slot) continue
    if (p.status === 'on' || p.status === 'injured_off') slots[p.slot] = p.id
    if (p.status === 'injured_off') injured.push(p.id)
  }
  const bench = players.filter((p) => p.side === side && p.status === 'bench').map((p) => p.id)
  return { formation, slots, bench, subs: [], injured }
}

// MEXER NO TIME DURANTE O JOGO: o mesmo campo da escalação. Arraste (ou toque em um e depois no outro):
// reserva → titular = substituição; titular ↔ titular = troca de posição. Formação e táticas também mudam aqui.
export default function MatchLineupEditor({
  catalog,
  players,
  squadById,
  side,
  colors,
  serverFormation,
  initialDraft,
  tactics: initialTactics,
  maxSubs,
  subsUsed,
  maxWindows,
  windowsUsed,
  atBreak,
  serverMin,
  onApply,
  onClose,
}) {
  const [draft, setDraft] = useState(initialDraft)
  const [tactics, setTactics] = useState(initialTactics)
  const [view, setView] = useState('lineup')
  const [sel, setSel] = useState(null) // seleção por toque
  const [msg, setMsg] = useState('')

  // jogador = dados do elenco (notas por posição) + situação AO VIVO (condição, cartões, lesão, nota no jogo)
  const byId = useMemo(() => {
    const m = {}
    for (const p of players) {
      if (p.side !== side) continue
      const base = squadById?.[p.id] || {}
      m[p.id] = {
        ...base,
        id: p.id,
        short_name: base.short_name || p.name,
        number: p.number ?? base.number,
        position: base.position || p.natural,
        ratings: base.ratings || { [p.natural]: p.overall },
        secondary: base.secondary || [],
        condition: Math.round(p.cond),
        injured_days: 0,
        suspended: 0,
        injured: p.status === 'injured_off',
        yellow: p.yellow,
        available: true,
        live: p,
      }
    }
    return m
  }, [players, squadById, side])

  const formation = catalog?.byId?.[draft.formation]
  const subsLeft = maxSubs - subsUsed - draft.subs.length
  const newWindowNeeded = !atBreak && draft.subs.length === 0
  const canSub = subsLeft > 0 && (!newWindowNeeded || windowsUsed < maxWindows)
  const strength = useMemo(() => (formation ? lineupStrength(formation, draft.slots, byId) : null), [formation, draft.slots, byId])

  const flash = (t) => {
    setMsg(t)
    setTimeout(() => setMsg(''), 2600)
  }

  const apply = useCallback(
    (from, to) => {
      setDraft((d) => {
        const slots = { ...d.slots }
        let bench = [...d.bench]
        let subs = [...d.subs]
        const read = (k) => (k.startsWith('slot:') ? slots[k.slice(5)] : bench[Number(k.slice(6))])
        const a = read(from)
        const b = read(to)
        if (!a) return d
        const isSlot = (k) => k.startsWith('slot:')
        if (isSlot(from) && isSlot(to)) {
          // troca de posição (ou ocupa a vaga vazia)
          if (d.injured.includes(a) || (b && d.injured.includes(b))) {
            flash('Jogador lesionado precisa ser substituído, não muda de posição.')
            return d
          }
          slots[to.slice(5)] = a
          if (b) slots[from.slice(5)] = b
          else delete slots[from.slice(5)]
          return { ...d, slots }
        }
        if (!isSlot(from) && !isSlot(to)) return d
        // substituição: um lado é o campo, o outro é o banco
        const slotKey = isSlot(from) ? from.slice(5) : to.slice(5)
        const inId = isSlot(from) ? b : a
        const outId = slots[slotKey]
        if (!inId) return d
        if (!outId) {
          flash('Vaga vazia (expulsão): não dá para colocar mais um jogador em campo.')
          return d
        }
        const prev = subs.find((s) => s.in === outId)
        if (prev) {
          // quem sai acabou de entrar nesta mesma parada: troca a escolha sem gastar outra substituição
          subs = subs.map((s) => (s === prev ? { ...s, in: inId } : s))
          bench = bench.map((x) => (x === inId ? outId : x))
        } else {
          if (!canSub) {
            flash(subsLeft <= 0 ? 'Não há mais substituições.' : 'Você já usou todas as paradas para substituição.')
            return d
          }
          subs.push({ out: outId, in: inId })
          bench = bench.filter((x) => x !== inId)
        }
        slots[slotKey] = inId
        return { ...d, slots, bench, subs }
      })
      setSel(null)
    },
    [canSub, subsLeft],
  )

  const { drag, bind, ghost } = useDragSwap({ onDrop: apply, getPlayer: (pid) => byId[pid] })

  // toque: escolhe um, depois toca no outro
  const tap = (key) => {
    if (!sel) setSel(key)
    else if (sel === key) setSel(null)
    else apply(sel, key)
  }

  function changeFormation(id) {
    if (id === draft.formation) return
    const live = Object.fromEntries(Object.entries(draft.slots).filter(([, pid]) => !draft.injured.includes(pid)))
    const next = remap(live, catalog.byId[id], byId)
    // lesionado ainda não substituído continua ocupando uma vaga
    for (const pid of draft.injured.filter((x) => Object.values(draft.slots).includes(x))) {
      const free = catalog.byId[id].slots.find((s) => !next[s.slot])
      if (free) next[free.slot] = pid
    }
    setDraft((d) => ({ ...d, formation: id, slots: next }))
  }

  const changed = draft.subs.length > 0 || draft.formation !== serverFormation || JSON.stringify(draft.slots) !== JSON.stringify(initialDraft.slots) || JSON.stringify(tactics) !== JSON.stringify(initialTactics)
  const bindTap = (key, pid) => ({ ...bind(key, pid), onClick: () => tap(key) })
  const selCls = (key) => (sel === key ? 'is-picked' : '')

  return (
    <div className="sn-sheet-wrap" onClick={onClose}>
      <div className="sn-sheet is-tall mp" role="dialog" aria-modal="true" aria-label="Mexer no time" onClick={(e) => e.stopPropagation()}>
        <header>
          <div>
            <small>Vale a partir do {serverMin}'</small>
            <strong className="heading">Mexer no time</strong>
          </div>
          <button type="button" className="gx-btn mp-done" onClick={() => onApply({ draft, tactics, changed })}>
            Pronto
          </button>
        </header>
        <div className="sn-seg mp-tabs">
          <button type="button" className={view === 'lineup' ? 'is-on' : ''} onClick={() => setView('lineup')}>
            Escalação
          </button>
          <button type="button" className={view === 'tactics' ? 'is-on' : ''} onClick={() => setView('tactics')}>
            Táticas
          </button>
        </div>

        <div className="sn-sheet-body">
          {view === 'lineup' && (
            <div className="mle">
              <div className="mle-bar">
                <span className={`mle-subs ${subsLeft <= 0 ? 'is-out' : ''}`}>
                  <b>{Math.max(0, subsLeft)}</b> substituições · <b>{Math.max(0, maxWindows - windowsUsed - (draft.subs.length && !atBreak ? 1 : 0))}</b> paradas
                  {atBreak && <em> · intervalo não gasta parada</em>}
                </span>
                {strength && (
                  <span className={`mle-ovr o-${ovrTone(strength.overall)}`} title="Força do time em campo">
                    {strength.overall}
                  </span>
                )}
              </div>

              <div className="tt-forms" role="radiogroup" aria-label="Formação">
                {(catalog?.formations || []).map((f) => (
                  <button key={f.id} type="button" role="radio" aria-checked={draft.formation === f.id} className={draft.formation === f.id ? 'is-on' : ''} onClick={() => changeFormation(f.id)}>
                    {f.name}
                  </button>
                ))}
              </div>

              <div className="mle-pitch">
                <Pitch
                  formation={formation}
                  slots={draft.slots}
                  playersById={byId}
                  colors={colors}
                  selected={sel?.startsWith('slot:') ? sel.slice(5) : null}
                  onSlot={(s) => tap(`slot:${s.slot}`)}
                  bind={bind}
                  drag={drag}
                  live
                />
              </div>

              {draft.subs.length > 0 && (
                <ul className="mp-queue">
                  {draft.subs.map((s) => (
                    <li key={s.out}>
                      <span className="in">
                        <ArrowUp size={13} /> {byId[s.in]?.short_name}
                      </span>
                      <span className="out">
                        <ArrowDown size={13} /> {byId[s.out]?.short_name}
                      </span>
                    </li>
                  ))}
                </ul>
              )}

              <h4 className="mle-title">
                Banco <small>arraste até o jogador que vai sair</small>
              </h4>
              <div className={`tt-bench ${drag ? 'is-dragging' : ''}`}>
                {draft.bench.map((pid, i) => (
                  <div key={pid} className={`tt-bslot ${drag?.over === `bench:${i}` ? 'is-drop' : ''} ${drag?.from === `bench:${i}` ? 'is-dragging' : ''} ${selCls(`bench:${i}`)}`} {...bindTap(`bench:${i}`, pid)}>
                    <PlayerToken player={byId[pid]} pos={byId[pid]?.position} label={byId[pid]?.position} colors={colors} onClick={() => {}} />
                  </div>
                ))}
                {draft.bench.length === 0 && <p className="sn-muted">Ninguém disponível no banco.</p>}
              </div>

              {msg && <p className="mle-msg">{msg}</p>}
              <p className="sn-hint">
                Arraste um reserva até quem vai sair, ou um titular até outra vaga para trocar de posição (também dá para tocar em um e depois no outro). Fora de posição
                o jogador rende menos — a nota mostrada é a que ele terá naquela vaga, e a etiqueta "é MC" indica a posição de origem.
              </p>
              {changed && (
                <button
                  type="button"
                  className="sn-link mle-reset"
                  onClick={() => {
                    setDraft(initialDraft)
                    setTactics(initialTactics)
                    setSel(null)
                  }}
                >
                  <RotateCcw size={14} /> Desfazer mudanças
                </button>
              )}
            </div>
          )}
          {view === 'tactics' && <TacticsPanel compact tactics={tactics} onChange={setTactics} />}
        </div>

        {drag && ghost && (
          <div className="tt-ghost" style={{ left: drag.x, top: drag.y }} aria-hidden="true">
            <PlayerToken player={ghost} pos={drag.over?.startsWith('slot:') ? formation?.slots.find((x) => `slot:${x.slot}` === drag.over)?.pos || ghost.position : ghost.position} colors={colors} />
          </div>
        )}
      </div>
    </div>
  )
}
