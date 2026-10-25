import { useEffect, useState } from 'react'
import ClubCrest from '../../club/components/ClubCrest'
import Sheet from '../ui/Sheet'
import { MSG_KIND } from '../utils/managerUtils'

// Caixa de mensagens: diretoria, torcida, departamento médico, propostas, imprensa...
export default function InboxSheet({ messages, focusId, onClose, onSeen }) {
  const [open, setOpen] = useState(focusId || null)
  useEffect(() => {
    onSeen?.()
    // marca como lidas ao abrir a caixa (uma vez)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  return (
    <Sheet kicker="Caixa de mensagens" title="Mensagens" onClose={onClose} tall>
      {messages.length === 0 && <p className="sn-muted sn-center">Nenhuma mensagem.</p>}
      <ul className="ib-list is-full">
        {messages.map((m) => {
          const k = MSG_KIND[m.kind] || MSG_KIND.system
          const isOpen = open === m.id
          return (
            <li key={m.id}>
              <button type="button" className={`ib ${m.read ? '' : 'is-new'} k-${k.tone} ${isOpen ? 'is-open' : ''}`} onClick={() => setOpen(isOpen ? null : m.id)}>
                {m.club_id ? <ClubCrest clubId={m.club_id} size={28} /> : <span className="ib-dot" />}
                <span className="ib-txt">
                  <small>
                    {k.label} · dia {m.day_no}
                  </small>
                  <b>{m.title}</b>
                  {isOpen && <p>{m.body}</p>}
                </span>
              </button>
            </li>
          )
        })}
      </ul>
    </Sheet>
  )
}
