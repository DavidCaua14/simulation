import { useCallback, useEffect, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import useBetSlip from './hooks/useBetSlip'
import useWallet from './hooks/useWallet'
import useTicketResults from './hooks/useTicketResults'
import { useNow } from './hooks/useMatches'
import { isLocked } from './utils/matchUtils'
import MatchesSection from './components/MatchesSection'
import TicketsSection from './components/TicketsSection'
import LeaderboardSection from './components/LeaderboardSection'
import TicketResultModal from './components/TicketResultModal'
import { Amount, ToastIcon } from './components/PredIcons'
import './predictions.css'

const SECTIONS = [
  { id: 'games', label: 'Jogos' },
  { id: 'tickets', label: 'Meus bilhetes' },
  { id: 'rank', label: 'Ranking' },
]

export default function PredictionsScreen({ career, onBack }) {
  const { player } = career
  const [section, setSection] = useState('games')
  const [toast, setToast] = useState(null)
  const [results, setResults] = useState([])
  const now = useNow(15000)
  const slip = useBetSlip()
  const wallet = useWallet()
  const refreshWallet = wallet.refresh

  // kind: 'start' | 'finish' | 'ticket' | 'alert' | 'info'
  const notify = useCallback((text, kind = 'info') => setToast({ text, kind, id: Date.now() }), [])

  useEffect(() => {
    if (!toast) return undefined
    const t = setTimeout(() => setToast(null), 4000)
    return () => clearTimeout(t)
  }, [toast])

  // Quando um bilhete é liquidado, abre o resultado na hora e atualiza o saldo
  useTicketResults(
    useCallback(
      (ticket) => {
        setResults((r) => [...r, ticket])
        refreshWallet()
      },
      [refreshWallet],
    ),
  )

  // Jogos que começaram saem sozinhos do bilhete em montagem
  useEffect(() => {
    const started = slip.pickList.filter((p) => isLocked(p.match, now))
    if (started.length) {
      slip.removeMany(started.map((p) => p.match.id))
      notify(`${started.length} jogo(s) já começaram e saíram do seu bilhete.`, 'alert')
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [now])

  return (
    <AppShell
      left={
        <button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar">
          <BackIcon />
        </button>
      }
      title="Palpites"
    >
      <div className="pred-body">
        <div className="pred-top">
          <div className="pred-wallet">
            <Amount kind="coin" value={wallet.coins ?? '—'} />
            <Amount kind="energy" value={wallet.energy ?? '—'} />
            <small>Simulação · sem dinheiro real</small>
          </div>
          <div className="pred-seg">
            {SECTIONS.map((s) => (
              <button key={s.id} type="button" className={section === s.id ? 'is-on' : ''} onClick={() => setSection(s.id)}>
                {s.label}
              </button>
            ))}
          </div>
        </div>

        {section === 'games' && (
          <MatchesSection slip={slip} now={now} balance={wallet.coins} notify={notify} onWalletChange={refreshWallet} />
        )}
        {section === 'tickets' && <TicketsSection onWalletChange={refreshWallet} />}
        {section === 'rank' && <LeaderboardSection nickname={player.nickname} />}

        {toast && (
          <div className={`pred-toast ${toast.kind}`} key={toast.id} role="status">
            <ToastIcon kind={toast.kind} />
            <span>{toast.text}</span>
          </div>
        )}

        {results[0] && <TicketResultModal ticket={results[0]} onClose={() => setResults((r) => r.slice(1))} />}
      </div>
    </AppShell>
  )
}
