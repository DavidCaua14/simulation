import { FastForward } from 'lucide-react'
import { COMP_NAME, roundTitle } from '../utils/seasonUtils'

// Dia de OUTRO campeonato: seu clube não joga. O botão "Próximo" simula essas rodadas (sem gastar energia)
// e para na próxima partida do seu clube.
export default function FreeRoundCard({ event, calendar, advancing, onAdvance }) {
  // quantas rodadas seguidas o "Próximo" vai simular (eventos "free" no começo do calendário)
  const batch = []
  for (const e of calendar) {
    if (e.kind !== 'free') break
    batch.push(e)
  }
  const first = batch[0] || event
  const stage = first.stage ?? event.stage
  const round = first.round ?? event.round

  return (
    <section className={`sn-nm sn-free card tone-${event.competition || first.comp}`}>
      <header>
        <small>Dia de rodada</small>
        <b>{COMP_NAME[event.competition || first.comp]}</b>
        <span>{roundTitle(stage, round)}</span>
      </header>

      <p className="sn-free-text">
        Seu clube <b>não joga</b> nesta rodada. Toque em <b>Próximo</b> para os outros campeonatos acontecerem.
      </p>

      {batch.length > 1 && (
        <ul className="sn-free-list">
          {batch.map((e) => (
            <li key={`${e.comp}-${e.stage}-${e.round}`}>
              <b>{COMP_NAME[e.comp]}</b>
              <span>{e.label}</span>
            </li>
          ))}
        </ul>
      )}

      <button type="button" className="sn-play sn-play-big sn-next-btn" disabled={advancing} onClick={onAdvance}>
        {advancing ? (
          'Simulando…'
        ) : (
          <>
            Próximo <FastForward size={18} fill="currentColor" />
            <span className="sn-cost free">sem energia</span>
          </>
        )}
      </button>
      <small className="sn-nm-note">Vale para {batch.length > 1 ? `as ${batch.length} rodadas` : 'esta rodada'}. Em seguida você volta a jogar pelo seu clube.</small>
    </section>
  )
}
