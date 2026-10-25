import { ArrowLeftRight, Trophy } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import RoundResults from './RoundResults'
import { COMP_NAME, roundTitle } from '../utils/seasonUtils'

// Resumo do "Avançar": o que aconteceu nos dias sem jogo do seu clube (e as propostas que chegaram).
export default function ParallelDigest({ digest, myClub, onClose, onOffers, onOpenReport }) {
  const rounds = digest.rounds || []
  const offers = digest.offers || []
  return (
    <div className="sn-overlay" role="dialog" aria-modal="true" aria-label="Resumo dos dias">
      <div className="sn-modal">
        <header className="sn-modal-head">
          <span>
            <small>{digest.days > 1 ? `${digest.days} dias se passaram` : 'Um dia se passou'}</small>
            <b>Enquanto isso…</b>
          </span>
        </header>

        {offers.length > 0 && (
          <section className="dg-offers">
            {offers.map((o) => (
              <button key={o.id} type="button" className="sn-offer-alert" onClick={onOffers}>
                <ArrowLeftRight size={18} />
                <ClubCrest clubId={o.club_id} size={26} />
                <span>
                  <b>{getClubById(o.club_id)?.name}</b> fez uma proposta para você treinar o clube! Toque para ver.
                </span>
              </button>
            ))}
          </section>
        )}

        {rounds.length === 0 && offers.length === 0 && <p className="sn-muted sn-center">Dia tranquilo, sem jogos e sem propostas. O telefone não tocou.</p>}

        {rounds.map((r) => (
          <section key={`${r.competition}-${r.stage}-${r.round}`} className="sn-digest-round">
            <RoundResults matches={r.results} myClub={myClub} title={`${COMP_NAME[r.competition]} · ${roundTitle(r.stage, r.round)}`} onOpen={onOpenReport} />
            {r.finished && (
              <div className="sn-compdone">
                <Trophy size={18} />
                <div>
                  <b>{COMP_NAME[r.competition]} encerrada</b>
                  <span>
                    Campeão: <ClubCrest clubId={r.champion} size={14} /> {getClubById(r.champion)?.name}
                  </span>
                  {r.player_result && <span>Sua campanha: {r.player_result}</span>}
                </div>
              </div>
            )}
          </section>
        ))}

        {digest.season_finished && (
          <div className="sn-compdone season">
            <Trophy size={18} />
            <div>
              <b>Temporada encerrada!</b>
              <span>Veja o balanço e comece a próxima temporada.</span>
            </div>
          </div>
        )}

        <button type="button" className="gx-btn sn-continue" onClick={onClose}>
          {digest.season_finished ? 'Ver balanço da temporada' : 'Continuar'}
        </button>
      </div>
    </div>
  )
}
