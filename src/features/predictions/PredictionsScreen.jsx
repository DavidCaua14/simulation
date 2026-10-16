import { useCallback, useEffect, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import useBetSlip from './hooks/useBetSlip'
import useWallet from './hooks/useWallet'
import { useNow } from './hooks/useMatches'
import { isLocked } from './utils/matchUtils'
import MatchesSection from './components/MatchesSection'
import TicketsSection from './components/TicketsSection'
import LeaderboardSection from './components/LeaderboardSection'
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
  const now = useNow(15000)
  const slip = useBetSlip()
  const wallet = useWallet()
  const refreshWallet = wallet.refresh

  const notify = useCallback((message) => setToast({ message, id: Date.now() }), [])

  useEffect(() => {
    if (!toast) return undefined
    const t = setTimeout(() => setToast(null), 4000)
    return () => clearTimeout(t)
  }, [toast])

  // Jogos que começaram saem sozinhos do bilhete em montagem
  useEffect(() => {
    const started = slip.pickList.filter((p) => isLocked(p.match, now))
    if (started.length) {
      slip.removeMany(started.map((p) => p.match.id))
      notify(`${started.length} jogo(s) já começaram e saíram do seu bilhete.`)
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
            <span>🪙 <b>{wallet.coins ?? '—'}</b></span>
            <span>⚡ <b>{wallet.energy ?? '—'}</b></span>
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
          <MatchesSection
            slip={slip}
            now={now}
            balance={wallet.coins}
            notify={notify}
            onWalletChange={refreshWallet}
          />
        )}
        {section === 'tickets' && <TicketsSection onWalletChange={refreshWallet} />}
        {section === 'rank' && <LeaderboardSection nickname={player.nickname} />}

        {toast && <div className="pred-toast" key={toast.id}>{toast.message}</div>}
      </div>
    </AppShell>
  )
}
