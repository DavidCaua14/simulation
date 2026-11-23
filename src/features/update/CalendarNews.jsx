import { CalendarClock, HeartPulse, Landmark, ListOrdered, Moon, Trophy, X } from 'lucide-react'
import './update.css'

// NOVIDADES (24/11/2026): novo calendário do Online (quatro jogos por dia, fila por campeonato, copa às 20:30) e a
// Reserva do clube (caixa do recomeço de volta ao Online). Aparece uma vez por carreira (versão em updateApi.CALENDAR_NEWS_RELEASE).
const POINTS = [
  [CalendarClock, 'Quatro jogos por dia', 'A liga agora tem quatro rodadas por dia, para todas as séries: 08:00, 11:30, 15:00 e 18:40. A temporada fica bem mais curta.'],
  [ListOrdered, 'Jogos em sequência', 'Em cada campeonato, no máximo duas partidas acontecem ao mesmo tempo, sempre da mesma rodada. Quando uma acaba, a próxima começa no minuto seguinte.'],
  [Trophy, 'Copa à noite', 'A Copa Online virou o quinto jogo do dia, às 20:30, para quem ainda está nela.'],
  [Moon, 'Sem jogos de madrugada', 'Nenhuma partida entre 17:30 e 18:40, e nada depois da meia-noite.'],
  [HeartPulse, 'Recuperação mais rápida', 'Os jogadores recuperam 10 de condição por hora (antes 6), mais o bônus do departamento médico. Mesmo assim, rodar o elenco ajuda.'],
  [Landmark, 'Reserva do clube', 'O caixa do Online que foi para o modo Temporadas no recomeço voltou para o Online. Ele entra no caixa aos poucos: 10% por dia, em 10 dias. Acompanhe em Clube › Finanças.'],
]

export default function CalendarNews({ onClose, onOpenSeasons, replay = false }) {
  return (
    <div className="uw" role="dialog" aria-modal="true" aria-label="Novidades: novo calendário do Online e Reserva do clube">
      <div className="uw-card">
        <header className="uw-head">
          <div>
            <small>{replay ? 'Novidades' : 'Atualização'}</small>
            <h2>Novo calendário do Online</h2>
          </div>
          <button type="button" className="uw-x" onClick={onClose} aria-label="Fechar">
            <X size={18} />
          </button>
        </header>
        <div className="uw-body">
          <p className="uw-lead"><CalendarClock size={16} /> Mais jogos por dia, rodadas mais rápidas e o caixa do recomeço de volta ao seu clube Online.</p>
          <section className="uw-sec">
            <ul className="uw-list">
              {POINTS.map(([Icon, title, text]) => (
                <li key={title}><Icon size={15} /> <b>{title}</b>: {text}</li>
              ))}
            </ul>
          </section>
        </div>
        <footer className="uw-foot">
          <button type="button" className="gx-btn-ghost" onClick={onClose}>Depois</button>
          <button type="button" className="gx-btn" onClick={onOpenSeasons || onClose}>Ver meus jogos</button>
        </footer>
      </div>
    </div>
  )
}
