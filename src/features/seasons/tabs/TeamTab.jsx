import { useCallback, useEffect, useMemo, useState } from 'react'
import { Ambulance, CircleAlert, Ban, BatteryLow, Check, Save, Sparkles, TriangleAlert, Users } from 'lucide-react'
import Pitch, { PlayerToken } from '../components/Pitch'
import PlayerPicker from '../components/PlayerPicker'
import PlayerSheet from '../components/PlayerSheet'
import TacticsPanel from '../components/TacticsPanel'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { EmptyState, ErrorState, LoadingState } from '../ui/States'
import useCatalog from '../hooks/useCatalog'
import { autoLineup, fetchSquad, saveLineup } from '../services/managerApi'
import { DEFAULT_TACTICS, LINE_NAME, LINES, POS_LINE, condTone, lineupStrength, ovrTone } from '../utils/managerUtils'
import { COMP_SHORT } from '../utils/seasonUtils'

const VIEWS = [
  { id: 'lineup', label: 'Escalação' },
  { id: 'tactics', label: 'Táticas' },
  { id: 'squad', label: 'Elenco' },
]

const SCARCITY = { GOL: 1, ZAG: 2, LD: 3, LE: 3, VOL: 4, ATA: 5, MC: 6, MEI: 7, PD: 8, PE: 8 }

// Ao trocar a formação, os 11 continuam: cada um vai para a vaga em que rende mais (preserva a escalação)
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

// TIME: escalação no campo (protagonista), táticas e elenco completo.
export default function TeamTab({ hub, onSaved, notify }) {
  const { catalog, error: catErr } = useCatalog()
  const [squad, setSquad] = useState(null)
  const [error, setError] = useState('')
  const [view, setView] = useState('lineup')
  const [draft, setDraft] = useState(null) // { formation, slots, bench, tactics }
  const [dirty, setDirty] = useState(false)
  const [picker, setPicker] = useState(null)
  const [info, setInfo] = useState(null)
  const [saving, setSaving] = useState(false)
  const [issues, setIssues] = useState([])

  const clubId = hub.coach.club_id
  const club = getClubById(clubId)

  const load = useCallback(async () => {
    try {
      const s = await fetchSquad()
      setSquad(s)
      setDraft({ formation: s.lineup.formation, slots: s.lineup.slots || {}, bench: s.lineup.bench || [], tactics: { ...DEFAULT_TACTICS, ...(s.lineup.tactics || {}) } })
      setIssues(s.lineup.issues || [])
      setDirty(false)
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])

  useEffect(() => {
    if (clubId) load()
  }, [clubId, hub.season.day_no, load])

  const byId = useMemo(() => Object.fromEntries((squad?.players || []).map((p) => [p.id, p])), [squad])
  const formation = catalog?.byId[draft?.formation]
  const strength = useMemo(() => (formation && draft ? lineupStrength(formation, draft.slots, byId) : null), [formation, draft, byId])

  // problemas calculados na hora (antes de salvar)
  const localIssues = useMemo(() => {
    if (!formation || !draft) return []
    const out = []
    for (const s of formation.slots) {
      const p = byId[draft.slots[s.slot]]
      if (!p) out.push({ level: 'error', text: `Vaga ${s.slot} sem jogador.` })
      else if (p.injured_days > 0) out.push({ level: 'error', text: `${p.short_name} está lesionado.` })
      else if (p.suspended > 0 && (!squad.next_competition || (p.susp?.[squad.next_competition] ?? 0) > 0)) out.push({ level: 'error', text: `${p.short_name} está suspenso.` })
    }
    return out
  }, [formation, draft, byId, squad])

  if (!clubId) return <EmptyState icon={Users} title="Sem clube" text="Você está sem clube. Aguarde propostas na aba Carreira." />
  if (error || catErr) return <ErrorState message={error || catErr} onRetry={load} />
  if (!squad || !draft || !catalog) return <LoadingState />

  const update = (patch) => {
    setDraft((d) => ({ ...d, ...patch }))
    setDirty(true)
  }

  function changeFormation(id) {
    if (id === draft.formation) return
    update({ formation: id, slots: remap(draft.slots, catalog.byId[id], byId) })
  }

  function pick(pid) {
    const t = picker
    const slots = { ...draft.slots }
    let bench = [...draft.bench]
    if (t.kind === 'slot') {
      const prev = slots[t.slot]
      const fromSlot = Object.keys(slots).find((k) => slots[k] === pid)
      if (fromSlot) {
        if (prev) slots[fromSlot] = prev
        else delete slots[fromSlot]
      } else if (bench.includes(pid)) {
        bench = prev ? bench.map((b) => (b === pid ? prev : b)) : bench.filter((b) => b !== pid)
      }
      slots[t.slot] = pid
    } else {
      if (t.index != null && bench[t.index]) bench[t.index] = pid
      else if (!bench.includes(pid)) bench.push(pid)
    }
    update({ slots, bench: [...new Set(bench)].slice(0, squad.rules.bench) })
    setPicker(null)
  }

  function removeFromTarget() {
    const t = picker
    if (t.kind === 'slot') {
      const slots = { ...draft.slots }
      delete slots[t.slot]
      update({ slots })
    } else {
      update({ bench: draft.bench.filter((_, i) => i !== t.index) })
    }
    setPicker(null)
  }

  async function handleSave() {
    setSaving(true)
    try {
      const r = await saveLineup(draft)
      setIssues(r.issues || [])
      setDirty(false)
      notify?.('Escalação salva!', 'ok')
      onSaved?.()
      load()
    } catch (e) {
      notify?.(e.message, 'alert')
    } finally {
      setSaving(false)
    }
  }

  async function handleAuto() {
    setSaving(true)
    try {
      const s = await autoLineup(draft.formation)
      setSquad(s)
      setDraft((d) => ({ ...d, slots: s.lineup.slots, bench: s.lineup.bench }))
      setIssues(s.lineup.issues || [])
      setDirty(false)
      notify?.('Auxiliar escalou o melhor time disponível.', 'ok')
      onSaved?.()
    } catch (e) {
      notify?.(e.message, 'alert')
    } finally {
      setSaving(false)
    }
  }

  const shownIssues = dirty ? localIssues : issues
  const errors = shownIssues.filter((i) => i.level === 'error')
  const warns = shownIssues.filter((i) => i.level === 'warn')
  const groups = LINES.map((line) => ({ line, players: squad.players.filter((p) => POS_LINE[p.position] === line) }))

  return (
    <div className="sn-page tt">
      <div className="tt-club">
        <ClubCrest clubId={clubId} size={34} />
        <div>
          <b>{club?.name}</b>
          <small>
            {squad.players.length} atletas
            {squad.next_competition ? ` · próximo jogo: ${COMP_SHORT[squad.next_competition]}` : ''}
          </small>
        </div>
        {strength && (
          <span className={`tt-ovr o-${ovrTone(strength.overall)}`} title="Força média do time titular nas vagas escolhidas">
            <small>Força</small>
            <b>{strength.overall}</b>
          </span>
        )}
      </div>

      <div className="sn-seg" role="tablist" aria-label="Gestão do time">
        {VIEWS.map((v) => (
          <button key={v.id} type="button" role="tab" aria-selected={view === v.id} className={view === v.id ? 'is-on' : ''} onClick={() => setView(v.id)}>
            {v.label}
          </button>
        ))}
      </div>

      {view === 'lineup' && (
        <>
          <div className="tt-forms" role="radiogroup" aria-label="Formação">
            {catalog.formations.map((f) => (
              <button key={f.id} type="button" role="radio" aria-checked={draft.formation === f.id} className={draft.formation === f.id ? 'is-on' : ''} onClick={() => changeFormation(f.id)}>
                {f.name}
              </button>
            ))}
          </div>

          <Pitch
            formation={formation}
            slots={draft.slots}
            playersById={byId}
            colors={club?.colors}
            selected={picker?.kind === 'slot' ? picker.slot : null}
            onSlot={(s) => setPicker({ kind: 'slot', slot: s.slot, pos: s.pos, current: draft.slots[s.slot] })}
          />

          {strength && (
            <div className="tt-lines" aria-label="Força por setor">
              {[
                ['Ataque', strength.att],
                ['Meio', strength.mid],
                ['Defesa', strength.def],
                ['Goleiro', strength.gk],
              ].map(([label, v]) => (
                <span key={label}>
                  <small>{label}</small>
                  <i className={`o-${ovrTone(v)}`}>
                    <em style={{ width: `${Math.max(0, Math.min(100, ((v - 40) / 50) * 100))}%` }} />
                  </i>
                  <b>{v}</b>
                </span>
              ))}
            </div>
          )}

          <section className="sn-sec">
            <h2 className="gx-title">
              Banco <small>{draft.bench.length}/{squad.rules.bench} reservas</small>
            </h2>
            <div className="tt-bench">
              {draft.bench.map((pid, i) => (
                <PlayerToken
                  key={pid}
                  player={byId[pid]}
                  pos={byId[pid]?.position}
                  label={byId[pid]?.position}
                  colors={club?.colors}
                  onClick={() => setPicker({ kind: 'bench', index: i, pos: byId[pid]?.position, current: pid })}
                />
              ))}
              {draft.bench.length < squad.rules.bench && (
                <PlayerToken player={null} label="Reserva" onClick={() => setPicker({ kind: 'bench', index: null, pos: null, current: null })} />
              )}
            </div>
          </section>

          {(errors.length > 0 || warns.length > 0) && (
            <ul className="tt-issues">
              {errors.map((i, k) => (
                <li key={`e${k}`} className="err">
                  <CircleAlert size={14} /> {i.text}
                </li>
              ))}
              {warns.map((i, k) => (
                <li key={`w${k}`} className="warn">
                  <TriangleAlert size={14} /> {i.text}
                </li>
              ))}
            </ul>
          )}
          {errors.length === 0 && !dirty && (
            <p className="tt-ready">
              <Check size={14} /> Escalação pronta para o próximo jogo
            </p>
          )}
          <p className="sn-hint">
            Toque numa vaga para trocar o jogador. Fora de posição ele rende menos; cansado também. Mudar a formação toda hora reduz o entrosamento
            tático ({squad.lineup.formation_games} jogo{squad.lineup.formation_games === 1 ? '' : 's'} seguidos nesta formação).
          </p>
        </>
      )}

      {view === 'tactics' && (
        <>
          <TacticsPanel tactics={draft.tactics} onChange={(tactics) => update({ tactics })} />
          <p className="sn-hint">As táticas valem a partir do próximo jogo. Durante a partida você ainda pode ajustá-las.</p>
        </>
      )}

      {view === 'squad' && (
        <div className="sq">
          {groups.map((g) => (
            <section key={g.line} className="sq-group">
              <h3 className="gx-title">
                {LINE_NAME[g.line]} <small>{g.players.length}</small>
              </h3>
              <ul>
                {g.players.map((p) => {
                  const inXI = Object.values(draft.slots).includes(p.id)
                  const onBench = draft.bench.includes(p.id)
                  return (
                    <li key={p.id}>
                      <button type="button" className={`sq-row ${p.available ? '' : 'is-out'}`} onClick={() => setInfo(p)}>
                        <span className="sq-num">{p.number ?? '–'}</span>
                        <span className="sq-name">
                          <b>{p.short_name}</b>
                          <small>
                            {p.position}
                            {p.position_estimated ? '*' : ''}
                            {inXI ? ' · titular' : onBench ? ' · banco' : ''}
                          </small>
                        </span>
                        <span className="sq-flags">
                          {p.injured_days > 0 && <Ambulance size={13} className="bad" />}
                          {p.suspended > 0 && <Ban size={13} className="bad" />}
                          {p.condition < 70 && !p.injured_days && <BatteryLow size={13} className="warn" />}
                        </span>
                        <span className={`sq-cond ${condTone(p.condition)}`} title={`Condição ${p.condition}%`}>
                          <i style={{ width: `${p.condition}%` }} />
                        </span>
                        <span className="sq-st">
                          {p.stats?.apps || 0}J {p.stats?.goals || 0}G
                        </span>
                        <span className={`sq-ovr o-${ovrTone(p.overall)}`}>{p.overall}</span>
                      </button>
                    </li>
                  )
                })}
              </ul>
            </section>
          ))}
          <p className="sn-hint">* posição detalhada estimada (a fonte do elenco só informava o setor). Atributos são estimativas de gameplay.</p>
        </div>
      )}

      {(view === 'lineup' || view === 'tactics') && (
        <div className="tt-actions">
          <button type="button" className="gx-btn-ghost" onClick={handleAuto} disabled={saving}>
            <Sparkles size={16} /> Auxiliar escala
          </button>
          <button type="button" className={`gx-btn tt-save ${dirty ? 'is-dirty' : ''}`} onClick={handleSave} disabled={saving || !dirty}>
            <Save size={17} /> {saving ? 'Salvando…' : dirty ? 'Salvar' : 'Salvo'}
          </button>
        </div>
      )}

      {picker && (
        <PlayerPicker
          target={picker}
          players={squad.players}
          slots={draft.slots}
          bench={draft.bench}
          onPick={pick}
          onRemove={picker.current ? removeFromTarget : null}
          onInfo={setInfo}
          onClose={() => setPicker(null)}
        />
      )}
      {info && <PlayerSheet player={info} clubName={club?.name} onClose={() => setInfo(null)} />}
    </div>
  )
}
