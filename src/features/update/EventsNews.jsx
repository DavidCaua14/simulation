import { useState } from 'react'
import { ChevronLeft, ChevronRight, X } from 'lucide-react'
import GameIcon from '../../components/ui/GameIcon'
import './update.css'

// NOVIDADES DOS EVENTOS — aparece uma vez por carreira na primeira entrada depois da atualização
// (o banco guarda quem já viu: release_news; versão em updateApi.EVENTS_NEWS_RELEASE). Pode ser revista no Perfil → Novidades.

const STREAK = [
  { day: 1, coins: '1.000' },
  { day: 2, coins: '2.000' },
  { day: 3, coins: '3.000', extra: '+1 energia' },
  { day: 4, coins: '4.000' },
  { day: 5, coins: '5.000', gems: 120 },
  { day: 6, coins: '6.000', extra: '+1 energia' },
  { day: 7, coins: '7.000', gems: 410, extra: '+2 energia' },
]

export default function EventsNews({ onClose, onOpenEvents, replay = false }) {
  const [page, setPage] = useState(0)
  const pages = ['Sequência turbinada', 'Eventos da semana', 'Maratona de Novembro']
  const last = page === pages.length - 1

  return (
    <div className="uw" role="dialog" aria-modal="true" aria-label="Novidades dos eventos">
      <div className="uw-card">
        <header className="uw-head">
          <div>
            <small>{replay ? 'Novidades dos eventos' : 'Novidade nos eventos!'}</small>
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
            <>
              <p className="uw-lead">Jogue uma partida ou faça um palpite por dia e resgate a recompensa na tela de Eventos. As moedas sobem todo dia.</p>
              <ul className="uw-streak">
                {STREAK.map((d) => (
                  <li key={d.day} className={d.gems ? 'is-big' : ''}>
                    <small>Dia {d.day}</small>
                    <b><GameIcon name="coins" size={16} /> {d.coins}</b>
                    {d.gems && <b className="uw-gems"><GameIcon name="diamond" size={16} /> {d.gems} diamantes</b>}
                    {d.extra && <span>{d.extra}</span>}
                  </li>
                ))}
              </ul>
              <p className="uw-lead">Pulou um dia? A sequência recomeça do Dia 1.</p>
            </>
          )}

          {page === 1 && (
            <>
              <section className="uw-sec">
                <h3><GameIcon name="coins" size={20} /> Diários com mais moedas</h3>
                <ul className="uw-list">
                  <li><b>Entre em campo</b>: 1 partida → 1.000 moedas</li>
                  <li><b>Vitória do dia</b>: 1 vitória → 2.000 moedas + energia</li>
                  <li><b>Ataque afiado</b> (3 gols) e <b>Muralha do dia</b> (1 jogo sem sofrer gol): 1.500 moedas cada</li>
                  <li><b>Rotina de campeão</b>: jogue 5 e vença 3 → 4.000 moedas + diamantes + energia</li>
                  <li><b>Palpite do dia</b>: 1 palpite → 1.000 moedas</li>
                </ul>
              </section>
              <section className="uw-sec">
                <h3><GameIcon name="crown" size={20} /> Semanais: de segunda a domingo</h3>
                <ul className="uw-list">
                  <li><b>Semana vencedora</b> em 3 degraus: Bronze (5 vitórias), Prata (20) e Ouro (50 vitórias + 120 gols). Ouro paga 40.000 moedas e 60 diamantes.</li>
                  <li><b>Caça-gigantes</b>: vença 5 times de força 80+ → 20.000 moedas e 30 diamantes.</li>
                  <li><b>Artilharia</b> (60 gols), <b>Defesa de aço</b> (15 jogos sem sofrer gol) e <b>Palpiteiro</b> (10 palpites).</li>
                </ul>
                <p>O progresso conta sozinho enquanto você joga. Toda segunda-feira começa uma semana nova.</p>
              </section>
            </>
          )}

          {page === 2 && (
            <section className="uw-sec">
              <h3><GameIcon name="highlight" size={20} /> Evento especial até domingo</h3>
              <p>Jogue <b>40 partidas</b>, vença <b>25</b> e marque <b>70 gols</b> até domingo (15/11).</p>
              <ul className="uw-gifts">
                <li><GameIcon name="coins" size={30} /><b>50.000</b><small>moedas</small></li>
                <li><GameIcon name="diamond" size={30} /><b>100</b><small>diamantes</small></li>
                <li><GameIcon name="energy" size={30} /><b>15</b><small>energia bônus</small></li>
                <li><GameIcon name="crown" size={30} /><b>Coroa</b><small>emblema exclusivo</small></li>
              </ul>
            </section>
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
            <button type="button" className="gx-btn" onClick={onOpenEvents || onClose}>
              Ver eventos
            </button>
          )}
        </footer>
      </div>
    </div>
  )
}
