import { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Ambulance, Ban, ClipboardList, Crown, Radio, RotateCcw, Save, Shirt, Star, Target, Wand2 } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import Pitch from '../seasons/components/Pitch'
import TacticsPanel from '../seasons/components/TacticsPanel'
import useCatalog from '../seasons/hooks/useCatalog'
import { POS_NAME, condTone, posFit } from '../seasons/utils/managerUtils'
import { autoOnlineLineup, fetchOnlineSquad, saveOnlineLineup, saveOnlineRoles } from './services/onlineApi'
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
  const tier = cardTier(p.ovr, p.star)
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
export default function OnlineSquad({ onOpenMatch }) {
  const { catalog } = useCatalog()
  const [squad, setSquad] = useState(null)
  const [draft, setDraft] = useState(null) // {formation, slots, bench, tactics}
  const [view, setView] = useState('team')
  const [sel, setSel] = useState(null) // {kind:'slot'|'bench'|'out', key}
  const [confirm, setConfirm] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState('')

  const load = (sq) => {
    setSquad(sq)
    if (sq?.lineup) setDraft({ formation: sq.lineup.formation, slots: { ...sq.lineup.slots }, bench: [...sq.lineup.bench], tactics: sq.lineup.tactics || {} })
  }
  useEffect(() => {
    fetchOnlineSquad().then(load).catch((e) => setError(e.message))
  }, [])

  const byId = useMemo(() => Object.fromEntries((squad?.players || []).map((p) => [p.id, asSeasonPlayer(p, posFit)])), [squad])
  const colors = clubColors(squad?.club)
  const formation = catalog?.byId?.[draft?.formation]
  const dirty = squad?.lineup && draft && JSON.stringify({ f: draft.formation, s: draft.slots, b: draft.bench, t: draft.tactics }) !==
    JSON.stringify({ f: squad.lineup.formation, s: squad.lineup.slots, b: squad.lineup.bench, t: squad.lineup.tactics || {} })

  if (!squad || !catalog) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />
  if (!squad.lineup || !draft) return <Notice kind="info">Sua escalação aparece aqui depois da escolha dos craques.</Notice>

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
      text: 'Os mesmos 11 continuam em campo; cada um vai para a vaga onde rende mais. Confira antes de salvar.',
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
          setSaved('Escalação salva. Vale para o próximo jogo.')
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
      text: 'O jogo escolhe os melhores disponíveis para cada vaga desta formação. Suas trocas manuais serão substituídas.',
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
  return (
    <section className="on-squad">
      {squad.live_fixture && (
        <button type="button" className="on-live-banner" onClick={() => onOpenMatch?.(squad.live_fixture)}>
          <Radio size={16} /> Seu time está jogando agora. Mexer aqui não muda a partida: vale para o próximo jogo. <b>Ir para a partida</b>
        </button>
      )}
      <div className="on-seg on-seg-3" role="tablist" aria-label="Elenco">
        <button type="button" role="tab" aria-selected={view === 'team'} className={view === 'team' ? 'is-on' : ''} onClick={() => setView('team')}><Shirt size={15} /> Time</button>
        <button type="button" role="tab" aria-selected={view === 'tactics'} className={view === 'tactics' ? 'is-on' : ''} onClick={() => setView('tactics')}><ClipboardList size={15} /> Táticas</button>
        <button type="button" role="tab" aria-selected={view === 'roles'} className={view === 'roles' ? 'is-on' : ''} onClick={() => setView('roles')}><Crown size={15} /> Funções</button>
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
          <p className="on-hint">{sel ? 'Agora toque em quem vai trocar de lugar.' : 'Toque em um jogador e depois em outro para trocar de lugar.'}</p>
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

          <h3 className="gx-subtitle">Banco ({draft.bench.length}/12)</h3>
          <div className="on-cards">
            {draft.bench.map((id, i) => byId[id] && (
              <PlayerCard key={id} p={byId[id]} tag="Reserva" colors={colors} selected={sel?.kind === 'bench' && sel.key === i} onClick={() => tap({ kind: 'bench', key: i })} />
            ))}
          </div>
          {out.length > 0 && (
            <>
              <h3 className="gx-subtitle">Fora da partida</h3>
              <p className="on-hint">Quem não está entre os 23 não entra no jogo. Toque duas vezes para mandar ao banco.</p>
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
          <p className="on-hint">Valem a partir do próximo jogo. Sem escolha, o jogo usa quem chuta melhor.</p>
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
