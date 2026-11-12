import { Crown, Dumbbell, Gavel, Megaphone, Swords, Trophy, X } from 'lucide-react'
import './update.css'

// ANÚNCIO: o modo Online abriu para todos. Aparece uma vez por carreira (release_news; versão em
// updateApi.ONLINE_NEWS_RELEASE). O botão leva direto ao modo.
const POINTS = [
  [Swords, 'Liga com outros técnicos', 'Um jogo por dia, em horário real, de manhã ou à tarde.'],
  [Crown, 'Jogadores reais e lendas', 'Monte o elenco com três craques e dispute cartas especiais.'],
  [Gavel, 'Leilões ao vivo', 'Todo dia tem um destaque e uma lenda. O maior lance leva.'],
  [Megaphone, 'Você é o técnico', 'Mude o time durante o jogo e fale com o elenco no intervalo.'],
  [Dumbbell, 'Treinos e preparação', 'Mini-games evoluem os jogadores e dão bônus em campo.'],
]

export default function OnlineNews({ onClose, onOpenSeasons, replay = false }) {
  return (
    <div className="uw" role="dialog" aria-modal="true" aria-label="Novidade: modo Online">
      <div className="uw-card">
        <header className="uw-head">
          <div>
            <small>{replay ? 'Novidade' : 'Novo modo de jogo'}</small>
            <h2>O modo Online chegou</h2>
          </div>
          <button type="button" className="uw-x" onClick={onClose} aria-label="Fechar">
            <X size={18} />
          </button>
        </header>
        <div className="uw-body">
          <p className="uw-lead"><Trophy size={16} /> A Liga Online está aberta. Entre hoje, assuma seu clube e comece a disputa.</p>
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
          <button type="button" className="gx-btn" onClick={onOpenSeasons || onClose}>Jogar agora</button>
        </footer>
      </div>
    </div>
  )
}
