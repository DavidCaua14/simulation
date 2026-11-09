import { useState } from 'react'
import { ChevronLeft, ChevronRight, Users, X } from 'lucide-react'
import MoodFace from '../seasons/components/MoodFace'
import './update.css'

// NOVIDADES: moral e elenco. Aparece uma vez por carreira (release_news; versão em updateApi.MORALE_NEWS_RELEASE).
const FACES = [
  [90, 'Satisfeito', 'moral 80% ou mais. Rende o máximo (até um pouco acima).'],
  [70, 'Neutro', 'moral de 60% a 79%. Já quer mais espaço e começa a render menos.'],
  [45, 'Insatisfeito', 'moral de 35% a 59%. Rende bem menos e pesa no vestiário.'],
  [20, 'Revoltado', 'moral abaixo de 35%. Rende muito menos e pode pedir para sair.'],
]

export default function MoraleNews({ onClose, onOpenSeasons, replay = false }) {
  const [page, setPage] = useState(0)
  const pages = ['Gire o elenco', 'Como ver a satisfação']
  const last = page === pages.length - 1

  return (
    <div className="uw" role="dialog" aria-modal="true" aria-label="Novidades: moral e elenco">
      <div className="uw-card">
        <header className="uw-head">
          <div>
            <small>{replay ? 'Novidades: moral e elenco' : 'Dica da atualização'}</small>
            <h2>{pages[page]}</h2>
          </div>
          <button type="button" className="uw-x" onClick={onClose} aria-label="Fechar">
            <X size={18} />
          </button>
        </header>
        <div className="uw-dots" aria-hidden="true">
          {pages.map((p, i) => <i key={p} className={i === page ? 'is-on' : ''} />)}
        </div>

        <div className="uw-body">
          {page === 0 && (
            <div className="uw-how">
              <section>
                <h3><Users size={18} /> Use todos os jogadores disponíveis</h3>
                <p>Faça <b>rodízio</b>: dê minutos a titulares, reservas e a quem está fora da lista. Jogador sem espaço perde moral, e moral baixa faz o time render menos. Elenco satisfeito rende mais e vence mais.</p>
              </section>
              <section>
                <h3>Diretoria de olho no elenco</h3>
                <p>Em <b>Carreira → Desempenho na temporada</b>, ao lado de Diretoria e Torcida, agora aparece <b>Elenco</b>: mostra como está a sua relação com os jogadores. Se ele cair, a diretoria avisa. Uma eliminação com o elenco insatisfeito pode custar o seu cargo e pontos no ranking.</p>
              </section>
            </div>
          )}

          {page === 1 && (
            <>
              <p className="uw-lead">Na tela de Time, na escalação e no pré-jogo, cada jogador (titulares, banco e não relacionados) tem um rostinho colorido:</p>
              <section className="uw-sec">
                <ul className="uw-list">
                  {FACES.map(([m, label, text]) => (
                    <li key={label}>
                      <MoodFace morale={m} size={13} /> <b>{label}</b>: {text}
                    </li>
                  ))}
                </ul>
                <p>Toque ou passe o mouse no rostinho para ver a moral exata. No Elenco, a coluna de moral mostra a porcentagem e a seta da última semana.</p>
              </section>
            </>
          )}
        </div>

        <footer className="uw-foot">
          <button type="button" className="gx-btn-ghost" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
            <ChevronLeft size={16} /> Voltar
          </button>
          {!last ? (
            <button type="button" className="gx-btn" onClick={() => setPage((p) => p + 1)}>
              Próximo <ChevronRight size={16} />
            </button>
          ) : (
            <button type="button" className="gx-btn" onClick={onOpenSeasons || onClose}>
              Ver meu elenco
            </button>
          )}
        </footer>
      </div>
    </div>
  )
}
