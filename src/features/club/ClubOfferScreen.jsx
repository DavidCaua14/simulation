import { useCallback, useEffect, useRef, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import SignOutButton from '../../components/ui/SignOutButton'
import LoadingOverlay from '../../components/ui/LoadingOverlay'
import { AlertIcon } from '../../components/ui/icons'
import { Check } from 'lucide-react'
import agentPhoto from './assets/agent-photo.webp'
import ChatBubble from './components/ChatBubble'
import ClubProposalCard from './components/ClubProposalCard'
import { getClubById } from './data/clubs'
import { chooseClub, fetchInitialOffers } from './clubService'
import './club-offer.css'

function buildScript(nickname) {
  return [
    `Fala, ${nickname}! Seja bem-vindo à carreira de técnico.`,
    'Sou seu empresário — vou ajudar na sua carreira como técnico.',
    'Boa notícia: dois clubes já mandaram proposta para você assumir o comando.',
    'Todo mundo começa de baixo. Comande bem seu time, que as propostas melhores vêm depois. Escolhe onde você quer começar:',
  ]
}

export default function ClubOfferScreen({ career, onClubChosen }) {
  const nickname = career.player.nickname
  const script = useRef(buildScript(nickname)).current

  const [visibleCount, setVisibleCount] = useState(0)
  const [showProposals, setShowProposals] = useState(false)
  const [offers, setOffers] = useState(null) // null = carregando em segundo plano durante a conversa
  const [offersError, setOffersError] = useState('')
  const [selectedId, setSelectedId] = useState(null)
  const [closingLine, setClosingLine] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const scrollRef = useRef(null)

  // As propostas são sorteadas (e gravadas) no banco. A chamada roda enquanto o "empresário" conversa,
  // então quando as mensagens terminam as propostas já chegaram.
  const loadOffers = useCallback(() => {
    setOffersError('')
    fetchInitialOffers()
      .then(setOffers)
      .catch((e) => setOffersError(e.message))
  }, [])
  useEffect(() => {
    loadOffers()
  }, [loadOffers])

  // Revela as mensagens uma a uma, como num chat.
  useEffect(() => {
    if (visibleCount >= script.length) {
      const t = setTimeout(() => setShowProposals(true), 500)
      return () => clearTimeout(t)
    }
    const t = setTimeout(() => setVisibleCount((n) => n + 1), visibleCount === 0 ? 400 : 900)
    return () => clearTimeout(t)
  }, [visibleCount, script.length])

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
  }, [visibleCount, showProposals, closingLine, offers])

  const selected = offers?.find((o) => o.id === selectedId) || null
  const club = selected ? getClubById(selected.club_id) : null

  async function handleConfirm() {
    if (!selected) return
    setClosingLine(true)
    setError('')
    await new Promise((r) => setTimeout(r, 700))
    setSaving(true)
    try {
      const updatedCareer = await chooseClub({ careerId: career.id, offerId: selected.id })
      onClubChosen?.(updatedCareer)
    } catch (err) {
      setSaving(false)
      setClosingLine(false)
      setError(err.message || 'Não foi possível salvar o clube escolhido.')
    }
  }

  const typing = !showProposals && visibleCount < script.length

  return (
    <AppShell left={<SignOutButton />} title="Propostas">
      <LoadingOverlay show={saving} label={`Fechando com o ${club?.name}...`} />

      <div className="of-screen">
        <header className="of-agent">
          <span className="gx-frame of-agent-photo">
            <img src={agentPhoto} alt="" />
          </span>
          <span className="of-agent-id">
            <small>Mercado da bola</small>
            <strong>Seu empresário</strong>
          </span>
          <span className="gx-tag is-live">
            <span className="gx-dot" /> online
          </span>
        </header>

        <div className="of-body" ref={scrollRef}>
          {script.slice(0, visibleCount).map((text, i) => (
            <ChatBubble key={i} text={text} />
          ))}
          {typing && (
            <div className="of-typing" aria-label="Digitando">
              <i />
              <i />
              <i />
            </div>
          )}

          {showProposals && offers && (
            <section className="of-offers" role="radiogroup" aria-label="Propostas dos clubes">
              <h2 className="gx-title">
                Propostas na mesa <small>{offers.length} clubes</small>
              </h2>
              {offers.map((o, i) => (
                <ClubProposalCard key={o.id} offer={o} selected={selectedId === o.id} onSelect={setSelectedId} style={{ animationDelay: `${i * 140}ms` }} />
              ))}
            </section>
          )}

          {showProposals && !offers && !offersError && <ChatBubble text="Só um instante, estou terminando de acertar os detalhes com os clubes…" />}

          {showProposals && offersError && (
            <div className="of-offers">
              <p className="of-error">
                <AlertIcon /> {offersError}
              </p>
              <button type="button" className="gx-btn-ghost" onClick={loadOffers}>
                Tentar de novo
              </button>
            </div>
          )}

          {closingLine && club && <ChatBubble tone="me" text={`Fechado! Vou vestir a camisa do ${club.name}.`} />}
        </div>

        <footer className="of-footer">
          {error && (
            <p className="of-error">
              <AlertIcon /> {error}
            </p>
          )}
          <button type="button" className="gx-btn" disabled={!selected || closingLine} onClick={handleConfirm}>
            <Check size={18} strokeWidth={3} /> {club ? `Assinar com ${club.name}` : 'Escolha um clube'}
          </button>
        </footer>
      </div>
    </AppShell>
  )
}
