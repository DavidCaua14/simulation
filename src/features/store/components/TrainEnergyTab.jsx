import { useCallback, useEffect, useState } from 'react'
import { Check, CircleAlert, Coins, Dumbbell, Zap } from 'lucide-react'
import { Skeleton } from '../../../components/ui/feedback'
import { useAudio } from '../../audio/AudioContext'
import { buyOnlineTrainEnergy, fetchOnlineClub } from '../../online/services/onlineApi'
import { fmt } from './storeUtils'

// Energia de treino do modo Online: cada compra libera um treino extra hoje (além dos 3 do dia), paga com moedas.
export default function TrainEnergyTab({ onChanged }) {
  const [club, setClub] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [bought, setBought] = useState(false)
  const { playSfx } = useAudio()
  const load = useCallback(() => fetchOnlineClub().then(setClub).catch((e) => setError(e.message)), [])
  useEffect(() => {
    load()
  }, [load])
  if (!club) return error ? <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p> : <Skeleton rows={2} />
  const t = club.train
  const left = t.max - t.used
  const full = t.extra >= t.extra_max
  const short = (club.coins?.wallet ?? 0) < t.extra_cost
  const buy = () => {
    setBusy(true)
    setError('')
    buyOnlineTrainEnergy()
      .then((c) => {
        setClub(c)
        setBought(true)
        playSfx('purchase')
        onChanged?.()
      })
      .catch((e) => setError(e.message))
      .finally(() => setBusy(false))
  }
  return (
    <section className="te">
      <article className="te-card">
        <span className="te-icon"><Dumbbell size={30} /><i><Zap size={14} /></i></span>
        <div className="te-info">
          <small>Modo Online</small>
          <strong>Energia de treino</strong>
          <span>+1 treino hoje</span>
        </div>
        <button type="button" className="gx-btn te-buy" disabled={busy || full || short} onClick={buy}>
          <Coins size={15} /> {fmt(t.extra_cost)}
        </button>
      </article>
      <dl className="sh-bill">
        <div><dt>Treinos disponíveis hoje</dt><dd><Zap size={14} /> {left} de {t.max}</dd></div>
        <div><dt>Extras comprados hoje</dt><dd>{t.extra} de {t.extra_max}</dd></div>
        <div><dt>Suas moedas</dt><dd><Coins size={14} /> {fmt(club.coins?.wallet ?? 0)}</dd></div>
      </dl>
      {bought && !error && <p className="sh-msg is-ok"><Check size={16} /> Treino extra liberado</p>}
      {short && !full && <p className="sh-msg is-error"><CircleAlert size={14} /> Moedas insuficientes</p>}
      {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
    </section>
  )
}
