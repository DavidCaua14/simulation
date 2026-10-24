import { FastForward } from 'lucide-react'
import CompEmblem from '../ui/CompEmblem'
import stadium from '../../home/assets/temporadas.webp'
import { COMP_NAME, COMP_SHORT, COMP_THEME, roundTitle } from '../utils/seasonUtils'

// Dia de OUTRO campeonato: seu clube folga. "Avançar" simula essas rodadas (sem energia)
// e para na próxima partida do seu clube.
export default function FreeRoundHero({ event, calendar, advancing, onAdvance }) {
  const batch = []
  for (const e of calendar) {
    if (e.kind !== 'free') break
    batch.push(e)
  }
  const first = batch[0] || event
  const compId = event.competition || first.comp
  const t = COMP_THEME[compId]

  return (
    <section className="nm is-free" style={{ '--c1': t.c1, '--c2': t.c2 }} aria-label="Dia de rodada">
      <img className="nm-bg" src={stadium} alt="" />
      <span className="nm-shade" aria-hidden="true" />

      <header className="nm-head">
        <CompEmblem comp={compId} size={30} />
        <span className="nm-head-txt">
          <small>Dia de rodada</small>
          <b>{COMP_NAME[compId]}</b>
        </span>
        <span className="nm-round">{roundTitle(first.stage ?? event.stage, first.round ?? event.round)}</span>
      </header>

      <div className="nm-free-body">
        <p>
          Seu clube <b>folga</b> hoje. Avance para os outros campeonatos acontecerem e volte a jogar pelo seu time.
        </p>
        {batch.length > 1 && (
          <ul className="nm-free-list">
            {batch.map((e) => (
              <li key={`${e.comp}-${e.stage}-${e.round}`}>
                <CompEmblem comp={e.comp} size={16} />
                <b>{COMP_SHORT[e.comp]}</b>
                <span>{e.label}</span>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="nm-cta">
        <button type="button" className="gx-btn nm-play is-advance" disabled={advancing} onClick={onAdvance}>
          {advancing ? (
            <>
              <span className="nm-spin" /> Simulando rodada…
            </>
          ) : (
            <>
              <FastForward size={20} fill="currentColor" /> Avançar{batch.length > 1 ? ` ${batch.length} rodadas` : ''}
              <span className="nm-cost free">sem energia</span>
            </>
          )}
        </button>
        <small>Em seguida você volta a jogar pelo seu clube.</small>
      </div>
    </section>
  )
}
