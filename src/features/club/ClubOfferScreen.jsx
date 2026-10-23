import { useCallback, useEffect, useRef, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import SignOutButton from '../../components/ui/SignOutButton'
import LoadingOverlay from '../../components/ui/LoadingOverlay'
import { AlertIcon } from '../../components/ui/icons'
import ChatBubble from './components/ChatBubble'
import ClubProposalCard from './components/ClubProposalCard'
import { getClubById } from './data/clubs'
import { chooseClub, fetchInitialOffers } from './clubService'
import './club-offer.css'
import './club-offer-extra.css'

function buildScript(nickname) {
  return [
    `Fala, ${nickname}! Seja bem-vindo ao futebol profissional.`,
    'Sou seu empresário — a partir de agora cuido da sua carreira.',
    'Boa notícia: dois clubes já mandaram proposta depois de ver seu potencial.',
    'Todo mundo começa de baixo. Joga bem, que as propostas melhores vêm depois. Escolhe onde você quer começar:',
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

  return (
    <AppShell left={<SignOutButton />} title="Propostas">
      <LoadingOverlay show={saving} label={`Fechando com o ${club?.name}...`} />

      <div className="offer-screen">
        <div className="offer-body" ref={scrollRef}>
          {script.slice(0, visibleCount).map((text, i) => (
            <ChatBubble key={i} text={text} />
          ))}

          {showProposals && offers && (
            <div className="club-grid">
              {offers.map((o, i) => (
                <ClubProposalCard key={o.id} offer={o} selected={selectedId === o.id} onSelect={setSelectedId} style={{ animationDelay: `${i * 120}ms` }} />
              ))}
            </div>
          )}

          {showProposals && !offers && !offersError && <ChatBubble text="Só um instante, estou terminando de acertar os detalhes com os clubes…" />}

          {showProposals && offersError && (
            <div className="club-grid">
              <p className="sheet-msg is-error">
                <AlertIcon /> {offersError}
              </p>
              <button type="button" className="btn-primary" onClick={loadOffers}>
                Tentar de novo
              </button>
            </div>
          )}

          {closingLine && club && <ChatBubble text={`Show de bola! Vou acertar tudo com o ${club.name}.`} />}
        </div>

        <div className="offer-footer">
          {error && (
            <p className="sheet-msg is-error">
              <AlertIcon /> {error}
            </p>
          )}
          <button type="button" className="btn-primary" disabled={!selected || closingLine} onClick={handleConfirm}>
            Fechar com {club ? club.name : 'o clube'}
          </button>
        </div>
      </div>
    </AppShell>
  )
}
