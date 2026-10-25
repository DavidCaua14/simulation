import { useCallback, useEffect, useState } from 'react'
import { CalendarDays, Ticket, Trophy } from 'lucide-react'
import AppShell from '../../components/layout/AppShell'
import SeasonHeader from '../seasons/ui/SeasonHeader'
import useBetSlip from './hooks/useBetSlip'
import useWallet from './hooks/useWallet'
import useTicketResults from './hooks/useTicketResults'
import { useNow } from './hooks/useMatches'
import { isLocked } from './utils/matchUtils'
import MatchesSection from './components/MatchesSection'
import TicketsSection from './components/TicketsSection'
import LeaderboardSection from './components/LeaderboardSection'
import TicketResultModal from './components/TicketResultModal'
import { ToastIcon } from './components/PredIcons'
import '../seasons/seasons.css'
import './predictions.css'

const SECTIONS = [
  { id: 'games', label: 'Jogos', title: 'Palpites', Icon: CalendarDays },
  { id: 'tickets', label: 'Bilhetes', title: 'Bilhetes', Icon: Ticket },
  { id: 'rank', label: 'Ranking', title: 'Ranking', Icon: Trophy },
]

// PALPITES: mesmo padrão visual dos outros modos (cabeçalho do jogo, abas embaixo, painéis noturnos).
// Simulação com moedas do jogo — sem dinheiro real.
export default function PredictionsScreen({ career, onBack }) {
  const { player } = career
  const [section, setSection] = useState('games')
  const [toast, setToast] = useState(null)
  const [results, setResults] = useState([])
  const now = useNow(15000)
  const slip = useBetSlip()
  const wallet = useWallet({ coins: player.coins, energy: player.energy })
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

  const current = SECTIONS.find((s) => s.id === section)
  const headerCareer = { level: player.level, xp: player.xp ?? 0, coins: wallet.coins, energy: wallet.energy, bonus_energy: 0 }

  return (
    <AppShell header={<SeasonHeader title={current.title} kicker="Palpites · simulação" career={headerCareer} onBack={onBack} />}>
      <div className="sn-screen pred-screen">
        {toast && (
          <div className={`sn-toast pred-toast ${toast.kind}`} key={toast.id} role="status">
            <ToastIcon kind={toast.kind} />
            <span>{toast.text}</span>
          </div>
        )}

        <div className="pred-body" key={section}>
          {section === 'games' && <MatchesSection slip={slip} now={now} balance={wallet.coins} notify={notify} onWalletChange={refreshWallet} />}
          {section === 'tickets' && <TicketsSection onWalletChange={refreshWallet} />}
          {section === 'rank' && <LeaderboardSection nickname={player.nickname} />}
        </div>

        <nav className="sn-nav pred-nav" aria-label="Seções dos palpites">
          {SECTIONS.map(({ id, label, Icon }) => (
            <button key={id} type="button" className={section === id ? 'is-on' : ''} aria-current={section === id ? 'page' : undefined} onClick={() => setSection(id)}>
              <span className="sn-nav-icon">
                <Icon size={22} strokeWidth={section === id ? 2.4 : 2} />
                {id === 'games' && slip.count > 0 && <em aria-label={`${slip.count} palpite(s) no bilhete`}>{slip.count}</em>}
              </span>
              <small>{label}</small>
            </button>
          ))}
        </nav>

        {results[0] && <TicketResultModal ticket={results[0]} onClose={() => setResults((r) => r.slice(1))} />}
      </div>
    </AppShell>
  )
}
