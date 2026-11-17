import { useCallback, useEffect, useState } from 'react'
import { Check, CircleAlert, Gem, Package, Sparkles } from 'lucide-react'
import { Skeleton } from '../../../components/ui/feedback'
import { useAudio } from '../../audio/AudioContext'
import { buyOnlineItem, fetchOnlineItems } from '../../online/services/onlineApi'
import GoldenWhistle from '../../online/components/GoldenWhistle'
import { fmt } from './storeUtils'

// Itens do modo Online pagos com diamantes. Por enquanto só o Apito de Ouro.
export default function ItemsTab({ onChanged }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [ask, setAsk] = useState(false)
  const [bought, setBought] = useState(false)
  const { playSfx } = useAudio()
  const load = useCallback(() => fetchOnlineItems().then(setData).catch((e) => setError(e.message)), [])
  useEffect(() => {
    load()
  }, [load])
  if (!data) return error ? <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p> : <Skeleton rows={3} />
  if (!data.enabled) return <p className="sh-msg">Nenhum item disponível.</p>
  const it = data.items.golden_whistle
  const full = it.qty >= it.max
  const poor = data.diamonds < it.price
  const buy = () => {
    setBusy(true)
    setError('')
    buyOnlineItem('golden_whistle')
      .then((d) => {
        setData(d)
        setBought(true)
        setAsk(false)
        playSfx('purchase')
        onChanged?.()
      })
      .catch((e) => setError(e.message))
      .finally(() => setBusy(false))
  }
  return (
    <section className="it">
      <article className="it-card">
        <span className="it-art"><GoldenWhistle size={84} /></span>
        <div className="it-info">
          <small><Sparkles size={11} /> Item lendário · Modo Online</small>
          <strong>Apito de Ouro</strong>
          <p>Treino de elite: leva um jogador do seu elenco à <b>nota máxima (potencial)</b> na hora. Não gasta condição nem os treinos do dia.</p>
          <span className="it-stock"><Package size={12} /> {it.qty} de {it.max} guardados</span>
        </div>
      </article>
      {!ask ? (
        <button type="button" className="it-buy" disabled={busy || full || poor} onClick={() => { setAsk(true); setBought(false) }}>
          {full ? 'Estoque cheio — use um no Elenco' : <>Comprar · <Gem size={15} /> {fmt(it.price)}</>}
        </button>
      ) : (
        <div className="it-ask">
          <p>Comprar 1 Apito de Ouro por <b><Gem size={13} /> {fmt(it.price)}</b>?</p>
          <div>
            <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => setAsk(false)}>Voltar</button>
            <button type="button" className="gx-btn" disabled={busy} onClick={buy}>{busy ? 'Comprando…' : 'Confirmar'}</button>
          </div>
        </div>
      )}
      <dl className="sh-bill">
        <div><dt>Seus diamantes</dt><dd><Gem size={14} /> {fmt(data.diamonds)}</dd></div>
        <div><dt>Depois da compra</dt><dd><Gem size={14} /> {fmt(Math.max(0, data.diamonds - it.price))}</dd></div>
      </dl>
      <p className="it-how">Como usar: Online → Elenco → toque no jogador → <b>Apito de Ouro</b>.</p>
      {poor && !full && <p className="sh-msg is-error"><CircleAlert size={14} /> Faltam {fmt(it.price - data.diamonds)} diamantes.</p>}
      {bought && !error && <p className="sh-msg is-ok"><Check size={16} /> Apito de Ouro guardado. Use no Elenco.</p>}
      {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
    </section>
  )
}
