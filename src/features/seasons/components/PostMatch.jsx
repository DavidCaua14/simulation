import { useEffect, useState } from 'react'
import { ArrowLeftRight, Coins, Sparkles, Star, Target, Trophy, Users } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { tierOf } from '../../cards/data/tiers'
import { getClubById } from '../../club/data/clubs'
import RoundResults from './RoundResults'
import StandingsTable from './StandingsTable'
import Bracket from './Bracket'
import { standingsFrom } from '../utils/seasonSelectors'
import { COMP_NAME, RESULT_LABEL, describeMatch, ratingTone } from '../utils/seasonUtils'

function performanceText(rating, goals, assists) {
  if (rating >= 8.5) return 'Atuação de craque! A torcida foi à loucura.'
  if (goals + assists >= 2) return 'Participou de vários gols. Jogão!'
  if (rating >= 7) return 'Boa partida, decisivo no setor.'
  if (rating >= 6) return 'Partida regular, cumpriu a função.'
  return 'Dia difícil. Siga trabalhando.'
}

// Tela de PÓS-JOGO em 3 abas: Resumo (placar revelado + seu desempenho), Rodada (todos os placares)
// e Classificação (ou chaveamento, no mata-mata). Tudo vem do resultado e dos dados já carregados.
export default function PostMatch({ result, byComp, onClose, onOpenOffers, box, onOpenBox }) {
  const [shown, setShown] = useState({ h: 0, a: 0 })
  const [done, setDone] = useState(false)
  const [tab, setTab] = useState('summary')

  useEffect(() => {
    let h = 0
    let a = 0
    let finish
    const id = setInterval(() => {
      if (h < result.home_goals) h += 1
      if (a < result.away_goals) a += 1
      setShown({ h, a })
      if (h >= result.home_goals && a >= result.away_goals) {
        clearInterval(id)
        finish = setTimeout(() => setDone(true), 450)
      }
    }, 600)
    return () => {
      clearInterval(id)
      clearTimeout(finish)
    }
  }, [result])

  const skip = () => {
    setShown({ h: result.home_goals, a: result.away_goals })
    setDone(true)
  }

  const home = getClubById(result.home)
  const away = getClubById(result.away)
  const { goals, assists, rating } = result.player
  const mineIsHome = result.home === result.my_club
  const pens = result.home_pens != null ? `Pênaltis: ${result.home_pens} × ${result.away_pens}` : null
  const qualified = result.tie_winner ? getClubById(result.tie_winner) : null
  const isTable = result.stage === 'league' || result.stage === 'group'
  const roundMatches = [
    { home: result.home, away: result.away, hg: result.home_goals, ag: result.away_goals, group: result.group, mine: true },
    ...(result.round_results || []),
  ]
  const tableRows = isTable ? standingsFrom(byComp[result.competition] || [], result.group || null) : []

  return (
    <div className="sn-overlay" role="dialog" aria-modal="true" aria-label="Resultado da partida">
      <div className="sn-modal">
        <header className="sn-modal-head">
          <small>{COMP_NAME[result.competition]}</small>
          <b>{describeMatch(result)}</b>
        </header>

        <div className="sn-board">
          <div className={`sn-board-team ${mineIsHome ? 'is-mine' : ''}`}>
            <ClubCrest clubId={result.home} size={58} />
            <span>{home?.name}</span>
          </div>
          <div className="sn-board-score">
            <b>{shown.h}</b>
            <i>×</i>
            <b>{shown.a}</b>
          </div>
          <div className={`sn-board-team ${!mineIsHome ? 'is-mine' : ''}`}>
            <ClubCrest clubId={result.away} size={58} />
            <span>{away?.name}</span>
          </div>
        </div>

        {!done && (
          <button type="button" className="sn-skip" onClick={skip}>
            Pular
          </button>
        )}

        {done && (
          <div className="sn-reveal">
            <div className={`sn-banner r-${result.result}`}>{RESULT_LABEL[result.result]}</div>
            {pens && <p className="sn-note">{pens}</p>}
            {qualified && result.stage !== 'final' && result.leg === 2 && (
              <p className="sn-note">
                Classificado: <b>{qualified.name}</b>
              </p>
            )}

            <div className="sn-seg">
              <button type="button" className={tab === 'summary' ? 'is-on' : ''} onClick={() => setTab('summary')}>
                Resumo
              </button>
              <button type="button" className={tab === 'round' ? 'is-on' : ''} onClick={() => setTab('round')}>
                Rodada
              </button>
              <button type="button" className={tab === 'table' ? 'is-on' : ''} onClick={() => setTab('table')}>
                {isTable ? 'Tabela' : 'Mata-mata'}
              </button>
            </div>

            {tab === 'summary' && (
              <>
                <section className="sn-perf">
                  <div className={`sn-rating ${ratingTone(rating)}`}>
                    <b>{Number(rating).toFixed(1)}</b>
                    <small>NOTA</small>
                  </div>
                  <div className="sn-perf-body">
                    <strong>Seu desempenho</strong>
                    <p>{performanceText(rating, goals, assists)}</p>
                    <div className="sn-perf-stats">
                      <span>
                        <Target size={14} /> {goals} gol{goals === 1 ? '' : 's'}
                      </span>
                      <span>
                        <Users size={14} /> {assists} assist.
                      </span>
                    </div>
                  </div>
                </section>

                <div className="sn-rewards">
                  <span className="xp">+{result.rewards.xp} XP</span>
                  <span className="coins">
                    <Coins size={13} /> +{result.rewards.coins}
                  </span>
                  <span className={`fame ${result.rewards.popularity < 0 ? 'neg' : ''}`}>
                    <Star size={13} fill="currentColor" /> {result.rewards.popularity > 0 ? '+' : ''}
                    {result.rewards.popularity}
                  </span>
                </div>

                {box && (
                  <button type="button" className="sn-boxwin" style={{ '--tier': tierOf(box.tier).color, '--glow': tierOf(box.tier).glow }} onClick={onOpenBox}>
                    <img src={tierOf(box.tier).closed} alt="" draggable="false" />
                    <span>
                      <b>Você ganhou uma caixa {tierOf(box.tier).label}!</b>
                      <small>Toque para abrir agora · ou abra depois na caixa de entrada</small>
                    </span>
                  </button>
                )}

                {result.level_up && (
                  <div className="sn-levelup">
                    <Sparkles size={18} /> SUBIU DE NÍVEL! Agora você é nível <b>{result.new_level}</b>
                  </div>
                )}

                {result.competition_finished && (
                  <div className="sn-compdone">
                    <Trophy size={18} />
                    <div>
                      <b>Campeonato encerrado</b>
                      <span>
                        Sua campanha: {result.competition_result || '—'}
                        {result.competition_bonus ? ` · +${result.competition_bonus.xp} XP · +${result.competition_bonus.coins} moedas` : ''}
                      </span>
                      {result.champion && <span>Campeão: {getClubById(result.champion)?.name}</span>}
                    </div>
                  </div>
                )}

                {result.offer && (
                  <button type="button" className="sn-offer-alert" onClick={onOpenOffers}>
                    <ArrowLeftRight size={18} />
                    <span>
                      Nova proposta do <b>{getClubById(result.offer.club_id)?.name}</b>! Toque para ver.
                    </span>
                  </button>
                )}

                {result.season_finished && (
                  <div className="sn-compdone season">
                    <Trophy size={18} />
                    <div>
                      <b>Temporada encerrada!</b>
                      <span>Veja o resumo e inicie a próxima temporada.</span>
                    </div>
                  </div>
                )}
              </>
            )}

            {tab === 'round' && <RoundResults matches={roundMatches} myClub={result.my_club} title="Jogos da rodada" />}

            {tab === 'table' &&
              (isTable ? (
                <StandingsTable rows={tableRows} myClub={result.my_club} mode={result.stage === 'group' ? 'group' : 'league'} />
              ) : (
                <Bracket fixtures={byComp[result.competition] || []} myClub={result.my_club} />
              ))}

            <button type="button" className="sn-continue" onClick={onClose}>
              {result.season_finished ? 'Ver resumo da temporada' : 'Continuar'}
            </button>
          </div>
        )}
      </div>
    </div>
  )
}
