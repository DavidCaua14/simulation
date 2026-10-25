import { useState } from 'react'
import { Check, CircleAlert, Clock, UserPlus, UserX, X } from 'lucide-react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import ProfileAvatar from '../profile/components/ProfileAvatar'
import { CountryFlag } from '../player/components/flags'
import { getClubById } from '../club/data/clubs'
import useFriends from './useFriends'
import { cancelInvite, removeFriend, respondInvite, sendInvite } from './friendsApi'
import FriendProfile from './FriendProfile'
import '../cards/cards.css'
import '../store/store.css'
import './friends.css'

function Person({ p, children, onClick }) {
  const club = p.club_id ? getClubById(p.club_id) : null
  const Tag = onClick ? 'button' : 'div'
  return (
    <Tag type={onClick ? 'button' : undefined} className="fr-person" onClick={onClick}>
      <ProfileAvatar profile={p} frame={p.frame} size={42} />
      <span className="fr-person-main">
        <strong>{p.nickname}</strong>
        <small><CountryFlag countryId={p.country} /> NV {p.level}{club ? ` · ${club.name}` : ''}</small>
      </span>
      <span className="fr-person-side">{children}</span>
    </Tag>
  )
}

// Amigos e convites: adicionar por username, convites recebidos/enviados, perfil (somente leitura) dos amigos.
export default function FriendsScreen({ onBack }) {
  const { data, error, refresh } = useFriends()
  const [tab, setTab] = useState('friends')
  const [name, setName] = useState('')
  const [msg, setMsg] = useState(null) // { kind: 'ok' | 'error' | 'info', text }
  const [busy, setBusy] = useState(null)
  const [open, setOpen] = useState(null)

  async function invite(e) {
    e.preventDefault()
    const n = name.trim()
    if (n.length < 3) return setMsg({ kind: 'error', text: 'Digite o username completo (3 caracteres ou mais).' })
    setBusy('invite')
    setMsg(null)
    try {
      const r = await sendInvite(n)
      setMsg(r.status === 'accepted'
        ? { kind: 'ok', text: `${r.nickname} já tinha te convidado: agora vocês são amigos!` }
        : { kind: 'ok', text: `Convite enviado para ${r.nickname}.` })
      setName('')
      await refresh()
    } catch (err) {
      const t = err.message
      setMsg({ kind: /já são amigos|já enviou/.test(t) ? 'info' : 'error', text: t })
    } finally {
      setBusy(null)
    }
  }

  async function act(id, fn, okText) {
    setBusy(id)
    setMsg(null)
    try {
      await fn()
      if (okText) setMsg({ kind: 'ok', text: okText })
      await refresh()
    } catch (err) {
      setMsg({ kind: 'error', text: err.message })
    } finally {
      setBusy(null)
    }
  }

  const incoming = data?.incoming || []
  const outgoing = data?.outgoing || []
  const declined = data?.declined || []
  const friends = data?.friends || []

  return (
    <AppShell
      left={<button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar ao menu"><BackIcon /></button>}
      title="Amigos"
    >
      <div className="fr-screen">
        <form className="fr-add" onSubmit={invite}>
          <label htmlFor="fr-name">Adicionar amigo pelo username</label>
          <div className="fr-add-row">
            <span className="fr-at">@</span>
            <input id="fr-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="username do jogador" autoComplete="off" autoCapitalize="off" spellCheck="false" maxLength={32} />
            <button type="submit" className="gx-btn fr-send" disabled={busy === 'invite'}><UserPlus size={16} /> {busy === 'invite' ? '…' : 'Convidar'}</button>
          </div>
          {msg && (
            <p className={`fr-msg is-${msg.kind}`}>
              {msg.kind === 'ok' ? <Check size={14} /> : <CircleAlert size={14} />} {msg.text}
            </p>
          )}
        </form>

        <div className="mk-views fr-tabs" role="tablist">
          <button type="button" role="tab" aria-selected={tab === 'friends'} className={tab === 'friends' ? 'is-on' : ''} onClick={() => setTab('friends')}>
            Amigos {friends.length > 0 && <span className="cx-count">{friends.length}</span>}
          </button>
          <button type="button" role="tab" aria-selected={tab === 'invites'} className={tab === 'invites' ? 'is-on' : ''} onClick={() => setTab('invites')}>
            Convites {incoming.length > 0 && <span className="cx-count">{incoming.length}</span>}
          </button>
        </div>

        {error && <p className="fr-msg is-error"><CircleAlert size={14} /> {error}</p>}
        <div className="fr-scroll">
          {!data && !error && <p className="cx-hint center">Carregando…</p>}

          {data && tab === 'friends' && (friends.length === 0 ? (
            <p className="cx-hint center">Você ainda não tem amigos no jogo. Convide alguém pelo username!</p>
          ) : (
            <div className="fr-list">
              {friends.map((f) => (
                <Person key={f.id} p={f} onClick={() => setOpen(f.nickname)}>
                  <small>amigos desde {new Date(f.since).toLocaleDateString('pt-BR')}</small>
                </Person>
              ))}
            </div>
          ))}

          {data && tab === 'invites' && (
            <>
              <h4 className="mk-h">Recebidos</h4>
              {incoming.length === 0 ? <p className="cx-hint">Nenhum convite recebido.</p> : (
                <div className="fr-list">
                  {incoming.map((f) => (
                    <Person key={f.id} p={f}>
                      <span className="fr-actions">
                        <button type="button" className="fr-ok" disabled={busy === f.id} onClick={() => act(f.id, () => respondInvite(f.id, true), `Você e ${f.nickname} agora são amigos!`)} aria-label={`Aceitar ${f.nickname}`}><Check size={16} /></button>
                        <button type="button" className="fr-no" disabled={busy === f.id} onClick={() => act(f.id, () => respondInvite(f.id, false), `Convite de ${f.nickname} recusado.`)} aria-label={`Recusar ${f.nickname}`}><X size={16} /></button>
                      </span>
                    </Person>
                  ))}
                </div>
              )}
              <h4 className="mk-h">Enviados</h4>
              {outgoing.length === 0 && declined.length === 0 ? <p className="cx-hint">Nenhum convite enviado.</p> : (
                <div className="fr-list">
                  {outgoing.map((f) => (
                    <Person key={f.id} p={f}>
                      <small className="fr-state"><Clock size={12} /> aguardando</small>
                      <button type="button" className="mk-cancel" disabled={busy === f.id} onClick={() => act(f.id, () => cancelInvite(f.id), 'Convite cancelado.')}>Cancelar</button>
                    </Person>
                  ))}
                  {declined.map((d) => (
                    <div key={d.id} className="fr-person is-declined">
                      <span className="fr-declined-icon"><UserX size={18} /></span>
                      <span className="fr-person-main"><strong>{d.nickname}</strong><small>recusou seu convite · {new Date(d.at).toLocaleDateString('pt-BR')}</small></span>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
        </div>

        {open && (
          <FriendProfile
            username={open}
            onClose={() => setOpen(null)}
            onRemove={(id) => act(id, () => removeFriend(id), `Amizade com ${open} desfeita.`).then(() => setOpen(null))}
          />
        )}
      </div>
    </AppShell>
  )
}
