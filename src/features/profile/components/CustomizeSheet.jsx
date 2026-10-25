import { useEffect, useState } from 'react'
import { Check } from 'lucide-react'
import { equipCosmetic, fetchCosmetics } from '../services/profileApi'
import ProfileHero from './ProfileHero'
import { KINDS, CosmeticSwatch } from './cosmeticsUi'
import Sheet from './Sheet'

// Personalizar: equipar/desequipar os itens que o jogador TEM. Comprar outros fica na Loja → Visual.
export default function CustomizeSheet({ profile, onClose, onChanged, onOpenStore }) {
  const [data, setData] = useState(null)
  const [kind, setKind] = useState('background')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const load = () => fetchCosmetics().then(setData).catch((e) => setError(e.message))
  useEffect(() => {
    load()
  }, [])

  const items = (data?.items || []).filter((i) => i.kind === kind && i.owned)
  const equipped = (data?.items || []).find((i) => i.kind === kind && i.equipped)

  async function equip(id) {
    setBusy(true)
    setError('')
    try {
      await equipCosmetic(kind, id)
      await load()
      onChanged?.()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <Sheet title="Personalizar perfil" onClose={onClose}>
      <ProfileHero profile={profile} compact />
      <div className="cz-kinds" role="tablist">
        {KINDS.map((k) => (
          <button key={k.id} type="button" role="tab" aria-selected={kind === k.id} className={kind === k.id ? 'is-on' : ''} onClick={() => setKind(k.id)}>
            {k.label}
          </button>
        ))}
      </div>
      {error && <p className="pf-error">{error}</p>}
      {!data ? <p className="pf-hint">Carregando…</p> : (
        <>
          <div className="cz-grid">
            {kind !== 'background' && (
              <button type="button" className={`cz-item ${!equipped ? 'is-on' : ''}`} disabled={busy} onClick={() => equip(null)}>
                <span className="cz-none">Nenhum</span>
                {!equipped && <span className="cz-check"><Check size={13} /></span>}
              </button>
            )}
            {items.map((i) => (
              <button key={i.id} type="button" className={`cz-item ${i.equipped ? 'is-on' : ''}`} disabled={busy || i.equipped} onClick={() => equip(i.id)}>
                <CosmeticSwatch item={i} />
                <span className="cz-label">{i.label}</span>
                {i.equipped && <span className="cz-check"><Check size={13} /></span>}
              </button>
            ))}
          </div>
          {items.length === 0 && kind !== 'background' && <p className="pf-hint">Você ainda não tem itens deste tipo.</p>}
          <button type="button" className="pf-btn block" onClick={onOpenStore}>Ver mais itens na Loja → Visual</button>
        </>
      )}
    </Sheet>
  )
}
