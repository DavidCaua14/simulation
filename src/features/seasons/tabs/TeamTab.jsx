import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Ambulance, ArrowLeftRight, CircleAlert, Ban, BatteryLow, Check, ChevronLeft, ChevronRight, ClipboardList, Flag, Save, Sparkles, TriangleAlert, Users } from 'lucide-react'
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
import { DEFAULT_TACTICS, LINE_NAME, LINES, POS_LINE, condTone, lineupStrength, ovrTone, POS_ORDER, posFit } from '../utils/managerUtils'
import { COMP_SHORT } from '../utils/seasonUtils'
import ClubDevPanel from '../../clubdev/ClubDevPanel'
import { fetchClubDev } from '../../clubdev/clubDevApi'

const VIEWS = [
  { id: 'lineup', label: 'Escalação' },
  { id: 'tactics', label: 'Táticas' },
  { id: 'squad', label: 'Elenco' },
  { id: 'club', label: 'Clube' },
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
// focusPlayerId: vindo de uma mensagem (ex.: atleta insatisfeito), abre o elenco já com a ficha dele.
export default function TeamTab({ hub, onSaved, notify, focusPlayerId = null, initialView = null, initialSection = null }) {
  const { catalog, error: catErr } = useCatalog()
  const [squad, setSquad] = useState(null)
  const [error, setError] = useState('')
  const [view, setView] = useState(focusPlayerId ? 'squad' : initialView || 'lineup')
  const [draft, setDraft] = useState(null) // { formation, slots, bench, tactics }
  const [dirty, setDirty] = useState(false)
  const [picker, setPicker] = useState(null)
  const [info, setInfo] = useState(focusPlayerId ? { id: focusPlayerId } : null)
  const [saving, setSaving] = useState(false)
  const [positionFilter, setPositionFilter] = useState('')
  const [issues, setIssues] = useState([])
  const [clubSection, setClubSection] = useState({ id: initialSection, n: 0 })
  const [familiarity, setFamiliarity] = useState(null) // entrosamento por formação (0–100), da gestão do clube

  const loadSequence = useRef(0)
  const dirtyDraft = useRef(false)
  const loadedClub = useRef(null)
  useEffect(() => { dirtyDraft.current = dirty }, [dirty])

  const clubId = hub.coach.club_id
  const club = getClubById(clubId)

  const load = useCallback(async (preserveDraft = false) => {
    const sequence = ++loadSequence.current
    try {
      const s = await fetchSquad()
      if (sequence !== loadSequence.current) return
      const keepDraft = preserveDraft === true && dirtyDraft.current && loadedClub.current === s.club_id
      setSquad(s)
      setDraft(previous => {
        if (keepDraft && previous) {
          const ids = new Set(s.players.map(p => p.id))
          return { ...previous, slots: Object.fromEntries(Object.entries(previous.slots).filter(([, id]) => ids.has(id))), bench: previous.bench.filter(id => ids.has(id)) }
        }
        return { formation: s.lineup.formation, slots: s.lineup.slots || {}, bench: s.lineup.bench || [], tactics: { ...DEFAULT_TACTICS, ...(s.lineup.tactics || {}) } }
      })
      if (!keepDraft) { setIssues(s.lineup.issues || []); setDirty(false) }
      loadedClub.current = s.club_id
      setError('')
    } catch (e) {
      if (sequence === loadSequence.current) setError(e.message)
    }
  }, [])

  const cancelLoad = useCallback(() => { loadSequence.current++ }, [])
  useEffect(() => {
    let alive = true
    fetchClubDev()
      .then((d) => alive && setFamiliarity(Object.fromEntries((d?.familiarity || []).map((f) => [f.formation, f.value]))))
      .catch(() => {})
    return () => {
      alive = false
    }
  }, [clubId, hub.world?.today])
  useEffect(() => {
    let cancelled = false
    queueMicrotask(() => { if (!cancelled && clubId) load(true) })
    return () => { cancelled = true; cancelLoad() }
  }, [clubId, hub.season.day_no, hub.world?.today, hub.world?.roster_revision, load, cancelLoad])

  const byId = useMemo(() => Object.fromEntries((squad?.players || []).map((p) => [p.id, p])), [squad])
  const infoPlayer = info ? byId[info.id] || (info.name ? info : null) : null
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
      else {
        // avisos de jogo (não impedem salvar): cansaço e posição improvisada
        if (p.condition != null && p.condition < 70) out.push({ level: 'warn', text: `${p.short_name} está cansado (${Math.round(p.condition)}% de condição).` })
        const fit = posFit(p, s.pos)
        if (fit < 0.86) out.push({ level: 'warn', text: `${p.short_name} está fora de posição como ${s.pos} (rende ${Math.round(fit * 100)}%).` })
        else if (fit < 1 && !(p.learned || []).includes(s.pos)) out.push({ level: 'warn', text: `${p.short_name} joga improvisado como ${s.pos}.` })
      }
    }
    return out
  }, [formation, draft, byId, squad])

  if (!clubId) return <EmptyState icon={Users} title="Sem clube" text="Você está sem clube. Aguarde propostas na aba Carreira." />
  if (error || catErr) return <ErrorState message={error || catErr} onRetry={load} />
  if (!squad || !draft || !catalog) return <LoadingState />

  const formIdx = Math.max(0, catalog.formations.findIndex((f) => f.id === draft.formation))
  const fam = familiarity && draft.formation in familiarity ? Math.round(familiarity[draft.formation]) : null
  // Funções (batedores de pênalti, falta e escanteio) ficam no treino da gestão do clube.
  const openRoles = () => {
    setClubSection((c) => ({ id: 'training', n: c.n + 1 }))
    setView('club')
  }

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

  const shownIssues = dirty ? localIssues : [...issues, ...localIssues.filter((i) => i.level === 'warn' && !issues.some((x) => x.text === i.text))]
  const errors = shownIssues.filter((i) => i.level === 'error')
  const warns = shownIssues.filter((i) => i.level === 'warn')
  // Mesma regra do banco, contada na lista exibida: atletas sem idade conhecida contam como adultos.
  const adults = squad.squad ? squad.players.filter((p) => (p.age ?? squad.squad.age) >= squad.squad.age).length : 0
  const groups = LINES.map((line) => ({ line, players: squad.players.filter((p) => POS_LINE[p.position] === line && (!positionFilter || p.position === positionFilter)).sort((a, b) => POS_ORDER.indexOf(a.position) - POS_ORDER.indexOf(b.position) || b.overall - a.overall) }))

  return (
    <div className="sn-page tt">
      <button type="button" className="sn-link" disabled={saving} onClick={() => load(true)}>Atualizar elenco</button>
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
          <span className={`tt-squad ${adults >= squad.squad.limit ? 'is-full' : ''}`} title={`${adults} dos ${squad.players.length} atletas têm ${squad.squad.age} anos ou mais. O limite para contratar é ${squad.squad.limit}; sub-${squad.squad.age} não contam.`}>
            <small>{squad.squad.age}+ (limite)</small>
            <b>{adults}/{squad.squad.limit}</b>
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

      {view === 'club' && <ClubDevPanel key={clubSection.n} initialSection={clubSection.id} players={squad.players} notify={notify} onChanged={() => load(true)} />}

      {view === 'lineup' && (
        <>
          <div className="tt-formstep" aria-label="Formação">
            <button type="button" aria-label="Formação anterior" onClick={() => changeFormation(catalog.formations[(formIdx - 1 + catalog.formations.length) % catalog.formations.length].id)}>
              <ChevronLeft size={20} />
            </button>
            <b>{formation?.name || draft.formation}</b>
            <button type="button" aria-label="Próxima formação" onClick={() => changeFormation(catalog.formations[(formIdx + 1) % catalog.formations.length].id)}>
              <ChevronRight size={20} />
            </button>
          </div>
          {fam != null && (
            <div className="tt-fam" title="Entrosamento do elenco com esta formação. Cada jogo nela aumenta; formações esquecidas perdem um pouco por mês.">
              <small>Treinamento</small>
              <i>
                <em className={fam >= 85 ? 'ok' : fam >= 65 ? 'mid' : 'low'} style={{ width: `${fam}%` }} />
              </i>
              <b>{fam}%</b>
            </div>
          )}

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

          <div className="tt-cmrow">
            <button type="button" className="gx-btn-ghost" onClick={() => setView('tactics')}>
              <ClipboardList size={16} /> Instruções
            </button>
            <button type="button" className="gx-btn-ghost" onClick={openRoles}>
              <Flag size={16} /> Funções
            </button>
            <button type="button" className="gx-btn-ghost" onClick={handleAuto} disabled={saving}>
              <Sparkles size={16} /> Seleção automática
            </button>
          </div>

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
              Reservas <small>{draft.bench.length}/{squad.rules.bench}</small>
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
                  <button type="button" className="tt-swap" aria-label={`Trocar ${byId[pid]?.short_name || 'reserva'}`} onClick={() => setPicker({ kind: 'bench', index: i, pos: byId[pid]?.position, current: pid })}>
                    <ArrowLeftRight size={13} />
                  </button>
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
                            {p.age != null ? ` · ${p.age} anos` : ''}
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

      {view === 'lineup' && (
        <div className={`tt-cmbar ${drag ? 'is-hidden' : ''}`}>
          <button type="button" className={`gx-btn tt-confirm ${dirty ? 'is-dirty' : ''}`} onClick={handleSave} disabled={saving || !dirty}>
            <Check size={18} /> {saving ? 'Salvando…' : dirty ? 'Confirmar' : 'Confirmado'}
          </button>
        </div>
      )}

      {view === 'tactics' && (
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
