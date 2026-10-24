import { Sparkles, Trophy } from 'lucide-react'
import { getClubById } from '../../club/data/clubs'
import RoundResults from './RoundResults'
import { COMP_NAME, roundTitle } from '../utils/seasonUtils'

// Resumo do "Próximo": o que aconteceu nos outros campeonatos enquanto seu clube folgava.
export default function ParallelDigest({ digest, myClub, onClose }) {
  return (
    <div className="sn-overlay" role="dialog" aria-modal="true" aria-label="Resumo dos outros campeonatos">
      <div className="sn-modal">
        <header className="sn-modal-head">
          <span>
            <small>Enquanto isso…</small>
            <b>Outros campeonatos</b>
          </span>
        </header>

        {digest.rounds.map((r) => (
          <section key={`${r.competition}-${r.stage}-${r.round}`} className="sn-digest-round">
            <RoundResults matches={r.results} myClub={myClub} title={`${COMP_NAME[r.competition]} · ${roundTitle(r.stage, r.round)}`} />
            {r.finished && (
              <div className="sn-compdone">
                <Trophy size={18} />
                <div>
                  <b>{COMP_NAME[r.competition]} encerrada</b>
                  <span>Campeão: {getClubById(r.champion)?.name}</span>
                  {r.player_result && (
                    <span>
                      Sua campanha: {r.player_result}
                      {r.bonus_xp > 0 ? ` · +${r.bonus_xp} XP · +${r.bonus_coins} moedas` : ''}
                    </span>
                  )}
                </div>
              </div>
            )}
          </section>
        ))}

        {digest.level_up && (
          <div className="sn-levelup">
            <Sparkles size={18} /> SUBIU DE NÍVEL! Agora você é nível <b>{digest.new_level}</b>
          </div>
        )}
        {digest.season_finished && (
          <div className="sn-compdone season">
            <Trophy size={18} />
            <div>
              <b>Temporada encerrada!</b>
              <span>Veja o resumo e inicie a próxima temporada.</span>
            </div>
          </div>
        )}

        <button type="button" className="gx-btn sn-continue" onClick={onClose}>
          {digest.season_finished ? 'Ver resumo da temporada' : 'Continuar'}
        </button>
      </div>
    </div>
  )
}
