import { useCallback, useEffect, useState } from 'react'
import { Check, CircleAlert, Coins, Dumbbell, Gem, Zap } from 'lucide-react'
import { Skeleton } from '../../../components/ui/feedback'
import { useAudio } from '../../audio/AudioContext'
import { buyOnlineTrainEnergy, fetchOnlineClub } from '../../online/services/onlineApi'
import { fmt } from './storeUtils'

// Energia de treino do modo Online: os 3 treinos do dia são grátis; cada treino além deles gasta 1 de energia.
// Aqui a energia é comprada em pacotes com diamantes ou uma a uma com moedas.
export default function TrainEnergyTab({ onChanged }) {
  const [club, setClub] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [bought, setBought] = useState(0)
  const { playSfx } = useAudio()
  const load = useCallback(() => fetchOnlineClub().then(setClub).catch((e) => setError(e.message)), [])
  useEffect(() => {
    load()
  }, [load])
  if (!club) return error ? <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p> : <Skeleton rows={3} />
  const t = club.train
  const diamonds = club.coins?.diamonds ?? 0
  const coins = club.coins?.wallet ?? 0
  const packs = Object.entries(t.packs || {}).sort((a, b) => a[1][0] - b[1][0])
  const buy = (pack, energy) => {
    setBusy(true)
    setError('')
    buyOnlineTrainEnergy(pack)
      .then((c) => {
        setClub(c)
        setBought(energy)
        playSfx('purchase')
        onChanged?.()
      })
      .catch((e) => setError(e.message))
      .finally(() => setBusy(false))
  }
  return (
    <section className="te">
      <header className="te-head">
        <span className="te-icon"><Dumbbell size={28} /><i><Zap size={14} /></i></span>
        <div className="te-info">
          <small>Modo Online</small>
          <strong>Energia de treino</strong>
          <span><Zap size={12} /> {fmt(t.energy)} em estoque · {t.free_left} de {t.max} grátis hoje</span>
        </div>
      </header>
      <div className="te-packs">
        {packs.map(([id, [energy, price]], i) => (
          <button key={id} type="button" className={`te-pack ${i === packs.length - 1 ? 'is-best' : ''}`} disabled={busy || diamonds < price} onClick={() => buy(id, energy)}>
            <b><Zap size={16} /> {energy}</b>
            <small>treinos extras</small>
            <em><Gem size={13} /> {price}</em>
          </button>
        ))}
        <button type="button" className="te-pack is-coin" disabled={busy || coins < t.coin_cost} onClick={() => buy('coin', 1)}>
          <b><Zap size={16} /> 1</b>
          <small>treino extra</small>
          <em><Coins size={13} /> {t.coin_cost}</em>
        </button>
      </div>
      <dl className="sh-bill">
        <div><dt>Seus diamantes</dt><dd><Gem size={14} /> {fmt(diamonds)}</dd></div>
        <div><dt>Suas moedas</dt><dd><Coins size={14} /> {fmt(coins)}</dd></div>
      </dl>
      {bought > 0 && !error && <p className="sh-msg is-ok"><Check size={16} /> +{bought} de energia de treino</p>}
      {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
    </section>
  )
}
