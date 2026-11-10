import { useEffect, useMemo, useState } from 'react'
import { Star, Wand2 } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import { autoOnlineLineup, fetchFormations, fetchOnlineSquad, saveOnlineLineup } from './services/onlineApi'
import { money } from './onlineUtils'

// Elenco e escalação. Para trocar dois jogadores de lugar (titular, banco ou fora), toque em um e depois no outro.
export default function OnlineSquad() {
  const [squad, setSquad] = useState(null)
  const [formations, setFormations] = useState([])
  const [selected, setSelected] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    fetchOnlineSquad().then(setSquad).catch((e) => setError(e.message))
    fetchFormations().then(setFormations).catch(() => {})
  }, [])

  const lineup = squad?.lineup
  const byId = useMemo(() => new Map((squad?.players || []).map((p) => [p.id, p])), [squad])
  const formation = formations.find((f) => f.id === lineup?.formation)
  const slotOrder = formation ? formation.slots.map((s) => s.slot) : Object.keys(lineup?.slots || {})
  const slotPos = (slot) => formation?.slots.find((s) => s.slot === slot)?.pos || slot.replace(/\d+$/, '')
  const starters = slotOrder.map((slot) => ({ slot, player: byId.get(lineup?.slots?.[slot]) })).filter((x) => x.player)
  const bench = (lineup?.bench || []).map((id) => byId.get(id)).filter(Boolean)
  const placed = new Set([...starters.map((x) => x.player.id), ...bench.map((p) => p.id)])
  const out = (squad?.players || []).filter((p) => !placed.has(p.id))

  const run = (job) => {
    setBusy(true)
    setError('')
    job.then(setSquad).catch((e) => setError(e.message)).finally(() => {
      setBusy(false)
      setSelected(null)
    })
  }

  // Troca os lugares de dois jogadores e salva.
  const swap = (a, b) => {
    const slots = { ...lineup.slots }
    let nextBench = [...lineup.bench]
    const place = (id) => {
      const slot = Object.keys(slots).find((k) => slots[k] === id)
      if (slot) return { slot }
      const i = nextBench.indexOf(id)
      return i >= 0 ? { bench: i } : {}
    }
    const pa = place(a)
    const pb = place(b)
    const put = (where, id) => {
      if (where.slot) slots[where.slot] = id
      else if (where.bench != null) nextBench[where.bench] = id
    }
    put(pa, b)
    put(pb, a)
    nextBench = nextBench.filter((id, i) => nextBench.indexOf(id) === i && !Object.values(slots).includes(id))
    run(saveOnlineLineup({ formation: lineup.formation, slots, bench: nextBench }))
  }

  const tap = (id) => {
    if (busy) return
    if (!selected) return setSelected(id)
    if (selected === id) return setSelected(null)
    return swap(selected, id)
  }

  if (!squad) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={8} />
  if (!lineup) return <Notice kind="info">Sua escalação aparece aqui depois da escolha dos craques.</Notice>

  const Row = ({ p, tag }) => (
    <li>
      <button type="button" className={`on-player ${selected === p.id ? 'is-selected' : ''}`} onClick={() => tap(p.id)} aria-pressed={selected === p.id}>
        <span className="on-player-tag">{tag}</span>
        <span className="on-player-who">
          <strong>{p.star && <Star size={12} aria-label="Craque" />}{p.name}</strong>
          <small>{p.pos} · {p.age} anos · {money(p.value)}{p.injured ? ' · lesionado' : ''}</small>
        </span>
        <span className="on-player-cond" title="Condição física">{p.cond}%</span>
        <b className="on-player-ovr">{Math.round(p.ovr)}</b>
      </button>
    </li>
  )

  return (
    <section className="on-squad">
      <div className="on-squad-bar">
        <label>
          Formação
          <select value={lineup.formation} disabled={busy} onChange={(e) => run(autoOnlineLineup(e.target.value))}>
            {(formations.length ? formations : [{ id: lineup.formation, name: lineup.formation }]).map((f) => (
              <option key={f.id} value={f.id}>{f.name}</option>
            ))}
          </select>
        </label>
        <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => run(autoOnlineLineup())}>
          <Wand2 size={15} /> Melhor time
        </button>
      </div>
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}
      <p className="on-hint">{selected ? 'Toque em outro jogador para trocar de lugar.' : 'Toque em um jogador e depois em outro para trocar de lugar.'}</p>

      <h3 className="gx-subtitle">Titulares</h3>
      <ul className="on-list">{starters.map(({ slot, player }) => <Row key={player.id} p={player} tag={slotPos(slot)} />)}</ul>
      <h3 className="gx-subtitle">Banco</h3>
      <ul className="on-list">{bench.map((p) => <Row key={p.id} p={p} tag="RES" />)}</ul>
      {out.length > 0 && (
        <>
          <h3 className="gx-subtitle">Fora da partida</h3>
          <ul className="on-list">{out.map((p) => <Row key={p.id} p={p} tag="—" />)}</ul>
        </>
      )}
    </section>
  )
}
