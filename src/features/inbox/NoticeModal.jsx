import { useEffect, useState } from 'react'
import { Bell } from 'lucide-react'
import { claimItem, fetchPending, markSeen, notifyInboxChanged, rewardEntries } from './inboxApi'
import { KIND_ICON, RewardChips } from './InboxScreen'
import './inbox.css'

// MODAL DA TELA INICIAL: mostra, um por vez, os avisos no período e os comunicados ainda não vistos
// (premiações, troca de clube, ajustes feitos pela administração). Cada item aparece uma única vez.
const KIND_TITLE = { announcement: 'Aviso', reward: 'Premiação', club: 'Mudança de clube', finance: 'Caixa do clube', reputation: 'Reputação', removal: 'Carteira', info: 'Comunicado' }

export default function NoticeModal({ onWalletChange }) {
  const [queue, setQueue] = useState([])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    fetchPending().then((list) => { if (alive && Array.isArray(list)) setQueue(list) }).catch(() => {})
    return () => { alive = false }
  }, [])

  const item = queue[0]
  if (!item) return null
  const kind = item.type === 'announcement' ? 'announcement' : item.kind
  const Icon = KIND_ICON[kind] || Bell
  const hasReward = item.claimable && rewardEntries(item.reward).length > 0

  async function next(claim) {
    setBusy(true)
    setError('')
    try {
      if (claim) {
        await claimItem(item)
        onWalletChange?.()
      }
      await markSeen([item])
      notifyInboxChanged()
      setQueue((q) => q.slice(1))
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="pn-overlay" role="dialog" aria-modal="true" aria-labelledby="pn-title">
      <div className={`pn-card k-${kind}`}>
        <span className="pn-badge"><Icon size={26} /></span>
        <small className="pn-kind">{KIND_TITLE[kind] || 'Comunicado'}{queue.length > 1 ? ` · 1 de ${queue.length}` : ''}</small>
        <h2 id="pn-title">{item.title}</h2>
        <p>{item.body}</p>
        <RewardChips reward={item.reward} />
        {error && <p className="pn-error">{error}</p>}
        <div className="pn-actions">
          {hasReward ? (
            <>
              <button type="button" className="gx-btn" disabled={busy} onClick={() => next(true)}>{busy ? 'Resgatando…' : 'Resgatar'}</button>
              <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => next(false)}>Depois (fica na caixa)</button>
            </>
          ) : (
            <button type="button" className="gx-btn" disabled={busy} onClick={() => next(false)}>{queue.length > 1 ? 'Próximo' : 'Entendi'}</button>
          )}
        </div>
      </div>
    </div>
  )
}
