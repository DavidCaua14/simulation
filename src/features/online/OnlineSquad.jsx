import { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Ambulance, ArrowDown, ArrowUp, Ban, ClipboardList, CornerDownLeft, CornerDownRight, Crown, Radio, RotateCcw, Save, Shirt, Star, Target, Users, Wand2, X } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import Pitch from '../seasons/components/Pitch'
import PlanPanel from './components/PlanPanel'
import EfTile from './components/EfTile'
import SquadDrawer from './components/SquadDrawer'
import useHoldDrag from './hooks/useHoldDrag'
import { PitchTokenContext } from '../seasons/components/pitchToken'
import { planShort, planOf } from './plans'
import PositionFilter from '../seasons/components/PositionFilter'
import '../seasons/components/position-filter.css'
import './components/squad-board.css'
import useCatalog from '../seasons/hooks/useCatalog'
import { POS_NAME, condTone, posFit } from '../seasons/utils/managerUtils'
import { applyOnlineItem, autoOnlineLineup, createOnlineLot, fetchOnlineItems, fetchOnlineMarket, fetchOnlineSquad, fetchPlanFit, sellOnlinePlayer, renewOnlinePlayer, saveOnlineLineup, saveOnlineRoles } from './services/onlineApi'
import PlayerSheet from './components/PlayerSheet'
import { asSeasonPlayer, cardTier, clubColors, money } from './onlineUtils'
import '../seasons/seasons.css'
import '../seasons/manager.css'
import '../seasons/matchflow/matchflow.css'

// carta quadrada do eFootball no campo do Elenco (as outras telas do online continuam com a carta de sempre)
const renderTile = ({ player, pos, colors, selected, onClick, label }) => <EfTile player={player} pos={pos} colors={colors} selected={selected} onClick={onClick} label={label} size={58} />

// Campo do Elenco (organização parecida com a do eFootball): as vagas com alturas próximas formam uma linha, as linhas
// se espalham por igual de cima a baixo e, dentro de cada linha, a forma da formação continua (laterais um pouco à
// frente dos zagueiros, pontas um pouco atrás do centroavante). Cartas só se afastam na horizontal se fossem se
// encostar. A formação real continua a mesma no motor.
function spreadRows(formation, tol = 6) {
  if (!formation?.slots?.length) return formation
  const ys = [...new Set(formation.slots.map((s) => s.y))].sort((a, b) => a - b)
  const rowOf = new Map()
  let row = 0
  ys.forEach((y, i) => {
    if (i > 0 && y - ys[i - 1] > tol) row += 1
    rowOf.set(y, row)
  })
  const n = row + 1
  const rows = Array.from({ length: n }, (_, r) => formation.slots.filter((s) => rowOf.get(s.y) === r))
  const deepest = rows.map((rs) => Math.max(...rs.map((s) => s.y)))
  const yAt = (r) => (n === 1 ? 50 : 12 + (r * 79) / (n - 1))
  // degrau dentro da linha: só para a frente (quem é mais avançado sobe um pouco, até 7 pontos)
  const step = (s) => -Math.min(7, (deepest[rowOf.get(s.y)] - s.y) * 2)
  const MIN = 23
  const xOf = new Map()
  rows.forEach((rs) => {
    const inRow = [...rs].sort((a, b) => a.x - b.x)
    if (!inRow.some((s, i) => i > 0 && s.x - inRow[i - 1].x < MIN)) return
    const k = inRow.length
    const span = (k - 1) * MIN
    if (span > 84) inRow.forEach((s, i) => xOf.set(s.slot, 8 + (i * 84) / (k - 1)))
    else {
      const mid = inRow.reduce((a, s) => a + s.x, 0) / k
      const start = Math.min(92 - span, Math.max(8, mid - span / 2))
      inRow.forEach((s, i) => xOf.set(s.slot, start + i * MIN))
    }
  })
  const pos = formation.slots.map((s) => ({ ...s, y: yAt(rowOf.get(s.y)) + step(s), x: xOf.get(s.slot) ?? s.x }))
  // folga final: carta + nome ocupam ~22% da largura e ~14% da altura do campo (celular de 375 px);
  // se duas se sobrepõem, a de cima sobe e a de baixo desce até caberem
  const W = 22
  const H = 14
  for (let it = 0; it < 8; it++) {
    let moved = false
    for (let i = 0; i < pos.length; i++) {
      for (let j = i + 1; j < pos.length; j++) {
        const a = pos[i]
        const b = pos[j]
        const dy = Math.abs(a.y - b.y)
        if (Math.abs(a.x - b.x) >= W || dy >= H) continue
        const push = (H - dy) / 2 + 0.2
        const [up, down] = a.y <= b.y ? [a, b] : [b, a]
        up.y = Math.max(4, up.y - push)
        down.y = Math.min(95, down.y + push)
        moved = true
      }
    }
    if (!moved) break
  }
  return { ...formation, slots: pos }
}

const SCARCITY = { GOL: 1, ZAG: 2, LD: 3, LE: 3, VOL: 4, ATA: 5, MC: 6, MEI: 7, PD: 8, PE: 8 }
// Funções de um jogador só. A ordem dos pênaltis é uma lista (o primeiro em campo cobra no jogo; na disputa, a ordem).
const ROLES = [
  { id: 'captain', label: 'Capitão', Icon: Crown, hint: 'Usa a braçadeira.' },
  { id: 'fk', label: 'Faltas', Icon: Target, hint: 'Chuta direto ou cruza nas faltas perto da área (finalização e técnica).' },
  { id: 'ck_r', label: 'Escanteio pela direita', Icon: CornerDownLeft, hint: 'Cruza os escanteios do lado direito (criação).' },
  { id: 'ck_l', label: 'Escanteio pela esquerda', Icon: CornerDownRight, hint: 'Cruza os escanteios do lado esquerdo (criação).' },
]
const PEN_SLOTS = 5
// funções salvas no formato antigo (pen e ck únicos) → formato novo
const normRoles = (r = {}) => ({
  captain: r.captain || '',
  fk: r.fk || '',
  ck_r: r.ck_r || r.ck || '',
  ck_l: r.ck_l || r.ck || '',
  pen: Array.isArray(r.pen) ? r.pen : r.pen ? [r.pen] : [],
})

// Mantém os mesmos 11 na troca de formação: cada um vai para a vaga nova onde rende mais.
function remap(slots, formation, byId) {
  const pool = Object.values(slots || {}).filter((id) => byId[id])
  const next = {}
  for (const s of [...formation.slots].sort((a, b) => SCARCITY[a.pos] - SCARCITY[b.pos])) {
    let best = null
    for (const id of pool) if (!best || byId[id].ratings[s.pos] > byId[best].ratings[s.pos]) best = id
    if (best) {
      next[s.slot] = best
      pool.splice(pool.indexOf(best), 1)
    }
  }
  return next
}

// Lugar de cada jogador na escalação em edição e troca de dois lugares (campo, banco ou fora da lista).
function whereIn(d, id) {
  const slot = Object.keys(d.slots).find((k) => d.slots[k] === id)
  if (slot) return { kind: 'slot', key: slot }
  const b = d.bench.indexOf(id)
  return b >= 0 ? { kind: 'bench', key: b } : { kind: 'out', key: id }
}
// chave do arrastar ("slot:ZAG1", "bench:3", "bench:new", "p:<id>") → lugar
function keyWhere(d, key) {
  const [kind, ...rest] = key.split(':')
  const v = rest.join(':')
  if (kind === 'slot') return { kind: 'slot', key: v }
  if (kind === 'bench') return { kind: 'bench', key: v === 'new' ? d.bench.length : Number(v) }
  if (kind === 'p') return whereIn(d, v)
  return null
}
function swapDraft(d, a, b) {
  if (!a || !b || (a.kind === 'out' && b.kind === 'out')) return d
  const at = (w) => (w.kind === 'slot' ? d.slots[w.key] : w.kind === 'bench' ? d.bench[w.key] : w.key)
  const slots = { ...d.slots }
  const bench = [...d.bench]
  const ia = at(a)
  const ib = at(b)
  const put = (w, id) => {
    if (w.kind === 'slot') slots[w.key] = id
    else if (w.kind === 'bench') bench[w.key] = id
  }
  put(a, ib)
  put(b, ia)
  // quem foi para "fora" sai do banco; banco sem buracos nem repetidos
  const onField = new Set(Object.values(slots))
  const nextBench = bench.filter((id, i) => id && bench.indexOf(id) === i && !onField.has(id))
  return { ...d, slots, bench: nextBench }
}

// Avisos antes de salvar: fora de posição, lesionado, suspenso, cansado.
function lineupWarnings(formation, slots, byId) {
  const out = []
  for (const s of formation?.slots || []) {
    const p = byId[slots[s.slot]]
    if (!p) continue
    const fit = p.ratings[s.pos] / Math.max(1, p.overall)
    if (p.injured) out.push({ kind: 'bad', text: `${p.name} está lesionado e será trocado no pontapé.` })
    else if (p.suspended) out.push({ kind: 'bad', text: `${p.name} está suspenso na próxima rodada de liga e será trocado.` })
    if (fit < 0.86) out.push({ kind: 'warn', text: `${p.name} (${p.pos}) jogando de ${POS_NAME[s.pos]}: rende ${p.ratings[s.pos]} em vez de ${p.overall}.` })
    if (p.cond < 70 && !p.injured) out.push({ kind: 'warn', text: `${p.name} está cansado (${p.cond}% de condição).` })
  }
  return out
}

export function PlayerCard({ p, tag, colors, selected, onClick, compact }) {
  const tier = cardTier(p)
  return (
    <button type="button" className={`on-card t-${tier} ${selected ? 'is-sel' : ''} ${compact ? 'is-compact' : ''}`} onClick={onClick} aria-pressed={selected}>
      <span className="on-card-ovr"><b>{Math.round(p.ovr)}</b><small>{p.pos}</small></span>
      <span className="on-card-shirt" style={{ '--c1': colors[0], '--c2': colors[1] }}>{p.number ?? ''}</span>
      <span className="on-card-who">
        <strong>{p.star && <Star size={11} aria-label="Craque" />}{p.name}</strong>
        <small>{tag ? `${tag} · ` : ''}{p.age} anos · {money(p.value)}</small>
      </span>
      <span className="on-card-flags">
        {p.injured > 0 && <Ambulance size={13} aria-label="Lesionado" />}
        {p.suspended > 0 && <Ban size={13} aria-label="Suspenso" />}
        {p.yellows > 0 && <i className="mcard y" title={`${p.yellows} amarelo(s) acumulado(s)`} />}
      </span>
      <span className={`on-card-cond ${condTone(p.cond)}`} title={`Condição ${p.cond}%`}><i style={{ width: `${p.cond}%` }} /></span>
    </button>
  )
}

// Elenco e escalação. Toque em uma vaga do campo e depois em outro jogador (no campo, banco ou fora) para trocar.
// Nada é salvo até tocar em Salvar; os avisos aparecem antes. Na aba Jogadores, tocar em um atleta abre a ficha dele.
export default function OnlineSquad({ onOpenMatch, notify, seasonId }) {
  const { catalog } = useCatalog()
  const [squad, setSquad] = useState(null)
  const [draft, setDraft] = useState(null) // {formation, slots, bench, tactics}
  const [view, setView] = useState('team')
  const [sel, setSel] = useState(null) // troca em andamento: {kind:'slot'|'bench'|'out', key}
  const [drawer, setDrawer] = useState(false) // gaveta com todos os jogadores
  const [confirm, setConfirm] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState('')
  const [listed, setListed] = useState(() => new Set())
  const [sheet, setSheet] = useState(null) // ficha aberta: {id, where}
  const [items, setItems] = useState(null) // Apito de Ouro (online_items)
  const [planFit, setPlanFit] = useState(null) // aderência dos estilos e titulares do próximo adversário (escalação salva)
  const [benchPos, setBenchPos] = useState('') // filtro de posição do banco
  // segurar e arrastar: soltar uma carta sobre outra troca os dois de lugar (campo, banco ou gaveta)
  const { drag, bind } = useHoldDrag({
    onDrop: (from, to) => {
      setDraft((d) => (d ? swapDraft(d, keyWhere(d, from), keyWhere(d, to)) : d))
      setSel(null)
    },
    onStart: (from) => {
      setSheet(null)
      if (from.startsWith('p:')) setDrawer(false) // da gaveta: ela fecha e a carta vai para o campo
    },
  })

  const load = (sq) => {
    setSquad(sq)
    if (sq?.lineup) setDraft({ formation: sq.lineup.formation, slots: { ...sq.lineup.slots }, bench: [...sq.lineup.bench], tactics: sq.lineup.tactics || {} })
  }
  const markListed = (market) => setListed(new Set((market?.lots || []).filter((l) => l.mine).map((l) => l.player.id)))
  useEffect(() => {
    fetchOnlineSquad().then(load).catch((e) => setError(e.message))
    fetchOnlineMarket().then(markListed).catch(() => {})
    fetchOnlineItems().then(setItems).catch(() => {})
  }, [])
  useEffect(() => {
    if (view === 'tactics') fetchPlanFit().then(setPlanFit).catch(() => setPlanFit(null))
  }, [view, squad])

  const byId = useMemo(() => Object.fromEntries((squad?.players || []).map((p) => [p.id, asSeasonPlayer(p, posFit)])), [squad])
  const colors = clubColors(squad?.club)
  const formation = catalog?.byId?.[draft?.formation]
  const boardFormation = useMemo(() => spreadRows(formation), [formation])
  const dirty = squad?.lineup && draft && JSON.stringify({ f: draft.formation, s: draft.slots, b: draft.bench, t: draft.tactics }) !==
    JSON.stringify({ f: squad.lineup.formation, s: squad.lineup.slots, b: squad.lineup.bench, t: squad.lineup.tactics || {} })

  if (!squad || !catalog) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />
  if (!squad.lineup || !draft) return <Skeleton rows={8} />

  const onField = new Set(Object.values(draft.slots))
  const benchSet = new Set(draft.bench)
  const out = squad.players.filter((p) => !onField.has(p.id) && !benchSet.has(p.id))
  const idAt = (s) => (s.kind === 'slot' ? draft.slots[s.key] : s.kind === 'bench' ? draft.bench[s.key] : s.key)

  // troca dois lugares quaisquer (vaga, banco ou fora)
  const swap = (a, b) => setDraft(swapDraft(draft, a, b))
  // onde o jogador está agora (vaga do campo, banco ou fora da lista)
  const whereOf = (id) => whereIn(draft, id)
  const whereLabel = (w) => (w.kind === 'slot' ? `titular (${formation?.slots.find((x) => x.slot === w.key)?.pos || w.key})` : w.kind === 'bench' ? 'reserva' : 'fora da lista')
  // toque no campo, no banco ou na gaveta: com uma troca em andamento, troca; senão abre a ficha (vaga vazia: escolher quem entra)
  const tap = (where) => {
    if (busy) return
    if (sel) {
      if (sel.kind === where.kind && sel.key === where.key) return setSel(null)
      swap(sel, where)
      setSel(null)
      setDrawer(false)
      return
    }
    const id = idAt(where)
    if (id) setSheet({ id, where })
    else setSel(where)
  }

  const changeFormation = (id) => {
    const next = catalog.byId[id]
    if (!next || id === draft.formation) return
    setConfirm({
      title: `Mudar para ${next.name}?`,
      ok: () => setDraft({ ...draft, formation: id, slots: remap(draft.slots, next, byId) }),
    })
  }

  const save = () => {
    const warnings = lineupWarnings(formation, draft.slots, byId)
    const go = () => {
      setBusy(true)
      setError('')
      saveOnlineLineup({ formation: draft.formation, slots: draft.slots, bench: draft.bench, tactics: draft.tactics })
        .then((sq) => {
          load(sq)
          setSaved('Escalação salva')
        })
        .catch((e) => setError(e.message))
        .finally(() => setBusy(false))
    }
    if (warnings.length) setConfirm({ title: 'Salvar mesmo assim?', list: warnings, ok: go })
    else go()
  }
  const auto = () => {
    setConfirm({
      title: 'Montar o melhor time?',
      ok: () => {
        setBusy(true)
        autoOnlineLineup(draft.formation).then(load).catch((e) => setError(e.message)).finally(() => setBusy(false))
      },
    })
  }
  const roles = normRoles(squad.lineup.roles)
  const saveRoles = (next) => {
    const clean = { ...next, pen: next.pen.filter(Boolean) }
    for (const k of ['captain', 'fk', 'ck_r', 'ck_l']) if (!clean[k]) delete clean[k]
    saveOnlineRoles(clean).then(load).catch((e) => setError(e.message))
  }
  const setRole = (role, id) => saveRoles({ ...roles, [role]: id })
  const setPen = (i, id) => {
    const pen = [...roles.pen]
    while (pen.length < i) pen.push('')
    const at = pen.indexOf(id)
    if (id && at >= 0 && at !== i) pen[at] = pen[i] || '' // já estava na lista: troca de lugar
    pen[i] = id
    saveRoles({ ...roles, pen })
  }
  const movePen = (i, d) => {
    const pen = [...roles.pen]
    const j = i + d
    if (j < 0 || j >= pen.length) return
    ;[pen[i], pen[j]] = [pen[j], pen[i]]
    saveRoles({ ...roles, pen })
  }

  const fieldIds = Object.values(draft.slots)
  // força geral: média da nota de titulares + reservas relacionados (mesma conta de on_strength, mostrada no início do modo)
  const xiOvr = fieldIds.map((id) => byId[id]?.ovr).filter((v) => v != null)
  const benchOvr = draft.bench.map((id) => byId[id]?.ovr).filter((v) => v != null)
  const avg = (list) => (list.length ? list.reduce((a, b) => a + b, 0) / list.length : 0)
  const squadStrength = avg([...xiOvr, ...benchOvr])
  return (
    <section className="on-squad">
      {squad.live_fixture && (
        <button type="button" className="on-live-banner" onClick={() => onOpenMatch?.(squad.live_fixture)}>
          <Radio size={16} /> Seu time está em campo <b>Assumir o comando</b>
        </button>
      )}
      <div className="on-seg on-seg-4" role="tablist" aria-label="Elenco">
        <button type="button" role="tab" aria-selected={view === 'team'} className={view === 'team' ? 'is-on' : ''} onClick={() => setView('team')}><Shirt size={15} /> Time</button>
        <button type="button" role="tab" aria-selected={view === 'tactics'} className={view === 'tactics' ? 'is-on' : ''} onClick={() => setView('tactics')}><ClipboardList size={15} /> Táticas</button>
        <button type="button" role="tab" aria-selected={view === 'roles'} className={view === 'roles' ? 'is-on' : ''} onClick={() => setView('roles')}><Crown size={15} /> Funções</button>
        <button type="button" role="tab" aria-selected={view === 'players'} className={view === 'players' ? 'is-on' : ''} onClick={() => setView('players')}><Users size={15} /> Jogadores</button>
      </div>
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}
      {saved && !dirty && <Notice kind="success" onClose={() => setSaved('')}>{saved}</Notice>}

      {view === 'team' && (
        <div className="ef-board">
          <div className="ef-top">
            <label className="ef-form">
              <span className="sr-only">Formação</span>
              <select value={draft.formation} disabled={busy} onChange={(e) => changeFormation(e.target.value)}>
                {catalog.formations.map((f) => <option key={f.id} value={f.id}>{f.name}</option>)}
              </select>
            </label>
            <button type="button" className="ef-plan" onClick={() => setView('tactics')}>{planShort(planOf(draft.tactics))}</button>
            <span className="ef-power" title={`Média ${squadStrength ? squadStrength.toFixed(1) : '–'} com as reservas`}>
              <small>Força coletiva</small><b>{Math.round(xiOvr.reduce((a, b) => a + b, 0))}</b>
            </span>
          </div>
          {sel && (
            <div className="ef-swap" role="status">
              <span>{idAt(sel) ? <>Toque em quem troca com <b>{byId[idAt(sel)]?.name}</b></> : 'Toque em quem entra nesta vaga'}</span>
              <button type="button" onClick={() => setDrawer(true)}>Ver todos</button>
              <button type="button" onClick={() => setSel(null)}>Cancelar</button>
            </div>
          )}
          <div className="ef-pitch">
            <PitchTokenContext.Provider value={renderTile}>
              <Pitch
                formation={boardFormation}
                slots={draft.slots}
                playersById={byId}
                colors={colors}
                selected={sel?.kind === 'slot' ? sel.key : null}
                onSlot={(s) => tap({ kind: 'slot', key: s.slot })}
                bind={bind}
                drag={drag}
              />
            </PitchTokenContext.Provider>
          </div>
          <div className="ef-tools">
            <button type="button" className="ef-tool" onClick={() => setDrawer(true)}><Users size={17} /> Jogadores <small>{out.length}</small></button>
            <button type="button" className="ef-tool" disabled={busy} onClick={auto}><Wand2 size={17} /> Escolha automática</button>
          </div>
          <div className="ef-benchbox">
            <h3 className="ef-h">Banco <small>{draft.bench.length}/12 · arraste até o jogador que vai sair</small></h3>
            <PositionFilter value={benchPos} onChange={setBenchPos} label="Posição no banco" />
            <div className={`ef-bench ${drag ? 'is-dragging' : ''}`}>
              {draft.bench.map((id, i) => byId[id] && (!benchPos || byId[id].pos === benchPos) && (
                <div key={id} className={`ef-bslot ${drag?.over === `bench:${i}` ? 'is-drop' : ''} ${drag?.from === `bench:${i}` ? 'is-dragging' : ''}`} {...bind(`bench:${i}`, id)}>
                  <EfTile player={byId[id]} colors={colors} size={62} selected={sel?.kind === 'bench' && sel.key === i} onClick={() => tap({ kind: 'bench', key: i })} />
                  <span className={`ef-pct ${condTone(byId[id].cond)}`}>{Math.round(byId[id].cond ?? 100)}%</span>
                </div>
              ))}
              {draft.bench.length < 12 && !benchPos && (
                <div className={`ef-bslot ${drag?.over === 'bench:new' ? 'is-drop' : ''}`} {...bind('bench:new', null)}>
                  <EfTile player={null} label="Vaga" size={62} selected={sel?.kind === 'bench' && sel.key === draft.bench.length} onClick={() => tap({ kind: 'bench', key: draft.bench.length })} />
                </div>
              )}
              {benchPos && !draft.bench.some((id) => byId[id]?.pos === benchPos) && <p className="ef-note">Nenhum {benchPos} no banco.</p>}
            </div>
          </div>
          <p className="ef-note">Toque no jogador para abrir o menu · encoste e arraste para trocar de lugar</p>
          {out.length > 0 && <p className="ef-note">{out.length} não relacionado(s) · abra <b>Jogadores</b> para trazer alguém</p>}
          {drag && byId[drag.pid] && (
            <div className="ef-ghost" style={{ left: drag.x, top: drag.y }} aria-hidden="true"><EfTile player={byId[drag.pid]} colors={colors} /></div>
          )}
        </div>
      )}

      {view === 'tactics' && (
        <div className="on-panel-dark">
          <PlanPanel tactics={draft.tactics} fit={planFit} onChange={(t) => setDraft({ ...draft, tactics: t })}
            mine={fieldIds.map((id) => byId[id]).filter(Boolean).map((p) => ({ id: p.id, name: p.name, pos: p.pos, ovr: p.ovr }))} />
        </div>
      )}

      {view === 'roles' && (
        <div className="on-roles">
          {ROLES.map(({ id, label, Icon, hint }) => (
            <label key={id} className="on-role">
              <span><Icon size={16} /> {label}</span>
              <select value={roles[id] || ''} onChange={(e) => setRole(id, e.target.value)}>
                <option value="">Automático</option>
                {fieldIds.map((pid) => byId[pid] && <option key={pid} value={pid}>{byId[pid].name} · {byId[pid].pos} {Math.round(byId[pid].ovr)}</option>)}
              </select>
              <small>{hint}</small>
            </label>
          ))}
          <section className="on-role on-pens" aria-label="Ordem dos pênaltis">
            <span><Target size={16} /> Ordem dos pênaltis</span>
            <ol>
              {Array.from({ length: PEN_SLOTS }, (_, i) => {
                const cur = roles.pen[i] || ''
                return (
                  <li key={i}>
                    <b>{i + 1}º</b>
                    <select value={cur} onChange={(e) => setPen(i, e.target.value)} aria-label={`${i + 1}º cobrador`}>
                      <option value="">{i === 0 ? 'Automático' : '—'}</option>
                      {fieldIds.map((pid) => byId[pid] && <option key={pid} value={pid}>{byId[pid].name} · {byId[pid].pos} {Math.round(byId[pid].ovr)}</option>)}
                    </select>
                    <button type="button" disabled={!cur || i === 0} onClick={() => movePen(i, -1)} aria-label="Subir"><ArrowUp size={14} /></button>
                    <button type="button" disabled={!cur || i >= roles.pen.length - 1} onClick={() => movePen(i, 1)} aria-label="Descer"><ArrowDown size={14} /></button>
                    <button type="button" disabled={!cur} onClick={() => setPen(i, '')} aria-label="Tirar"><X size={14} /></button>
                  </li>
                )
              })}
            </ol>
            <small>O 1º em campo cobra os pênaltis do jogo. Na disputa, a ordem é esta; depois vêm os melhores batedores e o goleiro por último.</small>
          </section>
          <p className="ef-note">Se um cobrador ou o capitão for substituído, quem entrar no lugar dele assume a função.</p>
        </div>
      )}

      {view === 'players' && (
        <div className="on-deals">
          <h3 className="on-h">Elenco <small>{squad.players.length}/28</small></h3>
          {squad.players.map((p) => {
            const left = (p.contract_end ?? 0) - (seasonId || 0)
            return <PlayerCard key={p.id} p={byId[p.id]} colors={colors} tag={listed.has(p.id) ? 'em leilão' : left <= 0 ? 'último ano' : `contrato +${left}`} onClick={() => setSheet({ id: p.id, where: whereOf(p.id) })} />
          })}
        </div>
      )}

      {dirty && (
        <div className="on-savebar">
          <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => load(squad)}><RotateCcw size={15} /> Desfazer</button>
          <button type="button" className="gx-btn" disabled={busy} onClick={save}><Save size={15} /> {busy ? 'Salvando…' : 'Salvar escalação'}</button>
        </div>
      )}

      {drawer && (
        <SquadDrawer
          title="Não relacionados"
          players={(sel ? squad.players : out).map((p) => byId[p.id])}
          statusOf={(id) => whereOf(id).kind}
          colors={colors}
          swapping={sel ? (idAt(sel) ? byId[idAt(sel)]?.name : 'a vaga escolhida') : null}
          onPick={(id) => tap(whereOf(id))}
          bind={bind}
          onClose={() => setDrawer(false)}
        />
      )}

      {sheet && byId[sheet.id] && (
        <PlayerSheet p={byId[sheet.id]} club={squad.club} seasonId={seasonId} busy={busy} listed={listed.has(sheet.id)} onClose={() => setSheet(null)}
          where={whereLabel(sheet.where)}
          onSwap={() => { setSel(sheet.where); setSheet(null); setDrawer(false); setView('team') }}
          onRoles={() => { setSheet(null); setDrawer(false); setView('roles') }}
          items={items}
          onUseItem={(pl) =>
            applyOnlineItem(pl.id).then(async (r) => {
              setItems((it) => (it ? { ...it, items: r.items } : it))
              // só a ficha dos jogadores muda: a escalação em edição fica como está
              const sq = await fetchOnlineSquad().catch(() => null)
              if (sq) setSquad(sq)
              return r
            })}
          onAuction={(pl, price) => {
            setBusy(true)
            createOnlineLot(pl.id, price).then((m) => { markListed(m); setSheet(null); notify?.(`${pl.name} em leilão por 1 hora`, 'success') }).catch((e) => notify?.(e.message, 'alert')).finally(() => setBusy(false))
          }}
          onSell={(pl) => {
            setBusy(true)
            sellOnlinePlayer(pl.id).then((sq) => { load(sq); setSheet(null); notify?.(`${pl.name} dispensado`, 'success') }).catch((e) => notify?.(e.message, 'alert')).finally(() => setBusy(false))
          }}
          onRenew={(pl, y) => {
            setBusy(true)
            renewOnlinePlayer(pl.id, y).then((sq) => { load(sq); setSheet(null); notify?.(`${pl.name} renovou por mais ${y} temporada(s).`, 'success') }).catch((e) => notify?.(e.message, 'alert')).finally(() => setBusy(false))
          }}
        />
      )}

      {confirm && (
        <div className="on-modal" role="dialog" aria-modal="true" aria-label={confirm.title}>
          <div className="on-modal-card gx-panel">
            <h3>{confirm.list ? <AlertTriangle size={18} /> : null} {confirm.title}</h3>
            {confirm.text && <p>{confirm.text}</p>}
            {confirm.list && <ul>{confirm.list.map((w, i) => <li key={i} className={`is-${w.kind}`}>{w.text}</li>)}</ul>}
            <div className="on-modal-actions">
              <button type="button" className="gx-btn-ghost" onClick={() => setConfirm(null)}>Voltar</button>
              <button type="button" className="gx-btn" onClick={() => { confirm.ok(); setConfirm(null) }}>Confirmar</button>
            </div>
          </div>
        </div>
      )}
    </section>
  )
}
