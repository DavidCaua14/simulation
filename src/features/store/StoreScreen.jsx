import GameIcon from '../../components/ui/GameIcon'
import { useEffect, useState } from 'react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import useWallet from '../predictions/hooks/useWallet'
import DiamondsSoon from './components/DiamondsSoon'
import EnergyTab from './components/EnergyTab'
import VisualTab from './components/VisualTab'
import TrainEnergyTab from './components/TrainEnergyTab'
import ItemsTab from './components/ItemsTab'
import PacksTab from './components/PacksTab'
import { fetchOnlineItems, fetchOnlineStatus, fetchPacks } from '../online/services/onlineApi'
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
  const [pick, setTab] = useState(TABS.some((t) => t.id === params?.tab) || ['training', 'items', 'bigtime'].includes(params?.tab) ? params.tab : 'bigtime')
  const [history, setHistory] = useState(false)
  const [exchange, setExchange] = useState(false)
  // Energia de treino: só para quem tem clube no modo Online
  const [online, setOnline] = useState(false)
  // Itens (Apito de Ouro): aparece quando o servidor libera (online_items.enabled)
  const [items, setItems] = useState(false)
  // Caixas Big Time: aba principal quando o servidor libera (online_packs.enabled)
  const [packs, setPacks] = useState(null)
  useEffect(() => {
    fetchPacks().then((d) => setPacks(Boolean(d?.enabled))).catch(() => setPacks(false))
    fetchOnlineStatus().then((s) => setOnline(s?.access === 'playing' && s.club?.draft_step >= 3)).catch(() => {})
    fetchOnlineItems().then((d) => setItems(Boolean(d?.enabled))).catch(() => {})
  }, [])
  // sem caixas liberadas, a aba Big Time vira Energia
  const tab = pick === 'bigtime' && packs === false ? 'energy' : pick
  const tabs = [...(packs ? [{ id: 'bigtime', label: 'Big Time', icon: 'highlight' }] : []), TABS[0], ...(online ? [{ id: 'training', label: 'Treino', icon: 'energy' }] : []), ...(online && items ? [{ id: 'items', label: 'Itens', icon: 'diamond' }] : []), ...TABS.slice(1)]
  return (
    <AppShell left={<button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar ao menu"><BackIcon /></button>} title="Loja">
      <div className="cx-screen sh-screen" style={{ '--store-bg': `url(${storeBg})` }}>
        <span className="sh-backdrop" aria-hidden="true" />
        <header className="sh-hero">
          <small>Loja do clube</small>
          <b>{packs ? 'Caixas Big Time, energia e itens' : 'Energia, visual e recompensas'}</b>
          <span>Tudo é comprado com moedas e diamantes do jogo — nenhum pagamento real.</span>
        </header>
        <div className="cx-wallet">
          <span className="cx-pill coins"><GameIcon name="coins" size={14} /> {fmt(wallet.coins)}</span>
          <span className="cx-pill gems"><GameIcon name="diamond" size={14} /> {fmt(wallet.diamonds)}</span>
          <span className="cx-pill energy"><GameIcon name="energy" size={14} /> {fmt(wallet.energy)}</span>
          <button type="button" className="cx-pill wh-open" onClick={() => setHistory(true)} aria-label="Ver extrato"><GameIcon name="statement" size={14} /> Extrato</button>
        </div>
        <nav className="sh-tabs" role="tablist" aria-label="Seções da loja" style={{ gridTemplateColumns: `repeat(${tabs.length}, minmax(0, 1fr))` }}>
          {tabs.map(({ id, label, icon, soon }) => (
            <button key={id} type="button" role="tab" aria-selected={tab === id} className={tab === id ? 'is-on' : ''} onClick={() => setTab(id)}>
              <GameIcon name={icon} size={18} /> {label}{soon && <GameIcon name="lock" size={12} title="em breve" />}
            </button>
          ))}
        </nav>
        <div className="cx-scroll">
          {tab === 'bigtime' && packs && <PacksTab onChanged={wallet.refresh} onEmpty={() => setTab('energy')} />}
          {tab === 'energy' && <><EnergyTab onChanged={wallet.refresh} /><button type="button" className="gx-btn-ghost" onClick={() => setExchange(true)}>Trocar diamantes por energia</button></>}
          {tab === 'training' && online && <TrainEnergyTab onChanged={wallet.refresh} />}
          {tab === 'items' && online && items && <ItemsTab onChanged={wallet.refresh} />}
          {tab === 'visual' && <VisualTab onChanged={wallet.refresh} />}
          {tab === 'diamonds' && <DiamondsSoon />}
        </div>
        {history && <WalletHistory onClose={() => setHistory(false)} />}
        {exchange && <DiamondExchange diamonds={wallet.diamonds} onClose={() => setExchange(false)} onDone={wallet.refresh} />}
      </div>
    </AppShell>
  )
}
