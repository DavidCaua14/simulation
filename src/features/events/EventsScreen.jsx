import { useCallback, useEffect, useState } from 'react'
import { CalendarClock, Gift, History } from 'lucide-react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import { EmptyState, Notice, Skeleton } from '../../components/ui/feedback'
import RewardReveal from '../../components/ui/RewardReveal'
import { useAudio } from '../audio/AudioContext'
import { claimEvent, claimStreak, fetchEvents } from './eventsApi'
import { RewardChip, fmtDate, useNow } from './eventsUi'
import EventCard from './EventCard'
import StreakPanel from './StreakPanel'
import AdminEvents from './AdminEvents'
import '../cards/cards.css'
import '../store/store.css'
import '../friends/friends.css'
import './events.css'

// Eventos: ativos (diários, semanais, especiais), próximos e encerrados; sequência diária; histórico de recompensas.
// Tudo vem do servidor: o progresso é contado pelas partidas, caixas, cartas, vendas e palpites reais.
export default function EventsScreen({ career, onBack, onNavigate }) {
  const { playSfx } = useAudio()
  const now = useNow()
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [tab, setTab] = useState('events')
  const [busy, setBusy] = useState(null)
  const [msg, setMsg] = useState(null) // erro: { kind: 'error', text }
  const [won, setWon] = useState(null) // recompensa conquistada: { title, subtitle, rewards }

  const load = useCallback(async () => {
    try {
      setData(await fetchEvents())
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])
  useEffect(() => {
    load()
  }, [load])
  // virou o dia/semana ou terminou um evento enquanto a tela estava aberta: recarrega
  useEffect(() => {
    if (!data) return
    const edges = [...data.active.map((e) => e.period_end), ...data.upcoming.map((e) => e.starts_at), data.streak?.resets_at].filter(Boolean)
    if (edges.some((t) => new Date(t).getTime() <= now)) load()
  }, [now, data, load])

  async function claim(ev, completionId) {
    setBusy(ev.id)
    setMsg(null)
    try {
      const r = await claimEvent(completionId)
      playSfx('reward')
      setWon({ subtitle: r.event || ev.name, rewards: r.rewards || [] })
      await load()
    } catch (e) {
      setMsg({ kind: 'error', text: e.message })
    } finally {
      setBusy(null)
    }
  }

  async function claimDaily() {
    setBusy('streak')
    setMsg(null)
    try {
      const r = await claimStreak()
      playSfx('reward')
      const rewards = [{ kind: 'coins', amount: r.coins }, r.diamonds > 0 && { kind: 'diamonds', amount: r.diamonds }, r.box_tier && { kind: 'box', amount: 1, ref: r.box_tier }].filter(Boolean)
      if (r.replayed) setMsg({ kind: 'info', text: 'A recompensa de hoje já foi resgatada.' })
      else setWon({ title: `Dia ${r.day} conquistado!`, subtitle: `Sequência diária · ${r.current} ${r.current === 1 ? 'dia seguido' : 'dias seguidos'}`, rewards })
      await load()
    } catch (e) {
      setMsg({ kind: 'error', text: e.message })
    } finally {
      setBusy(null)
    }
  }

  const active = data?.active || []
  const upcoming = data?.upcoming || []
  const ended = data?.ended || []
  const history = data?.history || []
  const tabs = [['events', 'Eventos'], ['history', 'Histórico'], ...(data?.is_admin ? [['admin', 'Admin']] : [])]
  const hasBox = won?.rewards?.some((r) => r.kind === 'box')

  return (
    <AppShell
      left={<button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar ao menu"><BackIcon /></button>}
      title="Eventos"
    >
      <div className="fr-screen ev-screen">
        <div className="mk-views" role="tablist" style={{ gridTemplateColumns: `repeat(${tabs.length}, 1fr)` }}>
          {tabs.map(([id, label]) => (
            <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? 'is-on' : ''} onClick={() => { setTab(id); setMsg(null) }}>
              {label} {id === 'events' && data?.claimable > 0 && <span className="cx-count">{data.claimable}</span>}
            </button>
          ))}
        </div>

        {msg && <Notice kind={msg.kind} onClose={() => setMsg(null)}>{msg.text}</Notice>}
        {error && <Notice kind="error">{error}</Notice>}

        <div className="fr-scroll">
          {!data && !error && <><Skeleton rows={1} variant="tall" /><div style={{ height: 12 }} /><Skeleton rows={2} variant="tall" /></>}

          {data && tab === 'events' && (
            <>
              <StreakPanel streak={data.streak} now={now} busy={busy === 'streak'} onClaim={claimDaily} />
              <h4 className="gx-subtitle">Acontecendo agora <small>{active.length} {active.length === 1 ? 'evento' : 'eventos'}</small></h4>
              {active.length === 0 ? (
                <EmptyState compact icon={CalendarClock} title="Sem eventos agora" text={upcoming.length ? 'Confira abaixo o que vem por aí.' : 'Novos desafios aparecem aqui assim que começarem.'} />
              ) : (
                <div className="ev-list">
                  {active.map((ev) => <EventCard key={ev.id} ev={ev} now={now} busy={busy === ev.id} onClaim={claim} playerLevel={career?.player?.level} />)}
                </div>
              )}
              {upcoming.length > 0 && (
                <>
                  <h4 className="gx-subtitle">Em breve</h4>
                  <div className="ev-list">{upcoming.map((ev) => <EventCard key={ev.id} ev={ev} now={now} playerLevel={career?.player?.level} />)}</div>
                </>
              )}
              {ended.length > 0 && (
                <>
                  <h4 className="gx-subtitle">Encerrados recentemente</h4>
                  <div className="ev-list">{ended.map((ev) => <EventCard key={ev.id} ev={ev} now={now} busy={busy === ev.id} onClaim={claim} />)}</div>
                </>
              )}
              <p className="cx-hint ev-foot">Horários de Brasília. Eventos diários renovam à meia-noite; semanais, na segunda-feira.</p>
            </>
          )}

          {data && tab === 'history' && (history.length === 0 ? (
            <EmptyState icon={History} title="Nenhuma recompensa ainda" text="Complete os objetivos de um evento e resgate: tudo o que você ganhar fica registrado aqui." action="Ver eventos" onAction={() => setTab('events')} />
          ) : (
            <div className="fr-list">
              {history.map((h, i) => (
                <div key={i} className="ev-hist">
                  <span className="ev-hist-main"><strong>{h.event}</strong><small>{fmtDate(h.claimed_at)}</small></span>
                  <div className="ev-chips">{(h.rewards || []).map((r, j) => <RewardChip key={j} r={r} />)}</div>
                </div>
              ))}
            </div>
          ))}

          {data && tab === 'admin' && data.is_admin && <AdminEvents onChanged={load} />}
        </div>

        {won && (
          <RewardReveal
            title={won.title}
            subtitle={won.subtitle}
            rewards={won.rewards.map((r, i) => <RewardChip key={i} r={r} />)}
            onClose={() => setWon(null)}
            actions={<>
              {hasBox && <button type="button" className="gx-btn" onClick={() => onNavigate?.('cards', { tab: 'inbox' })}><Gift size={16} /> Abrir caixas</button>}
              <button type="button" className={hasBox ? 'gx-btn-ghost' : 'gx-btn'} onClick={() => setWon(null)}>Continuar</button>
            </>}
          />
        )}
      </div>
    </AppShell>
  )
}
