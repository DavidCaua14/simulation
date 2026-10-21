import { Crown, Swords, Trophy, Zap, ChevronRight } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { STAGE_LABEL, describeMatch, ordinal, venueLabel } from '../utils/seasonUtils'

const META = {
  brasileirao: { Icon: Trophy, tone: 'green', tagline: '20 clubes · 38 rodadas' },
  copa_brasil: { Icon: Swords, tone: 'gold', tagline: 'Mata-mata · oitavas até a final' },
  libertadores: { Icon: Crown, tone: 'blue', tagline: '32 clubes · grupos + mata-mata' },
}

function TeamSide({ clubId, mine }) {
  const club = getClubById(clubId)
  return (
    <span className={`sn-side ${mine ? 'is-mine' : ''}`}>
      <ClubCrest clubId={clubId} size={44} />
      <b>{club?.name}</b>
    </span>
  )
}

// Cartão de um campeonato: situação do seu clube, próximo jogo e botão de simular.
export default function CompetitionCard({ comp, myClub, playing, canPlay, blockedText, onPlay, onOpen }) {
  const meta = META[comp.id] || META.brasileirao
  const { Icon } = meta
  const champion = comp.champion ? getClubById(comp.champion) : null

  return (
    <article className={`sn-comp card tone-${meta.tone} status-${comp.status}`}>
      <header className="sn-comp-head">
        <span className="sn-comp-icon">
          <Icon size={20} />
        </span>
        <div>
          <strong className="heading">{comp.name}</strong>
          <small>{comp.status === 'not_in' ? meta.tagline : STAGE_LABEL[comp.stage] || meta.tagline}</small>
        </div>
        {comp.table && (
          <span className="sn-pos" title="Sua posição">
            {comp.table.group ? `Gr. ${comp.table.group} · ` : ''}
            {ordinal(comp.table.pos)} · {comp.table.points} pts
          </span>
        )}
      </header>

      {comp.status === 'active' && comp.next && (
        <>
          <div className="sn-next">
            <small className="sn-next-label">Próxima partida · {describeMatch(comp.next)}</small>
            <div className="sn-versus">
              <TeamSide clubId={comp.next.home} mine={comp.next.home === myClub} />
              <span className="sn-x">×</span>
              <TeamSide clubId={comp.next.away} mine={comp.next.away === myClub} />
            </div>
            <small className="sn-venue">{venueLabel(comp.next)}</small>
          </div>

          <div className="sn-actions">
            <button type="button" className="sn-play" disabled={playing || !canPlay} onClick={() => onPlay(comp.id)}>
              {playing ? (
                'Simulando…'
              ) : canPlay ? (
                <>
                  Simular partida
                  <span className="sn-cost">
                    <Zap size={12} fill="currentColor" />1
                  </span>
                </>
              ) : (
                blockedText
              )}
            </button>
            <button type="button" className="sn-ghost" onClick={() => onOpen(comp.id)}>
              Tabela e jogos <ChevronRight size={14} />
            </button>
          </div>
          <div className="sn-progress" aria-hidden="true">
            <i style={{ width: `${comp.total ? (comp.played / comp.total) * 100 : 0}%` }} />
          </div>
          <small className="sn-progress-text">
            {comp.played} jogo{comp.played === 1 ? '' : 's'} disputado{comp.played === 1 ? '' : 's'}
          </small>
        </>
      )}

      {comp.status === 'finished' && (
        <div className="sn-done">
          {comp.player_result && (
            <p className="sn-result-line">
              Sua campanha: <b>{comp.player_result}</b>
              {(comp.bonus_xp > 0 || comp.bonus_coins > 0) && (
                <span className="sn-bonus">
                  {' '}
                  +{comp.bonus_xp} XP · +{comp.bonus_coins} moedas
                </span>
              )}
            </p>
          )}
          {champion && (
            <p className="sn-champ">
              <Trophy size={14} /> Campeão: <ClubCrest clubId={champion.id} size={18} /> <b>{champion.name}</b>
            </p>
          )}
          <button type="button" className="sn-ghost" onClick={() => onOpen(comp.id)}>
            Ver campeonato <ChevronRight size={14} />
          </button>
        </div>
      )}

      {comp.status === 'out' && (
        <div className="sn-done">
          <p className="sn-result-line">Seu clube não tem mais jogos neste campeonato.</p>
          <button type="button" className="sn-ghost" onClick={() => onOpen(comp.id)}>
            Ver campeonato <ChevronRight size={14} />
          </button>
        </div>
      )}

      {comp.status === 'not_in' && <p className="sn-muted">Seu clube não disputa este campeonato nesta temporada.</p>}
    </article>
  )
}
