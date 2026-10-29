import { useEffect, useMemo, useState } from 'react'
import { ChevronRight } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import Sheet from '../ui/Sheet'
import { MSG_ACTIONS, MSG_CATEGORIES, MSG_KIND, msgCategory } from '../utils/managerUtils'

// Caixa de mensagens organizada por assunto: Elenco (satisfação, pedidos de saída, contratos), Mercado (propostas e
// respostas das negociações), Clube (diretoria, torcida, médico, resultados) e Carreira (propostas de trabalho).
export default function InboxSheet({ messages, focusId, initialCategory = 'all', onClose, onSeen, onAction }) {
  const focus = messages.find((m) => m.id === focusId)
  const [cat, setCat] = useState(focus ? msgCategory(focus) : initialCategory)
  const [open, setOpen] = useState(focusId || null)
  const counts = useMemo(() => {
    const c = { all: { total: 0, unread: 0 } }
    for (const m of messages) {
      const k = msgCategory(m)
      c[k] ||= { total: 0, unread: 0 }
      c[k].total += 1
      c.all.total += 1
      if (!m.read) (c[k].unread += 1), (c.all.unread += 1)
    }
    return c
  }, [messages])
  const list = cat === 'all' ? messages : messages.filter((m) => msgCategory(m) === cat)

  // Marca como lidas as mensagens do assunto aberto.
  useEffect(() => {
    const ids = list.filter((m) => !m.read).map((m) => m.id)
    if (ids.length) onSeen?.(ids)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cat])

  const hint = MSG_CATEGORIES.find((c) => c.id === cat)?.hint
  return (
    <Sheet kicker="Caixa de mensagens" title="Mensagens" onClose={onClose} tall className="ib-sheet">
      <div className="ib-cats" role="tablist" aria-label="Assuntos">
        {MSG_CATEGORIES.map((c) => (
          <button key={c.id} type="button" role="tab" aria-selected={cat === c.id} className={cat === c.id ? 'is-on' : ''} onClick={() => setCat(c.id)}>
            {c.label}
            {counts[c.id]?.unread > 0 && <em>{counts[c.id].unread}</em>}
          </button>
        ))}
      </div>
      {hint && <p className="sn-hint">{hint}</p>}
      {list.length === 0 && <p className="sn-muted sn-center">Nenhuma mensagem neste assunto.</p>}
      <ul className="ib-list is-full">
        {list.map((m) => {
          const k = MSG_KIND[m.kind] || MSG_KIND.system
          const isOpen = open === m.id
          const act = m.action || (msgCategory(m) === 'career' ? 'open_offers' : null)
          const action = act && MSG_ACTIONS[act]
          return (
            <li key={m.id}>
              <div className={`ib ${m.read ? '' : 'is-new'} k-${k.tone} ${isOpen ? 'is-open' : ''}`}>
                <button type="button" className="ib-main" aria-expanded={isOpen} onClick={() => setOpen(isOpen ? null : m.id)}>
                  {m.club_id ? <ClubCrest clubId={m.club_id} size={28} /> : <span className="ib-dot" />}
                  <span className="ib-txt">
                    <small>
                      {k.label} · dia {m.day_no}
                    </small>
                    <b>{m.title}</b>
                    {isOpen && <p>{m.body}</p>}
                  </span>
                </button>
                {isOpen && action && onAction && (
                  <button type="button" className="ib-act" onClick={() => onAction({ ...m, action: act })}>
                    {action} <ChevronRight size={14} />
                  </button>
                )}
              </div>
            </li>
          )
        })}
      </ul>
    </Sheet>
  )
}
