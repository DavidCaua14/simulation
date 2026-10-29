import { useCallback, useEffect, useMemo, useState } from 'react'
import { Ambulance, CircleAlert, Ban, BatteryLow, Check, Save, Sparkles, TriangleAlert, Users } from 'lucide-react'
import Pitch, { PlayerToken } from '../components/Pitch'
import BasePlayerCard from '../../cards/components/BasePlayerCard'
import PositionFilter from '../components/PositionFilter'
import PlayerPicker from '../components/PlayerPicker'
import PlayerSheet from '../components/PlayerSheet'
import TacticsPanel from '../components/TacticsPanel'
import MoodBadge from '../components/MoodBadge'
import { MOODS } from '../utils/mood'
import ContractPanel from '../components/ContractPanel'
import { dateLabel } from '../services/careerWorldApi'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { EmptyState, ErrorState, LoadingState } from '../ui/States'
import useCatalog from '../hooks/useCatalog'
import useDragSwap from '../hooks/useDragSwap'
import { autoLineup, fetchSquad, saveLineup } from '../services/managerApi'
import { DEFAULT_TACTICS, LINE_NAME, LINES, POS_LINE, condTone, lineupStrength, ovrTone, POS_ORDER } from '../utils/managerUtils'
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
  const [positionFilter, setPositionFilter] = useState('')
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
  const infoPlayer = info ? byId[info.id] || info : null
  const expiringSoon = (until) => hub.world?.today && Date.parse(until) - Date.parse(hub.world.today) <= 183 * 86400000
  const formation = catalog?.byId[draft?.formation]
  const strength = useMemo(() => (formation && draft ? lineupStrength(formation, draft.slots, byId) : null), [formation, draft, byId])

  // ARRASTAR E SOLTAR: troca titular↔titular, titular↔reserva e reserva↔reserva
  const onDrop = useCallback(
    (from, to) => {
      setDraft((d) => {
        if (!d) return d
        const slots = { ...d.slots }
        const bench = [...d.bench]
        const read = (k) => (k.startsWith('slot:') ? slots[k.slice(5)] : k === 'bench:new' ? null : bench[Number(k.slice(6))])
        const write = (k, pid) => {
          if (k.startsWith('slot:')) {
            if (pid) slots[k.slice(5)] = pid
            else delete slots[k.slice(5)]
          } else if (k === 'bench:new') {
            if (pid) bench.push(pid)
          } else {
            const i = Number(k.slice(6))
            if (pid) bench[i] = pid
            else bench.splice(i, 1)
          }
        }
        const a = read(from)
        const b = read(to)
        if (!a) return d
        if (to === 'bench:new' && from.startsWith('bench:')) return d
        // reserva indo para o banco "novo" a partir do campo: precisa caber
        if (to === 'bench:new' && bench.length >= (squad?.rules?.bench ?? 12)) return d
        // ordem importa quando os dois estão no banco (índices)
        if (from.startsWith('bench:') && to.startsWith('bench:')) {
          write(to, a)
          write(from, b)
        } else {
          write(from, b)
          write(to, a)
        }
        return { ...d, slots, bench: bench.filter(Boolean) }
      })
      setDirty(true)
    },
    [squad],
  )
  const { drag, bind, ghost } = useDragSwap({ onDrop, getPlayer: (pid) => byId[pid] })

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
  const groups = LINES.map((line) => ({ line, players: squad.players.filter((p) => POS_LINE[p.position] === line && (!positionFilter || p.position === positionFilter)).sort((a, b) => POS_ORDER.indexOf(a.position) - POS_ORDER.indexOf(b.position) || b.overall - a.overall) }))

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
        {squad.squad && (
          <span className={`tt-squad ${squad.squad.count >= squad.squad.limit ? 'is-full' : ''}`} title={`Limite de inscrição: ${squad.squad.limit} atletas com ${squad.squad.age} anos ou mais. Sub-${squad.squad.age} não contam.`}>
            <small>Elenco {squad.squad.age}+</small>
            <b>{squad.squad.count}/{squad.squad.limit}</b>
          </span>
        )}
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

      {(view === 'lineup' || view === 'squad') && <PositionFilter value={positionFilter} onChange={setPositionFilter} />}

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
            bind={bind}
            drag={drag}
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
            <div className={`tt-bench ${drag ? 'is-dragging' : ''}`}>
              {draft.bench.map((pid, i) => (!positionFilter || byId[pid]?.position === positionFilter) && (
                <div key={pid} className={`tt-bslot ${drag?.over === `bench:${i}` ? 'is-drop' : ''} ${drag?.from === `bench:${i}` ? 'is-dragging' : ''}`} {...bind(`bench:${i}`, pid)}>
                  <PlayerToken
                    player={byId[pid]}
                    pos={byId[pid]?.position}
                    label={byId[pid]?.position}
                    colors={club?.colors}
                    onClick={() => setPicker({ kind: 'bench', index: i, pos: byId[pid]?.position, current: pid })}
                  />
                </div>
              ))}
              {draft.bench.length < squad.rules.bench && (
                <div className={`tt-bslot ${drag?.over === 'bench:new' ? 'is-drop' : ''}`} {...bind('bench:new', null)}>
                  <PlayerToken player={null} label="Reserva" onClick={() => setPicker({ kind: 'bench', index: null, pos: null, current: null })} />
                </div>
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
          {squad.players.some((p) => p.morale != null) && (
            <ul className="tt-moods" aria-label="Legenda de satisfação">
              {MOODS.map((m) => (
                <li key={m.id}>
                  <MoodBadge morale={m.at < 0 ? 0 : m.at} size={13} /> {m.label}
                </li>
              ))}
            </ul>
          )}
          <p className="sn-hint">
            Arraste um jogador até outra vaga ou até o banco para trocar de lugar — ou toque nele para escolher da lista. A etiqueta abaixo do nome é a posição: no campo, a da vaga ("é MC" mostra a posição de origem de quem está improvisado); no banco, a posição de cada reserva. Fora de posição ele rende menos; cansado também. Mudar a formação toda hora reduz o entrosamento
            tático ({squad.lineup.formation_games} jogo{squad.lineup.formation_games === 1 ? '' : 's'} seguidos nesta formação).
          </p>
        </>
      )}

      {view === 'tactics' && (
        <>
          <TacticsPanel engineVersion={hub.simulation_version ?? 1} tactics={draft.tactics} onChange={(tactics) => update({ tactics })} />
          <p className="sn-hint">As táticas valem a partir do próximo jogo. Durante a partida você ainda pode ajustá-las.</p>
        </>
      )}

      {view === 'squad' && (
        <div className="sq">
          {groups.filter((g) => g.players.length > 0).map((g) => (
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
                        <BasePlayerCard player={{ ...p, club_id: clubId }} width={112} />
                        <span className="sq-name">
                          <b>{p.short_name}</b>
                          <small>
                            {p.position}
                            {p.position_estimated ? '*' : ''}
                            {inXI ? ' · titular' : onBench ? ' · banco' : ''}
                          </small>
                          {(p.transfer_requested || p.transfer_listed || p.precontract || p.contract_expires) && (
                            <span className="sq-tags">
                              {p.transfer_requested && <em className="sq-tag bad">Pede para sair</em>}
                              {p.precontract && <em className="sq-tag bad">Pré-contrato</em>}
                              {p.transfer_listed && <em className="sq-tag warn">À venda</em>}
                              {p.contract_expires && <em className={`sq-tag ${expiringSoon(p.contract_expires) ? 'warn' : ''}`}>Até {dateLabel(p.contract_expires).slice(3)}</em>}
                            </span>
                          )}
                        </span>
                        <MoodBadge morale={p.morale} size={16} />
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
        <div className={`tt-actions ${drag ? "is-hidden" : ""}`}>
          <button type="button" className="gx-btn-ghost" onClick={handleAuto} disabled={saving}>
            <Sparkles size={16} /> Auxiliar escala
          </button>
          <button type="button" className={`gx-btn tt-save ${dirty ? 'is-dirty' : ''}`} onClick={handleSave} disabled={saving || !dirty}>
            <Save size={17} /> {saving ? 'Salvando…' : dirty ? 'Salvar' : 'Salvo'}
          </button>
        </div>
      )}

      {drag && ghost && (
        <div className="tt-ghost" style={{ left: drag.x, top: drag.y }} aria-hidden="true">
          <PlayerToken player={ghost} pos={drag.over?.startsWith('slot:') ? formation?.slots.find((x) => `slot:${x.slot}` === drag.over)?.pos || ghost.position : ghost.position} colors={club?.colors} />
        </div>
      )}

      {picker && (
        <PlayerPicker
          target={picker}
          players={squad.players.map((p) => ({ ...p, club_id: clubId }))}
          slots={draft.slots}
          bench={draft.bench}
          onPick={pick}
          onRemove={picker.current ? removeFromTarget : null}
          onInfo={setInfo}
          onClose={() => setPicker(null)}
        />
      )}
      {infoPlayer && (
        <PlayerSheet player={{ ...infoPlayer, club_id: clubId }} clubName={club?.name} onClose={() => setInfo(null)}>
          {(infoPlayer.contract_expires || infoPlayer.morale != null) && (
            <ContractPanel
              key={infoPlayer.id}
              player={infoPlayer}
              today={hub.world?.today}
              notify={notify}
              onChanged={(r) => {
                load()
                onSaved?.()
                if (r?.closed) setInfo(null)
              }}
            />
          )}
        </PlayerSheet>
      )}
    </div>
  )
}
