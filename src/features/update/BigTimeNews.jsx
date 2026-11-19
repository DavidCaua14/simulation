import { Copy, Flame, Gavel, Gift, Store, Users, X, Zap } from 'lucide-react'
import './update.css'

// NOVIDADES (20/11/2026): modo Online aberto para todos, cartas Big Time e caixas na Loja, mercado com cópias,
// promoção relâmpago e bots no mercado. Aparece uma vez por carreira (release_news; versão em updateApi.BIGTIME_NEWS_RELEASE).
const POINTS = [
  [Flame, 'Cartas Big Time', 'Atuações históricas em cartas vermelhas, com overall acima de 105 e regularidade B. A carta chega com overall menor e você treina até o máximo.'],
  [Store, 'Caixas na Loja', 'Toda semana chega uma caixa nova, com tempo contado. Cada giro tira um prêmio: Big Time, cartas base ou itens.'],
  [Copy, 'Mercado com cópias', 'O mesmo jogador pode estar em vários clubes. Depois de comprado, ele volta ao mercado mais tarde para outros técnicos.'],
  [Zap, 'Promoção relâmpago', 'Algumas vezes por dia, um leilão de 30 minutos com lance inicial menor. Fique de olho nos avisos.'],
  [Gavel, 'Mercado mais disputado', 'Os clubes da máquina também dão lances e anunciam jogadores.'],
  [Users, 'Elenco sem limite', 'Monte o elenco do tamanho que quiser.'],
]

export default function BigTimeNews({ onClose, onOpenSeasons, replay = false }) {
  return (
    <div className="uw" role="dialog" aria-modal="true" aria-label="Novidades: Big Time e modo Online para todos">
      <div className="uw-card">
        <header className="uw-head">
          <div>
            <small>{replay ? 'Novidades' : 'Atualização'}</small>
            <h2>Modo Online para todos e Big Time</h2>
          </div>
          <button type="button" className="uw-x" onClick={onClose} aria-label="Fechar">
            <X size={18} />
          </button>
        </header>
        <div className="uw-body">
          <p className="uw-lead"><Gift size={16} /> O modo Online está aberto para todos: assuma seu clube, dispute as Séries e o mercado ao vivo.</p>
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
          <button type="button" className="gx-btn" onClick={onOpenSeasons || onClose}>Ver a caixa Big Time</button>
        </footer>
      </div>
    </div>
  )
}
