import GameIcon from '../../../components/ui/GameIcon'
import { useCallback, useEffect, useRef, useState } from 'react'
import { Check, CircleAlert, X } from 'lucide-react'
import ProfileHero from '../../profile/components/ProfileHero'
import { CosmeticSwatch, KINDS, RARITY_LABEL } from '../../profile/components/cosmeticsUi'
import { buyCosmetic, equipCosmetic, fetchCosmetics, fetchMyProfile } from '../../profile/services/profileApi'
import { newRequestId } from '../services/storeApi'
import { useAudio } from '../../audio/AudioContext'
import { Skeleton } from '../../../components/ui/feedback'

function BuySheet({ item, diamonds, profile, onClose, onDone }) {
  const requestId = useRef(newRequestId()).current
  const [busy, setBusy] = useState(false)
  const { playSfx } = useAudio()
  const [error, setError] = useState('')
  const [done, setDone] = useState(null)
  const short = diamonds < item.price

  async function buy(andEquip) {
    setBusy(true)
    setError('')
    try {
      const r = done || (await buyCosmetic(item.id, requestId))
      if (andEquip) await equipCosmetic(item.kind, item.id)
      setDone({ ...r, equipped: andEquip })
      playSfx('purchase')
      onDone?.()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="cx-sheet-wrap" role="dialog" aria-modal="true" aria-label={`Comprar ${item.label}`} onClick={busy ? undefined : onClose}>
      <div className="cx-sheet sh-confirm vs-sheet" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="cx-sheet-x" onClick={onClose} disabled={busy} aria-label="Fechar"><X size={18} /></button>
        <ProfileHero profile={profile} preview={{ [item.kind]: item }} compact />
        <h3>{item.label}</h3>
        <p className="vs-meta">{KINDS.find((k) => k.id === item.kind)?.label.replace(/s$/, '')} · {RARITY_LABEL[item.rarity]} · item visual (não muda cartas nem atletas)</p>
        {!done ? (
          <>
            <dl className="sh-bill">
              <div><dt>Preço</dt><dd><GameIcon name="diamond" size={14} /> {item.price} diamantes</dd></div>
              <div className={short ? 'is-short' : ''}><dt>Seus diamantes</dt><dd>{diamonds} → {short ? `faltam ${item.price - diamonds}` : diamonds - item.price}</dd></div>
            </dl>
            {short && <p className="sh-msg is-error"><CircleAlert size={14} /> Diamantes insuficientes.</p>}
            {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
            <div className="sh-confirm-actions">
              <button type="button" className="gx-btn-ghost" disabled={busy || short} onClick={() => buy(false)}>Só comprar</button>
              <button type="button" className="gx-btn" disabled={busy || short} onClick={() => buy(true)}>{busy ? '…' : 'Comprar e usar'}</button>
            </div>
          </>
        ) : (
          <>
            <p className="sh-msg is-ok"><Check size={16} /> {done.equipped ? 'Comprado e equipado!' : 'Comprado! Equipe quando quiser no Perfil.'}</p>
            <button type="button" className="gx-btn sh-confirm-btn" onClick={onClose}>Fechar</button>
          </>
        )}
      </div>
    </div>
  )
}

// Loja → Visual: cosméticos do perfil (molduras, fundos, efeitos, emblemas, temas) comprados com diamantes.
// Prévia no próprio perfil antes de comprar; mostra o que já é seu e o que está equipado.
export default function VisualTab({ onChanged }) {
  const [data, setData] = useState(null)
  const [profile, setProfile] = useState(null)
  const [kind, setKind] = useState('frame')
  const [sel, setSel] = useState(null)
  const [buying, setBuying] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const load = useCallback(async () => {
    try {
      const [c, p] = await Promise.all([fetchCosmetics(), fetchMyProfile()])
      setData(c)
      setProfile(p)
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])
  useEffect(() => {
    load()
  }, [load])

  const items = (data?.items || []).filter((i) => i.kind === kind)
  const current = sel && sel.kind === kind ? items.find((i) => i.id === sel.id) : null

  async function equip(item, on) {
    setBusy(true)
    setError('')
    try {
      await equipCosmetic(item.kind, on ? item.id : null)
      await load()
      onChanged?.()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  if (!data || !profile) return error ? <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p> : <Skeleton rows={3} variant="tall" />

  return (
    <section className="vs" aria-label="Itens visuais do perfil">
      <ProfileHero profile={profile} preview={current ? { [current.kind]: current } : {}} compact />
      <p className="cx-hint vs-note">{current ? `Prévia: ${current.label}.` : 'Toque num item para ver como fica no seu perfil.'} Itens visuais não mudam cartas nem atletas.</p>
      <div className="cz-kinds" role="tablist">
        {KINDS.map((k) => (
          <button key={k.id} type="button" role="tab" aria-selected={kind === k.id} className={kind === k.id ? 'is-on' : ''} onClick={() => { setKind(k.id); setSel(null) }}>
            {k.label}
          </button>
        ))}
      </div>
      {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
      <div className="vs-grid">
        {items.map((i) => (
          <article key={i.id} className={`vs-item r-${i.rarity} ${current?.id === i.id ? 'is-sel' : ''}`}>
            <button type="button" className="vs-preview" onClick={() => setSel(i)} aria-label={`Ver prévia de ${i.label}`}>
              <CosmeticSwatch item={i} size={58} />
            </button>
            <strong>{i.label}</strong>
            <small>{RARITY_LABEL[i.rarity]}{i.price === 0 ? ' · grátis' : ''}</small>
            {i.equipped ? (
              <button type="button" className="vs-btn is-on" disabled={busy || i.kind === 'background'} onClick={() => equip(i, false)}>
                <Check size={13} /> {i.kind === 'background' ? 'Em uso' : 'Em uso · tirar'}
              </button>
            ) : i.owned ? (
              <button type="button" className="vs-btn" disabled={busy} onClick={() => equip(i, true)}>Usar (é seu)</button>
            ) : (
              <button type="button" className={`vs-btn buy ${data.diamonds < i.price ? 'is-short' : ''}`} onClick={() => { setSel(i); setBuying(i) }}>
                <GameIcon name="diamond" size={13} /> {i.price}
              </button>
            )}
          </article>
        ))}
      </div>
      {buying && (
        <BuySheet item={buying} diamonds={data.diamonds} profile={profile} onClose={() => { setBuying(null); load() }} onDone={onChanged} />
      )}
    </section>
  )
}
