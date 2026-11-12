import { Eye, Megaphone, Shirt, UserRound, X } from 'lucide-react'
import './update.css'

// TUTORIAL (13/11/2026): escalações no vestiário e na partida, e a ficha do jogador no elenco do modo Online.
// Aparece uma vez por carreira (release_news; versão em updateApi.LINEUPS_NEWS_RELEASE).
const STEPS = [
  ['Escalações no vestiário', Shirt, [
    'Abra o seu jogo antes do pontapé inicial e toque em "Ver escalações".',
    'A aba "Meu time" mostra os seus onze no campo; "Adversário" mostra os onze do outro técnico e a formação dele.',
  ]],
  ['Adversário durante a partida', Eye, [
    'Com a bola rolando, toque em "Adversário", ao lado de Time e Instruções.',
    'A tela se atualiza sozinha: se o outro técnico trocar um jogador, a mudança aparece.',
  ]],
  ['Ficha do jogador', UserRound, [
    'Em Elenco > Jogadores, toque em um atleta.',
    'A ficha mostra a nota atual, até onde ele pode chegar, valor, salário e contrato.',
    'Na mesma tela você leiloa, renova ou dispensa o jogador.',
  ]],
  ['Novidades', Megaphone, [
    'Este aviso fica sempre disponível em Perfil > Novidades.',
  ]],
]

export default function LineupsNews({ onClose, onOpenSeasons, replay = false }) {
  return (
    <div className="uw" role="dialog" aria-modal="true" aria-label="Novidade: escalações e ficha do jogador">
      <div className="uw-card">
        <header className="uw-head">
          <div>
            <small>{replay ? 'Novidade' : 'Novo no modo Online'}</small>
            <h2>Escalações e ficha do jogador</h2>
          </div>
          <button type="button" className="uw-x" onClick={onClose} aria-label="Fechar">
            <X size={18} />
          </button>
        </header>
        <div className="uw-body">
          {STEPS.map(([title, Icon, items], i) => (
            <section className="uw-sec" key={title}>
              <h3><Icon size={15} /> {i + 1}. {title}</h3>
              <ul className="uw-list">
                {items.map((t) => <li key={t}>{t}</li>)}
              </ul>
            </section>
          ))}
        </div>
        <footer className="uw-foot">
          <button type="button" className="gx-btn-ghost" onClick={onClose}>Depois</button>
          <button type="button" className="gx-btn" onClick={onOpenSeasons || onClose}>Abrir o modo Online</button>
        </footer>
      </div>
    </div>
  )
}
