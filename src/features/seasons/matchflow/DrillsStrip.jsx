import { useEffect, useState } from 'react'
import { Crosshair, Hand, Shield, Footprints, Share2 } from 'lucide-react'
import GameIcon from '../../../components/ui/GameIcon'
import { buyDrill, fetchDrills } from '../../clubdev/clubDevApi'
import { isSessionError } from '../../../lib/sessionRecovery'

const ICONS = { shooting: Crosshair, passing: Share2, penalty: Footprints, blocking: Hand, tackling: Shield }

// EXERCÍCIOS PRÉ-JOGO (CM17): Tiro, Passe, Pênalti, Bloqueio e Roubada. Cada um custa moedas e vale por alguns jogos.
export default function DrillsStrip({ notify, onCoins }) {
  const [data, setData] = useState(null)
  const [busy, setBusy] = useState(null)

  useEffect(() => {
    let alive = true
    fetchDrills()
      .then((d) => alive && setData(d))
      .catch((e) => alive && !isSessionError(e) && setData({ unavailable: true }))
    return () => {
      alive = false
    }
  }, [])

  if (!data?.drills) return null
  async function buy(kind) {
    setBusy(kind)
    try {
      const d = await buyDrill(kind)
      setData(d)
      onCoins?.()
      notify?.(kind === 'all' ? 'Todos os exercícios ativados.' : 'Exercício ativado.', 'ok')
    } catch (e) {
      notify?.(e.message, 'alert')
    } finally {
      setBusy(null)
    }
  }
  const allActive = data.drills.every((d) => d.games_left > 0)
  return (
    <section className="dr" aria-label="Exercícios pré-jogo">
      <button type="button" className="dr-all" disabled={Boolean(busy) || allActive || data.coins < data.all_price} onClick={() => buy('all')}>
        <span>Ativar todos os exercícios pré-jogo</span>
        <b>
          <GameIcon name="coins" size={14} /> {data.all_price}
        </b>
      </button>
      <div className="dr-list">
        {data.drills.map((d) => {
          const Icon = ICONS[d.kind] || Crosshair
          return (
            <button key={d.kind} type="button" className={`dr-item ${d.games_left > 0 ? 'is-on' : ''}`} title={d.description} disabled={Boolean(busy) || data.coins < d.price} onClick={() => buy(d.kind)}>
              <small>{d.label}</small>
              <Icon size={22} />
              {d.games_left > 0 ? <em>{d.games_left} jogo{d.games_left > 1 ? 's' : ''}</em> : null}
              <b>
                <GameIcon name="coins" size={12} /> {d.price}
              </b>
            </button>
          )
        })}
      </div>
    </section>
  )
}
