import { CalendarClock, FileSignature } from 'lucide-react'
import { renewalLabel, useOpenRenewals } from '../hooks/useOpenRenewals'

// Início: mostra que as propostas de renovação foram feitas e que dá para seguir o calendário (inclusive virar a
// temporada) sem perder o atleta — a negociação continua e o vínculo fica garantido até a resposta.
export default function RenewalsCard({ version, finished, onOpen }) {
  const list = useOpenRenewals(version)
  if (!list.length) return null
  const waitingYou = list.some((n) => renewalLabel(n).mine)
  return (
    <section className="rn-card" aria-label="Renovações em andamento">
      <header>
        <FileSignature size={18} />
        <h2>{list.length === 1 ? 'Renovação em andamento' : `${list.length} renovações em andamento`}</h2>
      </header>
      <ul>
        {list.map((n) => {
          const l = renewalLabel(n)
          return (
            <li key={n.id} className={l.mine ? 'is-mine' : ''}>
              <b>{n.player_name}</b>
              <span>{l.text}</span>
            </li>
          )
        })}
      </ul>
      <p className="rn-ok">
        <CalendarClock size={15} />
        <span>
          {waitingYou
            ? 'Há uma resposta esperando por você. As demais continuam sozinhas.'
            : finished
              ? 'Pode avançar para a próxima temporada: as negociações continuam e o contrato fica garantido até a resposta do atleta.'
              : 'Pode seguir o calendário: as negociações continuam e o contrato fica garantido até a resposta do atleta.'}
        </span>
      </p>
      <button type="button" className="sn-link" onClick={onOpen}>Ver negociações</button>
    </section>
  )
}
