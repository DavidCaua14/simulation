import { useCallback, useEffect, useState } from 'react'
import { Coins, Gem, Zap } from 'lucide-react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import useWallet from '../predictions/hooks/useWallet'
import useInbox from './hooks/useInbox'
import { fetchCatalog, fetchCollection, fetchTiers, openBox } from './services/cardsApi'
import BoxOpener from './components/BoxOpener'
import OpenSummary from './components/OpenSummary'
import CardDetail from './components/CardDetail'
import DiamondExchange from './components/DiamondExchange'
import InboxTab from './tabs/InboxTab'
import CollectionTab from './tabs/CollectionTab'
import './cards.css'
import { Skeleton } from '../../components/ui/feedback'

const fmt = (n) => (n == null ? '—' : Number(n).toLocaleString('pt-BR'))

// Cartas: caixa de entrada + coleção. Tudo vem do banco; abrir uma caixa é feito pela função box_open.
export default function CardsScreen({ career, params, onBack, onNavigate }) {
  const { player } = career
  const wallet = useWallet({ coins: player.coins, energy: player.energy, diamonds: player.diamonds })
  const refreshWallet = wallet.refresh
  const inbox = useInbox()
  const inboxRefresh = inbox.refresh
  const [tab, setTab] = useState(params?.tab === 'collection' ? 'collection' : 'inbox')
  const [catalog, setCatalog] = useState([])
  const [owned, setOwned] = useState([])
  const [tiers, setTiers] = useState([])
  const [loadingCol, setLoadingCol] = useState(true)
  const [opener, setOpener] = useState(null) // lista de caixas abertas uma a uma
  const [summary, setSummary] = useState(null)
  const [batchBusy, setBatchBusy] = useState(false)
  const [detail, setDetail] = useState(null)
  const [swap, setSwap] = useState(false)
  const [error, setError] = useState('')

  const loadCollection = useCallback(async () => {
    try {
      const [cat, mine, tr] = await Promise.all([fetchCatalog(), fetchCollection(), fetchTiers()])
      setCatalog(cat || [])
      setOwned((mine || []).filter((m) => m.card))
      setTiers(tr || [])
      setError('')
    } catch (e) {
      setError(e.message)
    } finally {
      setLoadingCol(false)
    }
  }, [])

  useEffect(() => {
    loadCollection()
  }, [loadCollection])

  const afterOpen = useCallback(() => {
    refreshWallet()
  }, [refreshWallet])

  const closeOpener = useCallback(() => {
    setOpener(null)
    inboxRefresh()
    refreshWallet()
    loadCollection()
  }, [inboxRefresh, refreshWallet, loadCollection])

  // "Abrir todas": abre uma por uma no banco e mostra só o resumo no final
  async function openAll(list) {
    setBatchBusy(true)
    const results = []
    try {
      for (const b of list) results.push(await openBox(b.id))
    } catch (e) {
      setError(e.message)
    }
    setBatchBusy(false)
    if (results.length) setSummary(results)
    inboxRefresh()
    refreshWallet()
    loadCollection()
  }

  const tierRow = (id) => tiers.find((t) => t.id === id)

  return (
    <AppShell
      left={
        <button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar ao menu">
          <BackIcon />
        </button>
      }
      title="Cartas"
    >
      <div className="cx-screen">
        <div className="cx-wallet">
          <span className="cx-pill coins"><Coins size={14} /> {fmt(wallet.coins)}</span>
          <span className="cx-pill energy"><Zap size={14} fill="currentColor" /> {fmt(wallet.energy)}</span>
          <button type="button" className="cx-pill gems" onClick={() => setSwap(true)} aria-label="Trocar diamantes por energia">
            <Gem size={14} /> {fmt(wallet.diamonds)} <small>trocar</small>
          </button>
        </div>

        <div className="cx-tabs" role="tablist">
          <button type="button" role="tab" aria-selected={tab === 'inbox'} className={tab === 'inbox' ? 'is-on' : ''} onClick={() => setTab('inbox')}>
            Caixa de entrada{inbox.count > 0 && <span className="cx-count">{inbox.count}</span>}
          </button>
          <button type="button" role="tab" aria-selected={tab === 'collection'} className={tab === 'collection' ? 'is-on' : ''} onClick={() => setTab('collection')}>
            Coleção
          </button>
        </div>

        {error && <p className="cx-error">{error}</p>}

        <div className="cx-scroll">
          {tab === 'inbox' &&
            (inbox.loading ? (
              <Skeleton rows={4} variant="line" />
            ) : (
              <InboxTab
                boxes={inbox.boxes}
                busy={batchBusy}
                onOpenOne={(b) => setOpener([b])}
                onOpenSequence={(list) => setOpener(list)}
                onOpenAll={openAll}
              />
            ))}
          {tab === 'collection' &&
            (loadingCol ? <Skeleton rows={4} variant="line" /> : <CollectionTab catalog={catalog} owned={owned} onSelect={setDetail} />)}
        </div>

        {opener && <BoxOpener boxes={opener} onOpened={afterOpen} onClose={closeOpener} />}
        {summary && <OpenSummary results={summary} onClose={() => setSummary(null)} />}
        {detail && (
          <CardDetail
            entry={owned.find((o) => o.card.id === detail.card.id) || detail}
            tier={tierRow(detail.card.tier)}
            onClose={() => setDetail(null)}
            onSell={onNavigate ? (cardId) => onNavigate('store', { tab: 'market', sell: cardId }) : undefined}
            onChanged={async () => {
              await loadCollection()
              refreshWallet()
            }}
          />
        )}
        {swap && <DiamondExchange diamonds={wallet.diamonds ?? 0} onClose={() => setSwap(false)} onDone={() => refreshWallet()} />}
      </div>
    </AppShell>
  )
}
