import GameIcon from '../../../components/ui/GameIcon'
import { useCallback, useEffect, useRef, useState } from 'react'
import { BatteryLow, Check, CircleAlert, X } from 'lucide-react'
import { buyEnergy, fetchEnergy, newRequestId } from '../services/storeApi'
import { fmt } from './storeUtils'
import { useAudio } from '../../audio/AudioContext'
import { Skeleton } from '../../../components/ui/feedback'

const hhmm = (iso) => new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })

function ConfirmPack({ pack, data, onClose, onDone }) {
  const requestId = useRef(newRequestId()).current
  const [busy, setBusy] = useState(false)
  const { playSfx } = useAudio()
  const [error, setError] = useState('')
  const [result, setResult] = useState(null)
  const short = data.diamonds < pack.price

  async function confirm() {
    setBusy(true)
    setError('')
    try {
      const r = await buyEnergy(pack.id, requestId)
      setResult(r)
      playSfx('purchase')
      onDone?.()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="cx-sheet-wrap" role="dialog" aria-modal="true" aria-label={`Comprar ${pack.label}`} onClick={busy ? undefined : onClose}>
      <div className="cx-sheet sh-confirm" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="cx-sheet-x" onClick={onClose} disabled={busy} aria-label="Fechar"><X size={18} /></button>
        <span className="en-big"><GameIcon name="energy" size={34} /> +{pack.energy}</span>
        <h3>{pack.label}</h3>
        {!result ? (
          <>
            <dl className="sh-bill">
              <div><dt>Preço</dt><dd><GameIcon name="diamond" size={14} /> {pack.price} diamantes</dd></div>
              <div><dt>Seus diamantes</dt><dd>{fmt(data.diamonds)} → {short ? `faltam ${pack.price - data.diamonds}` : fmt(data.diamonds - pack.price)}</dd></div>
              <div><dt>Energia bônus</dt><dd>{fmt(data.bonus_energy)} → {fmt(data.bonus_energy + pack.energy)} (limite {fmt(data.bonus_cap)})</dd></div>
              <div><dt>Energia normal</dt><dd>{data.energy}/{data.regular_max} (não muda)</dd></div>
            </dl>
            {short && <p className="sh-msg is-error"><CircleAlert size={14} /> Diamantes insuficientes.</p>}
            {!pack.fits && <p className="sh-msg is-error"><CircleAlert size={14} /> Passaria do limite de energia bônus ({fmt(data.bonus_cap)}). Use um pouco antes de comprar.</p>}
            {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
            <button type="button" className="gx-btn sh-confirm-btn" disabled={busy || short || !pack.fits} onClick={confirm}>
              {busy ? 'Comprando…' : <><GameIcon name="diamond" size={16} /> Comprar por {pack.price}</>}
            </button>
          </>
        ) : (
          <>
            <p className="sh-msg is-ok"><Check size={16} /> +{result.energy_added} de energia bônus!</p>
            <dl className="sh-bill">
              <div><dt>Energia bônus agora</dt><dd><GameIcon name="energy" size={14} /> {fmt(result.bonus_energy)}</dd></div>
              <div><dt>Diamantes</dt><dd><GameIcon name="diamond" size={14} /> {fmt(result.diamonds)}</dd></div>
            </dl>
            <button type="button" className="gx-btn sh-confirm-btn" onClick={onClose}>Fechar</button>
          </>
        )}
      </div>
    </div>
  )
}

// Pacotes de energia: diamantes viram energia BÔNUS (a que não zera). Limite e regra aparecem antes da compra.
export default function EnergyTab({ onChanged }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [pack, setPack] = useState(null)
  const load = useCallback(async () => {
    try {
      setData(await fetchEnergy())
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])
  useEffect(() => {
    load()
  }, [load])

  if (!data) return error ? <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p> : <Skeleton rows={3} variant="tall" />
  const pct = Math.min(100, (data.bonus_energy / data.bonus_cap) * 100)

  return (
    <section className="en" aria-label="Pacotes de energia">
      <div className="en-now">
        <div>
          <small>Energia normal</small>
          <b><GameIcon name="energy" size={16} /> {data.energy}/{data.regular_max}</b>
          <span>volta a {data.regular_max} a cada {data.regen_hours} h · próxima às {hhmm(data.next_reset_at)}</span>
        </div>
        <div>
          <small>Energia bônus</small>
          <b><BatteryLow size={16} /> {fmt(data.bonus_energy)}</b>
          <span className="en-cap"><i style={{ width: `${pct}%` }} /></span>
          <span>limite {fmt(data.bonus_cap)} · nunca zera</span>
        </div>
      </div>
      <p className="cx-hint">Os pacotes somam energia bônus. Se a compra passar do limite, ela é recusada antes de cobrar.</p>
      <div className="en-packs">
        {data.packs.map((p) => (
          <button key={p.id} type="button" className={`en-pack ${p.fits ? '' : 'is-full'}`} onClick={() => setPack(p)}>
            <span className="en-pack-amt"><GameIcon name="energy" size={20} /> +{p.energy}</span>
            <strong>{p.label}</strong>
            <small>{p.description}</small>
            <span className={`sh-price gems ${data.diamonds < p.price ? 'is-short' : ''}`}><GameIcon name="diamond" size={14} /> {p.price}</span>
            {!p.fits && <small className="en-full">passaria do limite</small>}
          </button>
        ))}
      </div>
      <p className="cx-hint sh-foot">Troca avulsa (1 💎 = {data.exchange_rate} ⚡) continua em Cartas → diamantes, com o mesmo limite.</p>
      {pack && <ConfirmPack pack={pack} data={data} onClose={() => { setPack(null); load() }} onDone={onChanged} />}
    </section>
  )
}
