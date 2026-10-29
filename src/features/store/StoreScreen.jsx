import GameIcon from '../../components/ui/GameIcon'
import { useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import useWallet from '../predictions/hooks/useWallet'
import DiamondsSoon from './components/DiamondsSoon'
import EnergyTab from './components/EnergyTab'
import VisualTab from './components/VisualTab'
import WalletHistory from './components/WalletHistory'
import DiamondExchange from '../cards/components/DiamondExchange'
import '../cards/cards.css'
import './store.css'
import storeBg from '../home/assets/loja.webp'

const TABS = [
  { id: 'energy', label: 'Energia', icon: 'energy' },
  { id: 'visual', label: 'Visual', icon: 'palette' },
  { id: 'diamonds', label: 'Diamantes', icon: 'diamond', soon: true },
]
const fmt = (n) => Number(n ?? 0).toLocaleString('pt-BR')

export default function StoreScreen({ career, params, onBack }) {
  const { player } = career
  const wallet = useWallet({ coins: player.coins, energy: player.energy, diamonds: player.diamonds })
  const [tab, setTab] = useState(TABS.some((t) => t.id === params?.tab) ? params.tab : 'energy')
  const [history, setHistory] = useState(false)
  const [exchange, setExchange] = useState(false)
  return (
    <AppShell left={<button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar ao menu"><BackIcon /></button>} title="Loja">
      <div className="cx-screen sh-screen" style={{ '--store-bg': `url(${storeBg})` }}>
        <span className="sh-backdrop" aria-hidden="true" />
        <header className="sh-hero">
          <small>Loja do clube</small>
          <b>Energia, visual e recompensas</b>
          <span>Tudo é comprado com moedas e diamantes do jogo — nenhum pagamento real.</span>
        </header>
        <div className="cx-wallet">
          <span className="cx-pill coins"><GameIcon name="coins" size={14} /> {fmt(wallet.coins)}</span>
          <span className="cx-pill gems"><GameIcon name="diamond" size={14} /> {fmt(wallet.diamonds)}</span>
          <span className="cx-pill energy"><GameIcon name="energy" size={14} /> {fmt(wallet.energy)}</span>
          <button type="button" className="cx-pill wh-open" onClick={() => setHistory(true)} aria-label="Ver extrato"><GameIcon name="statement" size={14} /> Extrato</button>
        </div>
        <nav className="sh-tabs" role="tablist" aria-label="Seções da loja">
          {TABS.map(({ id, label, icon, soon }) => (
            <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? 'is-on' : ''} onClick={() => setTab(id)}>
              <GameIcon name={icon} size={18} /> {label}{soon && <GameIcon name="lock" size={12} title="em breve" />}
            </button>
          ))}
        </nav>
        <div className="cx-scroll">
          {tab === 'energy' && <><EnergyTab onChanged={wallet.refresh} /><button type="button" className="gx-btn-ghost" onClick={() => setExchange(true)}>Trocar diamantes por energia</button></>}
          {tab === 'visual' && <VisualTab onChanged={wallet.refresh} />}
          {tab === 'diamonds' && <DiamondsSoon />}
        </div>
        {history && <WalletHistory onClose={() => setHistory(false)} />}
        {exchange && <DiamondExchange diamonds={wallet.diamonds} onClose={() => setExchange(false)} onDone={wallet.refresh} />}
      </div>
    </AppShell>
  )
}
