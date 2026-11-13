import { useEffect, useMemo, useState } from 'react'
import { RefreshCw, Shirt, X } from 'lucide-react'
import { Notice, Skeleton } from '../../../components/ui/feedback'
import Pitch from '../../seasons/components/Pitch'
import useCatalog from '../../seasons/hooks/useCatalog'
import { posFit } from '../../seasons/utils/managerUtils'
import OnlineCrest from './OnlineCrest'
import { fetchOnlineFixtureLineups } from '../services/onlineApi'
import { asSeasonPlayer, clubColors } from '../onlineUtils'

// ESCALAÇÕES do jogo: o seu time e o adversário no campo, com a formação de cada um, em cartas.
// No vestiário mostra a escalação salva; com a bola rolando mostra quem está em campo agora (a tela se atualiza
// sozinha, então substituições do adversário aparecem). LineupsView é o conteúdo (também usado na aba Times da
// partida); LineupsSheet é a janela.
export function LineupsView({ fixtureId, live = false, onLive }) {
  const { catalog } = useCatalog()
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [side, setSide] = useState(null)

  useEffect(() => {
    let alive = true
    const load = () => fetchOnlineFixtureLineups(fixtureId)
      .then((d) => { if (alive) { setData(d); setError('') } })
      .catch((e) => alive && setError(e.message))
    load()
    const id = setInterval(load, live ? 15000 : 30000)
    return () => { alive = false; clearInterval(id) }
  }, [fixtureId, live])

  const mySide = data?.my_side === 'a' ? 'away' : 'home'
  const shown = side || mySide
  const team = data?.[shown]
  const byId = useMemo(() => Object.fromEntries((team?.players || []).map((p) => [p.id, asSeasonPlayer({ sec: [], ...p }, posFit)])), [team])
  const slots = useMemo(() => Object.fromEntries((team?.players || []).map((p) => [p.slot, p.id])), [team])
  const formation = catalog?.byId?.[team?.formation]
  const strength = team?.players?.length ? team.players.reduce((a, p) => a + Number(p.ovr), 0) / team.players.length : 0
  const label = (key) => (data?.my_side && key === mySide ? 'Meu time' : data?.my_side ? 'Adversário' : data?.[key]?.club.short)
  useEffect(() => { onLive?.(Boolean(team?.live)) }, [team?.live, onLive])

  if (error && !data) return <Notice kind="error">{error}</Notice>
  if (!data || !catalog) return <Skeleton rows={6} />
  return (
    <div className="on-lus-view">
      <div className="on-seg" role="tablist" aria-label="Time">
        {['home', 'away'].map((key) => (
          <button key={key} type="button" role="tab" aria-selected={shown === key} className={shown === key ? 'is-on' : ''} onClick={() => setSide(key)}>
            <OnlineCrest club={data[key].club} size={18} /> {label(key)}
          </button>
        ))}
      </div>
      <div className="on-lus-info">
        <span><small>Clube</small><b>{team.club.name}</b></span>
        <span><small>Formação</small><b>{team.formation}</b></span>
        <span><small>Força</small><b>{strength ? strength.toFixed(1).replace('.', ',') : '–'}</b></span>
      </div>
      <div className="on-pitch-wrap">
        <Pitch formation={formation} slots={slots} playersById={byId} colors={clubColors(team.club)} live={team.live} />
      </div>
    </div>
  )
}

export default function LineupsSheet({ fixtureId, live = false, onClose }) {
  const [isLive, setIsLive] = useState(false)
  return (
    <div className="on-modal on-lus" role="dialog" aria-modal="true" aria-label="Escalações">
      <div className="on-lus-card gx-panel">
        <header className="on-lus-head">
          <h3><Shirt size={18} /> Escalações</h3>
          {isLive && <span className="on-lus-live"><RefreshCw size={12} /> ao vivo</span>}
          <button type="button" className="on-result-x" onClick={onClose} aria-label="Fechar"><X size={16} /></button>
        </header>
        <LineupsView fixtureId={fixtureId} live={live} onLive={setIsLive} />
      </div>
    </div>
  )
}
