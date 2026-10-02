import { useEffect, useRef, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import LoadingOverlay from '../../components/ui/LoadingOverlay'
import { ShieldIcon, AlertIcon } from '../../components/ui/icons'
import ChatBubble from './components/ChatBubble'
import ClubProposalCard from './components/ClubProposalCard'
import { CLUBS, getClubById } from './data/clubs'
import { chooseClub } from './clubService'
import './club-offer.css'

function buildScript(nickname) {
  return [
    `Fala, ${nickname}! Seja bem-vindo ao futebol profissional.`,
    'Sou seu empresário — a partir de agora cuido da sua carreira.',
    'Boa notícia: três clubes já mandaram proposta depois de ver seu potencial.',
    'Dá uma olhada e escolhe onde você quer começar:',
  ]
}

export default function ClubOfferScreen({ career, onClubChosen }) {
  const nickname = career.player.nickname
  const script = useRef(buildScript(nickname)).current

  const [visibleCount, setVisibleCount] = useState(0)
  const [showProposals, setShowProposals] = useState(false)
  const [selectedClub, setSelectedClub] = useState(null)
  const [closingLine, setClosingLine] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const scrollRef = useRef(null)

  // Revela as mensagens uma a uma, como num chat — sem nenhum loading aqui,
  // é só o ritmo da conversa.
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
  }, [visibleCount, showProposals, closingLine])

  async function handleConfirm() {
    if (!selectedClub) return
    setClosingLine(true)
    setError('')
    await new Promise((r) => setTimeout(r, 700))
    setSaving(true)
    try {
      const updatedCareer = await chooseClub({ careerId: career.id, clubId: selectedClub })
      onClubChosen?.(updatedCareer)
    } catch (err) {
      setSaving(false)
      setClosingLine(false)
      setError(err.message || 'Não foi possível salvar o clube escolhido.')
    }
  }

  const club = selectedClub ? getClubById(selectedClub) : null

  return (
    <AppShell left={<ShieldIcon />} title="Propostas">
      <LoadingOverlay show={saving} label={`Fechando com o ${club?.name}...`} />

      <div className="offer-screen">
        <div className="offer-body" ref={scrollRef}>
          {script.slice(0, visibleCount).map((text, i) => (
            <ChatBubble key={i} text={text} />
          ))}

          {showProposals && (
            <div className="club-grid">
              {CLUBS.map((c, i) => (
                <ClubProposalCard
                  key={c.id}
                  club={c}
                  selected={selectedClub === c.id}
                  onSelect={setSelectedClub}
                  style={{ animationDelay: `${i * 120}ms` }}
                />
              ))}
            </div>
          )}

          {closingLine && club && (
            <ChatBubble text={`Show de bola! Vou acertar tudo com o ${club.name}.`} />
          )}
        </div>

        <div className="offer-footer">
          {error && (
            <p className="sheet-msg is-error">
              <AlertIcon /> {error}
            </p>
          )}
          <button
            type="button"
            className="btn-primary"
            disabled={!selectedClub || closingLine}
            onClick={handleConfirm}
          >
            Fechar com {club ? club.name : 'o clube'}
          </button>
        </div>
      </div>
    </AppShell>
  )
}
