import { useCallback, useEffect, useState } from 'react'
import { ArrowLeftRight, CircleDot, Coins, Crown, Gem, Hourglass, Lock, Palette, Receipt, Sparkles, Zap } from 'lucide-react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import useWallet from '../predictions/hooks/useWallet'
import { fetchShop } from './services/storeApi'
import ShopItem from './components/ShopItem'
import BuyConfirm from './components/BuyConfirm'
import DiamondsSoon from './components/DiamondsSoon'
import WheelTab from './components/WheelTab'
import MarketTab from './components/MarketTab'
import EnergyTab from './components/EnergyTab'
import VisualTab from './components/VisualTab'
import WalletHistory from './components/WalletHistory'
import { Notice, Skeleton } from '../../components/ui/feedback'
import '../cards/cards.css'
import './store.css'

const fmt = (n) => (n == null ? '—' : Number(n).toLocaleString('pt-BR'))
const SECTION_ICON = { destaque: Sparkles, lenda: Crown }

function useCountdown(endsAt, onEnd) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 30000)
    return () => clearInterval(t)
  }, [])
  const ms = endsAt ? new Date(endsAt).getTime() - now : null
  useEffect(() => {
    if (ms != null && ms <= 0) onEnd?.()
  }, [ms, onEnd])
  if (ms == null) return ''
  const m = Math.max(0, Math.round(ms / 60000))
  return m >= 60 ? `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}min` : `${m} min`
}

// Loja: vitrine rotativa de Destaques e Lendas (moedas ou diamantes), roleta (diamantes), mercado entre jogadores
// (moedas) e "Comprar diamantes" (EM BREVE).
// Preço, saldo e entrega são decididos no servidor; a tela só mostra e pede a compra.
export default function StoreScreen({ career, params, onBack, onNavigate }) {
  const { player } = career
  const wallet = useWallet({ coins: player.coins, energy: player.energy, diamonds: player.diamonds })
  const refreshWallet = wallet.refresh
  const [shop, setShop] = useState(null)
  const [error, setError] = useState('')
  const [tab, setTab] = useState(params?.tab || 'destaque')
  const [buying, setBuying] = useState(null) // { item, currency }
  const [history, setHistory] = useState(false)

  const load = useCallback(async () => {
    try {
      setShop(await fetchShop())
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])
  useEffect(() => {
    load()
  }, [load])

  const sections = shop?.sections || []
  const section = sections.find((s) => s.tier === tab)
  const countdown = useCountdown(section?.ends_at, load)
  const newCount = section ? section.items.filter((it) => !it.owned).length : 0
  const tabs = [
    // antes da loja carregar, as duas vitrines já ocupam o lugar delas (as abas não "pulam")
    ...(shop ? sections : [{ tier: 'destaque', label: 'Destaques' }, { tier: 'lenda', label: 'Lendas' }]).map((s) => ({ id: s.tier, label: s.label, Icon: SECTION_ICON[s.tier] || Sparkles })),
    { id: 'wheel', label: 'Roleta', Icon: CircleDot },
    { id: 'market', label: 'Mercado', Icon: ArrowLeftRight },
    { id: 'energy', label: 'Energia', Icon: Zap },
    { id: 'visual', label: 'Visual', Icon: Palette },
    { id: 'diamonds', label: 'Diamantes', Icon: Gem, soon: true },
  ]
  // saldo mais recente: o do servidor depois de uma compra, senão o da carteira
  const balance = { coins: wallet.coins ?? shop?.wallet?.coins ?? 0, diamonds: wallet.diamonds ?? shop?.wallet?.diamonds ?? 0 }

  return (
    <AppShell
      left={
        <button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar ao menu">
          <BackIcon />
        </button>
      }
      title="Loja"
    >
      <div className="cx-screen sh-screen">
        <div className="cx-wallet">
          <span className="cx-pill coins"><Coins size={14} /> {fmt(balance.coins)}</span>
          <span className="cx-pill gems"><Gem size={14} /> {fmt(balance.diamonds)}</span>
          <span className="cx-pill energy"><Zap size={14} fill="currentColor" /> {fmt(wallet.energy)}</span>
          <button type="button" className="cx-pill wh-open" onClick={() => setHistory(true)} aria-label="Ver extrato"><Receipt size={14} /> Extrato</button>
        </div>

        <nav className="sh-tabs" role="tablist" aria-label="Seções da loja">
          {tabs.map(({ id, label, Icon, soon }) => (
            <button key={id} type="button" role="tab" aria-selected={tab === id} className={`${tab === id ? 'is-on' : ''} ${soon ? 'is-soon' : ''}`} onClick={() => setTab(id)}>
              <Icon size={15} /> {label}
              {soon && <Lock size={12} aria-label="em breve" className="sh-tab-lock" />}
            </button>
          ))}
        </nav>

        {error && <Notice kind="error">{error}</Notice>}

        <div className="cx-scroll">
          {!shop && !error && (tab === 'destaque' || tab === 'lenda') && <Skeleton rows={4} variant="grid" />}

          {section && (
            <>
              <header className={`sh-head sh-head-${section.tier}`}>
                <span className="sh-head-icon" aria-hidden="true">{section.tier === 'lenda' ? <Crown size={20} /> : <Sparkles size={20} />}</span>
                <div className="sh-head-main">
                  <strong>{section.label}</strong>
                  <p>{section.description}</p>
                </div>
                <div className="sh-head-meta">
                  <span className="sh-timer"><Hourglass size={13} /> {countdown}</span>
                  {newCount > 0 && <span className="sh-new-count">{newCount} {newCount === 1 ? 'nova' : 'novas'} p/ coleção</span>}
                </div>
              </header>
              <div className="sh-grid">
                {section.items.map((it) => (
                  <ShopItem key={it.card.id} item={it} wallet={balance} onBuy={(item, currency) => setBuying({ item, currency })} />
                ))}
              </div>
              <p className="cx-hint sh-foot">
                Limite: {section.per_user_limit} {section.per_user_limit === 1 ? 'cópia' : 'cópias'} de cada carta por vitrine. Cartas repetidas
                ficam na coleção e podem ser descartadas por moedas/diamantes.
              </p>
            </>
          )}

          {tab === 'wheel' && <WheelTab onSpent={refreshWallet} onOpenCollection={() => onNavigate?.('cards', { tab: 'collection' })} />}

          {tab === 'market' && (
            <MarketTab
              wallet={balance}
              initialSell={params?.sell}
              onChanged={refreshWallet}
              onOpenCollection={() => onNavigate?.('cards', { tab: 'collection' })}
            />
          )}

          {tab === 'energy' && <EnergyTab onChanged={refreshWallet} />}

          {tab === 'visual' && <VisualTab onChanged={refreshWallet} />}

          {tab === 'diamonds' && <DiamondsSoon />}
        </div>

        {history && <WalletHistory onClose={() => setHistory(false)} />}

        {buying && (
          <BuyConfirm
            item={buying.item}
            currency={buying.currency}
            wallet={balance}
            onClose={() => {
              setBuying(null)
              load()
            }}
            onBought={() => {
              refreshWallet()
            }}
            onOpenCollection={() => onNavigate?.('cards', { tab: 'collection' })}
          />
        )}
      </div>
    </AppShell>
  )
}
