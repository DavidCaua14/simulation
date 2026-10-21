import { useCallback, useEffect, useState } from 'react'
import { ChevronLeft } from 'lucide-react'
import AppShell from '../../components/layout/AppShell'
import { BackIcon } from '../../components/ui/icons'
import useSeasonHub from './hooks/useSeasonHub'
import { playMatch, respondOffer, startNextSeason } from './services/seasonsApi'
import PlayerCard from './components/PlayerCard'
import CompetitionCard from './components/CompetitionCard'
import CompetitionDetail from './components/CompetitionDetail'
import MatchResultModal from './components/MatchResultModal'
import OffersPanel from './components/OffersPanel'
import CareerPanel from './components/CareerPanel'
import SeasonSummary from './components/SeasonSummary'
import { getClubById } from '../club/data/clubs'
import { formatRemaining } from './utils/seasonUtils'
import useCountdown from './hooks/useCountdown'
import './seasons.css'

const TABS = [
  { id: 'comps', label: 'Campeonatos' },
  { id: 'offers', label: 'Propostas' },
  { id: 'career', label: 'Carreira' },
]

export default function SeasonsScreen({ onBack }) {
  const { hub, loading, error, reload } = useSeasonHub()
  const [tab, setTab] = useState('comps')
  const [openComp, setOpenComp] = useState(null) // id do campeonato aberto em detalhe
  const [playing, setPlaying] = useState(null)
  const [result, setResult] = useState(null)
  const [busyOffer, setBusyOffer] = useState(null)
  const [starting, setStarting] = useState(false)
  const [toast, setToast] = useState(null)

  const notify = useCallback((text, kind = 'info') => setToast({ text, kind, id: Date.now() }), [])
  useEffect(() => {
    if (!toast) return undefined
    const t = setTimeout(() => setToast(null), 4200)
    return () => clearTimeout(t)
  }, [toast])

  const remaining = useCountdown(hub?.career.next_reset_at, () => reload({ silent: true }))

  async function handlePlay(competitionId) {
    setPlaying(competitionId)
    try {
      const r = await playMatch(competitionId)
      setResult(r)
      reload({ silent: true }) // atualiza energia, XP, tabela... enquanto o resultado é revelado
    } catch (e) {
      notify(e.message, 'alert')
      reload({ silent: true })
    } finally {
      setPlaying(null)
    }
  }

  async function handleOffer(offerId, accept) {
    setBusyOffer(offerId)
    try {
      const r = await respondOffer(offerId, accept)
      await reload({ silent: true })
      if (r.accepted) {
        notify(`Transferência concluída! Você agora joga pelo ${getClubById(r.club_id)?.name}.`, 'ok')
        setTab('comps')
      } else {
        notify('Proposta recusada.', 'info')
      }
    } catch (e) {
      notify(e.message, 'alert')
    } finally {
      setBusyOffer(null)
    }
  }

  async function handleStartNext() {
    setStarting(true)
    try {
      await startNextSeason()
      await reload({ silent: true })
      setTab('comps')
      notify('Nova temporada! Bola rolando.', 'ok')
    } catch (e) {
      notify(e.message, 'alert')
    } finally {
      setStarting(false)
    }
  }

  const closeResult = () => {
    setResult(null)
    reload({ silent: true })
  }

  const detailComp = hub?.competitions.find((c) => c.id === openComp)
  const finished = hub?.season.status === 'finished'

  // Texto do botão quando não dá para simular
  const canPlay = hub ? hub.career.energy + hub.career.bonus_energy > 0 && !finished : false
  const blockedText = finished
    ? 'Temporada encerrada'
    : remaining != null
      ? `Sem energia · recarga em ${formatRemaining(remaining)}`
      : 'Sem energia'

  return (
    <AppShell
      left={
        <button
          type="button"
          className="icon-btn"
          onClick={detailComp ? () => setOpenComp(null) : onBack}
          aria-label="Voltar"
        >
          {detailComp ? <ChevronLeft size={20} /> : <BackIcon />}
        </button>
      }
      title={detailComp ? detailComp.name : 'Temporadas'}
    >
      <div className="sn-screen">
        {toast && <div className={`sn-toast ${toast.kind}`}>{toast.text}</div>}

        <div className="sn-scroll">
          {loading && !hub && <p className="sn-muted sn-center">Carregando sua temporada…</p>}

          {error && !hub && (
            <div className="sn-empty card">
              <p>{error}</p>
              <button type="button" className="sn-ghost" onClick={() => reload()}>
                Tentar de novo
              </button>
            </div>
          )}

          {hub && !detailComp && (
            <>
              <PlayerCard
                career={hub.career}
                stats={hub.stats}
                season={hub.season}
                onRecharged={() => reload({ silent: true })}
              />

              <div className="sn-seg" role="tablist">
                {TABS.map((t) => (
                  <button key={t.id} type="button" role="tab" aria-selected={tab === t.id} className={tab === t.id ? 'is-on' : ''} onClick={() => setTab(t.id)}>
                    {t.label}
                    {t.id === 'offers' && hub.offers.length > 0 && <em>{hub.offers.length}</em>}
                  </button>
                ))}
              </div>

              {tab === 'comps' && (
                <div className="sn-list">
                  {finished && <SeasonSummary season={hub.season} starting={starting} onStartNext={handleStartNext} />}
                  {hub.competitions.map((c) => (
                    <CompetitionCard
                      key={c.id}
                      comp={c}
                      myClub={hub.career.club_id}
                      playing={playing === c.id}
                      canPlay={canPlay && !playing}
                      blockedText={blockedText}
                      onPlay={handlePlay}
                      onOpen={setOpenComp}
                    />
                  ))}
                </div>
              )}

              {tab === 'offers' && (
                <OffersPanel
                  offers={hub.offers}
                  currentClub={hub.career.club_id}
                  popularity={hub.stats.popularity}
                  busyId={busyOffer}
                  onRespond={handleOffer}
                />
              )}

              {tab === 'career' && <CareerPanel stats={hub.stats} />}
            </>
          )}

          {hub && detailComp && (
            <CompetitionDetail
              seasonId={hub.season.id}
              comp={detailComp}
              myClub={hub.career.club_id}
              version={`${hub.season.matches}-${detailComp.stage}-${detailComp.status}`}
            />
          )}
        </div>

        {result && (
          <MatchResultModal
            result={result}
            onClose={closeResult}
            onOpenOffers={() => {
              closeResult()
              setOpenComp(null)
              setTab('offers')
            }}
          />
        )}
      </div>
    </AppShell>
  )
}
