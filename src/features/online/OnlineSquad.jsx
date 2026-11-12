import { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Ambulance, Ban, ClipboardList, Crown, FileSignature, Gauge, Gavel, Radio, UserMinus, RotateCcw, Save, Shirt, Star, Target, Users, Wand2 } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import Pitch from '../seasons/components/Pitch'
import TacticsPanel from '../seasons/components/TacticsPanel'
import useCatalog from '../seasons/hooks/useCatalog'
import { POS_NAME, condTone, posFit } from '../seasons/utils/managerUtils'
import { autoOnlineLineup, createOnlineLot, fetchOnlineMarket, fetchOnlineSquad, sellOnlinePlayer, renewOnlinePlayer, saveOnlineLineup, saveOnlineRoles } from './services/onlineApi'
import { asSeasonPlayer, cardTier, clubColors, money } from './onlineUtils'
import '../seasons/seasons.css'
import '../seasons/manager.css'
import '../seasons/matchflow/matchflow.css'

const SCARCITY = { GOL: 1, ZAG: 2, LD: 3, LE: 3, VOL: 4, ATA: 5, MC: 6, MEI: 7, PD: 8, PE: 8 }
const ROLES = [
  { id: 'captain', label: 'Capitão', Icon: Crown },
  { id: 'pen', label: 'Pênaltis', Icon: Target },
  { id: 'fk', label: 'Faltas', Icon: Target },
  { id: 'ck', label: 'Escanteios', Icon: Target },
]

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
// Nada é salvo até tocar em Salvar; os avisos aparecem antes.
// salário pela nota (mesma fórmula de on_wage no banco)
const wageFor = (ovr, age) => Math.ceil((Math.max(1, ovr - 45) ** 2 * 0.65 + Math.max(0, ovr - 75) ** 2 * 12) * (age < 24 ? 1.1 : age >= 31 ? 0.9 : 1))

const AUCTION_STEPS = [[0.5, 'Mínimo'], [0.75, '75%'], [1, 'Valor'], [1.5, '+50%'], [2, 'Dobro']]
const round100 = (n) => Math.ceil(n / 100) * 100

function PlayerDeal({ p, seasonId, colors, busy, listed, onSell, onRenew, onAuction }) {
  const [mode, setMode] = useState(null)
  const [step, setStep] = useState(1)
  const startPrice = step === 0.5 ? Math.max(500, Math.round(p.value * 0.5)) : round100(p.value * step)
  const ends = p.contract_end ?? 0
  const left = ends - (seasonId || 0)
  return (
    <div className={`on-deal-card ${mode ? 'is-open' : ''}`}>
      <PlayerCard p={p} colors={colors} tag={listed ? 'em leilão' : left <= 0 ? 'último ano' : `contrato +${left}`} onClick={() => setMode(mode ? null : 'menu')} />
      {mode === 'menu' && (
        <div className="on-deal-actions">
          <button type="button" className="gx-btn-ghost" disabled={listed} onClick={() => setMode('auction')}><Gavel size={14} /> Leiloar</button>
          <button type="button" className="gx-btn-ghost" disabled={listed} onClick={() => setMode('sell')}><UserMinus size={14} /> Dispensar</button>
          <button type="button" className="gx-btn-ghost" disabled={left >= 3} onClick={() => setMode('renew')}><FileSignature size={14} /> Renovar</button>
        </div>
      )}
      {mode === 'sell' && (
        <div className="on-deal-actions">
          <button type="button" className="gx-btn" disabled={busy} onClick={() => onSell(p)}><UserMinus size={14} /> Dispensar · +{money(p.sell ?? Math.round(p.value * 0.6))}</button>
          <button type="button" className="gx-btn-ghost" onClick={() => setMode(null)}>Cancelar</button>
          <small>Ele deixa o clube e volta ao mercado</small>
        </div>
      )}
      {mode === 'auction' && (
        <div className="on-deal-actions on-deal-auction">
          <div className="on-auc-steps" role="group" aria-label="Lance inicial">
            {AUCTION_STEPS.map(([v, label]) => <button key={v} type="button" className={step === v ? 'is-on' : ''} onClick={() => setStep(v)}>{label}</button>)}
          </div>
          <button type="button" className="gx-btn" disabled={busy} onClick={() => { onAuction(p, startPrice); setMode(null) }}><Gavel size={14} /> Leiloar · {money(startPrice)}</button>
          <button type="button" className="gx-btn-ghost" onClick={() => setMode(null)}>Cancelar</button>
          <small>1 hora no mercado · valor {money(p.value)}</small>
        </div>
      )}
      {mode === 'renew' && (
        <div className="on-deal-actions">
          {[1, 2, 3].filter((y) => left + y <= 3).map((y) => {
            const w = wageFor(p.ovr, p.age)
            return (
              <button key={y} type="button" className="gx-btn-ghost" disabled={busy} onClick={() => onRenew(p, y)}>
                +{y} temp. · luva {money(w * 8 * y)}
              </button>
            )
          })}
          <small>Salário {money(p.wage)} → {money(wageFor(p.ovr, p.age))}/dia</small>
        </div>
      )}
    </div>
  )
}

export default function OnlineSquad({ onOpenMatch, notify, seasonId }) {
  const { catalog } = useCatalog()
  const [squad, setSquad] = useState(null)
  const [draft, setDraft] = useState(null) // {formation, slots, bench, tactics}
  const [view, setView] = useState('team')
  const [sel, setSel] = useState(null) // {kind:'slot'|'bench'|'out', key}
  const [confirm, setConfirm] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState('')
  const [listed, setListed] = useState(() => new Set())

  const load = (sq) => {
    setSquad(sq)
    if (sq?.lineup) setDraft({ formation: sq.lineup.formation, slots: { ...sq.lineup.slots }, bench: [...sq.lineup.bench], tactics: sq.lineup.tactics || {} })
  }
  const markListed = (market) => setListed(new Set((market?.lots || []).filter((l) => l.mine).map((l) => l.player.id)))
  useEffect(() => {
    fetchOnlineSquad().then(load).catch((e) => setError(e.message))
    fetchOnlineMarket().then(markListed).catch(() => {})
  }, [])

  const byId = useMemo(() => Object.fromEntries((squad?.players || []).map((p) => [p.id, asSeasonPlayer(p, posFit)])), [squad])
  const colors = clubColors(squad?.club)
  const formation = catalog?.byId?.[draft?.formation]
  const dirty = squad?.lineup && draft && JSON.stringify({ f: draft.formation, s: draft.slots, b: draft.bench, t: draft.tactics }) !==
    JSON.stringify({ f: squad.lineup.formation, s: squad.lineup.slots, b: squad.lineup.bench, t: squad.lineup.tactics || {} })

  if (!squad || !catalog) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />
  if (!squad.lineup || !draft) return <Skeleton rows={8} />

  const onField = new Set(Object.values(draft.slots))
  const benchSet = new Set(draft.bench)
  const out = squad.players.filter((p) => !onField.has(p.id) && !benchSet.has(p.id))
  const idAt = (s) => (s.kind === 'slot' ? draft.slots[s.key] : s.kind === 'bench' ? draft.bench[s.key] : s.key)

  // troca dois lugares quaisquer (vaga, banco ou fora)
  const swap = (a, b) => {
    const slots = { ...draft.slots }
    const bench = [...draft.bench]
    const ia = idAt(a)
    const ib = idAt(b)
    const put = (where, id) => {
      if (where.kind === 'slot') slots[where.key] = id
      else if (where.kind === 'bench') bench[where.key] = id
    }
    put(a, ib)
    put(b, ia)
    // quem foi para "fora" sai do banco
    const nextBench = bench.filter((id, i) => id && bench.indexOf(id) === i && !Object.values(slots).includes(id))
    if (a.kind === 'out' && b.kind === 'out') return
    setDraft({ ...draft, slots, bench: nextBench })
  }
  const tap = (where) => {
    if (busy) return
    if (!sel) return setSel(where)
    if (sel.kind === where.kind && sel.key === where.key) return setSel(null)
    swap(sel, where)
    setSel(null)
  }
  const addToBench = (id) => {
    if (draft.bench.length >= 12) return setError('O banco aceita até 12 jogadores.')
    setDraft({ ...draft, bench: [...draft.bench, id] })
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
  const setRole = (role, id) => {
    const roles = { ...(squad.lineup.roles || {}), [role]: id || undefined }
    saveOnlineRoles(roles).then(load).catch((e) => setError(e.message))
  }

  const fieldIds = Object.values(draft.slots)
  // força: titulares pela nota na vaga; relacionados = titulares + banco (o que aparece no início do modo)
  const xi = (formation?.slots || []).map((sl) => byId[draft.slots[sl.slot]]?.ratings?.[sl.pos]).filter((v) => v != null)
  const benchOvr = draft.bench.map((id) => byId[id]?.ovr).filter((v) => v != null)
  const avg = (list) => (list.length ? list.reduce((a, b) => a + b, 0) / list.length : 0)
  const xiStrength = avg(xi)
  const squadStrength = avg([...fieldIds.map((id) => byId[id]?.ovr).filter((v) => v != null), ...benchOvr])
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
        <>
          <div className="on-squad-bar">
            <label>
              Formação
              <select value={draft.formation} disabled={busy} onChange={(e) => changeFormation(e.target.value)}>
                {catalog.formations.map((f) => <option key={f.id} value={f.id}>{f.name}</option>)}
              </select>
            </label>
            <button type="button" className="gx-btn-ghost" disabled={busy} onClick={auto}><Wand2 size={15} /> Melhor time</button>
          </div>
          <div className="on-strength" aria-label="Força do time">
            <span className="is-main"><Gauge size={15} /><small>Força do time</small><b>{xiStrength ? xiStrength.toFixed(1).replace('.', ',') : '–'}</b></span>
            <span><small>Com reservas</small><b>{squadStrength ? squadStrength.toFixed(1).replace('.', ',') : '–'}</b></span>
            <span><small>Banco</small><b>{benchOvr.length ? avg(benchOvr).toFixed(1).replace('.', ',') : '–'}</b></span>
          </div>
          <div className="on-pitch-wrap">
            <Pitch
              formation={formation}
              slots={draft.slots}
              playersById={byId}
              colors={colors}
              selected={sel?.kind === 'slot' ? sel.key : null}
              onSlot={(s) => tap({ kind: 'slot', key: s.slot })}
            />
          </div>

          <h3 className="on-h">Banco <small>{draft.bench.length}/12</small></h3>
          <div className="on-cards">
            {draft.bench.map((id, i) => byId[id] && (
              <PlayerCard key={id} p={byId[id]} tag="Reserva" colors={colors} selected={sel?.kind === 'bench' && sel.key === i} onClick={() => tap({ kind: 'bench', key: i })} />
            ))}
          </div>
          {out.length > 0 && (
            <>
              <h3 className="on-h">Não relacionados</h3>
              <div className="on-cards">
                {out.map((p) => (
                  <PlayerCard key={p.id} p={byId[p.id]} colors={colors} selected={sel?.kind === 'out' && sel.key === p.id}
                    onClick={() => (sel?.kind === 'out' && sel.key === p.id ? (setSel(null), addToBench(p.id)) : tap({ kind: 'out', key: p.id }))} />
                ))}
              </div>
            </>
          )}
        </>
      )}

      {view === 'tactics' && (
        <div className="on-panel-dark">
          <TacticsPanel tactics={draft.tactics} onChange={(t) => setDraft({ ...draft, tactics: t })} />
        </div>
      )}

      {view === 'roles' && (
        <div className="on-roles">
          {ROLES.map(({ id, label, Icon }) => (
            <label key={id} className="on-role">
              <span><Icon size={16} /> {label}</span>
              <select value={squad.lineup.roles?.[id] || ''} onChange={(e) => setRole(id, e.target.value)}>
                <option value="">Automático</option>
                {fieldIds.map((pid) => byId[pid] && <option key={pid} value={pid}>{byId[pid].name} · {byId[pid].pos} {Math.round(byId[pid].ovr)}</option>)}
              </select>
            </label>
          ))}
        </div>
      )}

      {view === 'players' && (
        <div className="on-deals">
          <h3 className="on-h">Elenco <small>{squad.players.length}/28</small></h3>
          {squad.players.map((p) => (
            <PlayerDeal key={p.id} p={byId[p.id]} seasonId={seasonId} colors={colors} busy={busy} listed={listed.has(p.id)}
              onAuction={(pl, price) => {
                setBusy(true)
                createOnlineLot(pl.id, price).then((m) => { markListed(m); notify?.(`${pl.name} em leilão por 1 hora`, 'success') }).catch((e) => notify?.(e.message, 'alert')).finally(() => setBusy(false))
              }}
              onSell={(pl) => {
                setBusy(true)
                sellOnlinePlayer(pl.id).then((sq) => { load(sq); notify?.(`${pl.name} dispensado`, 'success') }).catch((e) => notify?.(e.message, 'alert')).finally(() => setBusy(false))
              }}
              onRenew={(pl, y) => {
                setBusy(true)
                renewOnlinePlayer(pl.id, y).then((sq) => { load(sq); notify?.(`${pl.name} renovou por mais ${y} temporada(s).`, 'success') }).catch((e) => notify?.(e.message, 'alert')).finally(() => setBusy(false))
              }}
            />
          ))}
        </div>
      )}

      {dirty && (
        <div className="on-savebar">
          <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => load(squad)}><RotateCcw size={15} /> Desfazer</button>
          <button type="button" className="gx-btn" disabled={busy} onClick={save}><Save size={15} /> {busy ? 'Salvando…' : 'Salvar escalação'}</button>
        </div>
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
