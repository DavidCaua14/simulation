import { useCallback, useEffect, useState } from 'react'
import { ArrowLeft, Bell, Gift, Inbox, Megaphone, Shield, TrendingUp, Wallet } from 'lucide-react'
import GameIcon from '../../components/ui/GameIcon'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import { claimItem, fetchInbox, markSeen, notifyInboxChanged, REWARD_ICON, REWARD_LABEL, rewardEntries } from './inboxApi'
import './inbox.css'

// CAIXA DE ENTRADA: avisos do jogo (com período) e comunicados da administração, com premiações para resgatar.
const TABS = [['all', 'Tudo'], ['announcement', 'Avisos'], ['reward', 'Premiações']]
export const KIND_ICON = { announcement: Megaphone, reward: Gift, club: Shield, finance: Wallet, reputation: TrendingUp, removal: Wallet, info: Bell }
const fmtDate = (v) => (v ? new Date(v).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' }) : '')

export function RewardChips({ reward }) {
  const list = rewardEntries(reward)
  if (!list.length) return null
  return (
    <span className="gi-rewards">
      {list.map(([k, v]) => <span key={k}><GameIcon name={REWARD_ICON[k]} size={16} /> {Number(v).toLocaleString('pt-BR')} {REWARD_LABEL[k]}</span>)}
    </span>
  )
}

export default function InboxScreen({ onBack, onWalletChange }) {
  const [data, setData] = useState(null)
  const [tab, setTab] = useState('all')
  const [busy, setBusy] = useState(null)
  const [msg, setMsg] = useState(null)

  const load = useCallback(() => fetchInbox().then((d) => { setData(d); return d }).catch((e) => setMsg({ kind: 'error', text: e.message })), [])
  useEffect(() => {
    // Abrir a caixa marca como lido o que está nela.
    load().then((d) => {
      const unseen = (d?.items || []).filter((i) => !i.seen_at)
      if (unseen.length) markSeen(unseen).then(notifyInboxChanged).catch(() => {})
    })
  }, [load])

  async function claim(item) {
    setBusy(item.id)
    try {
      await claimItem(item)
      setMsg({ kind: 'ok', text: 'Premiação resgatada!' })
      onWalletChange?.()
      notifyInboxChanged()
      await load()
    } catch (e) {
      setMsg({ kind: 'error', text: e.message })
    } finally {
      setBusy(null)
    }
  }

  const items = (data?.items || []).filter((i) => tab === 'all' || (tab === 'announcement' ? i.type === 'announcement' : rewardEntries(i.reward).length > 0))
  return (
    <div className="gi">
      <header className="gi-top">
        <button type="button" className="gi-back" onClick={onBack} aria-label="Voltar"><ArrowLeft size={20} /></button>
        <h1>Caixa de entrada</h1>
        {data?.claimable > 0 && <span className="gi-pill">{data.claimable} para resgatar</span>}
      </header>
      <div className="gi-tabs" role="tablist">
        {TABS.map(([id, label]) => <button key={id} role="tab" aria-selected={tab === id} className={tab === id ? 'is-on' : ''} onClick={() => setTab(id)}>{label}</button>)}
      </div>
      {msg && <Notice kind={msg.kind} onClose={() => setMsg(null)}>{msg.text}</Notice>}
      {!data ? <Skeleton rows={4} /> : items.length === 0 ? (
        <EmptyState icon={Inbox} title="Nada por aqui" text="Avisos do jogo e premiações aparecem nesta caixa." />
      ) : (
        <ul className="gi-list">
          {items.map((i) => {
            const Icon = KIND_ICON[i.type === 'announcement' ? 'announcement' : i.kind] || Bell
            return (
              <li key={`${i.type}:${i.id}`} className={`gi-item k-${i.type === 'announcement' ? 'announcement' : i.kind}`}>
                <span className="gi-ico"><Icon size={18} /></span>
                <div className="gi-body">
                  <small>{i.type === 'announcement' ? 'Aviso' : 'Comunicado'} · {fmtDate(i.at)}{i.ends_at ? ` · até ${fmtDate(i.ends_at)}` : ''}</small>
                  <b>{i.title}</b>
                  <p>{i.body}</p>
                  <RewardChips reward={i.reward} />
                </div>
                {i.claimable ? (
                  <button type="button" className="gx-btn gi-claim" disabled={busy === i.id} onClick={() => claim(i)}>{busy === i.id ? '…' : 'Resgatar'}</button>
                ) : i.claimed_at ? <span className="gi-done">Resgatado</span> : null}
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
