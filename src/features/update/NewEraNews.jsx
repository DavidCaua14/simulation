import { CalendarClock, Coins, Gavel, RotateCcw, ShieldCheck, Trophy, X } from 'lucide-react'
import './update.css'

// ANÚNCIO: nova era (13/11/2026). Temporadas recomeça em 2026, premiação em moedas pelo futebol real, ranking pelo
// modo Online e novo ritmo da liga. Aparece uma vez por carreira (release_news; versão em updateApi.NEW_ERA_NEWS_RELEASE).
const SECTIONS = [
  ['Temporadas recomeçou em 2026', RotateCcw, [
    'Todo mundo volta ao primeiro dia: técnico sem clube, três propostas da Série A, elencos originais.',
    'Nível, XP, moedas, diamantes e a sala de troféus continuam com você.',
    'Cada título da sua história virou moedas: o prêmio está na sua caixa de mensagens.',
    'Jogadores não envelhecem nem se aposentam, e não existe mais insatisfação de elenco.',
  ]],
  ['Premiação em moedas', Coins, [
    'Brasileirão: 1 milhão ao campeão, 950 mil ao vice, até 340 mil ao 16º.',
    'Copa do Brasil: até 1,5 milhão. Libertadores: até 2,5 milhões.',
    'Cada vitória rende de 2.500 a 4.000 moedas; empate também paga.',
    'Use as moedas no modo Online: 1 moeda vale $ 1 no caixa do seu clube.',
  ]],
  ['Ranking pelo modo Online', Trophy, [
    'O ranking geral foi zerado. Só a Liga Online pontua.',
    'Vitórias, gols, jogos sem sofrer gol, preparação completa, colocação na liga e copa.',
  ]],
  ['Liga Online mais rápida', CalendarClock, [
    'Uma rodada a cada 7 horas.',
    'Vitória rende 15 moedas na conta; empate, 5.',
  ]],
  ['Mercado', Gavel, [
    'Aberto das 08:00 às 18:30, todos os dias.',
    'Destaque e lenda novos a cada 5 horas. Bots não disputam essas cartas.',
    'Agora você pode leiloar um jogador do seu elenco por uma hora.',
  ]],
]

export default function NewEraNews({ onClose, onOpenSeasons, replay = false }) {
  return (
    <div className="uw" role="dialog" aria-modal="true" aria-label="Novidade: nova era">
      <div className="uw-card">
        <header className="uw-head">
          <div>
            <small>{replay ? 'Novidade' : 'Atualização'}</small>
            <h2>Nova era</h2>
          </div>
          <button type="button" className="uw-x" onClick={onClose} aria-label="Fechar">
            <X size={18} />
          </button>
        </header>
        <div className="uw-body">
          <p className="uw-lead"><ShieldCheck size={16} /> Seu nível, suas moedas e suas taças estão guardados.</p>
          {SECTIONS.map(([title, Icon, items]) => (
            <section className="uw-sec" key={title}>
              <h3><Icon size={15} /> {title}</h3>
              <ul className="uw-list">
                {items.map((t) => <li key={t}>{t}</li>)}
              </ul>
            </section>
          ))}
        </div>
        <footer className="uw-foot">
          <button type="button" className="gx-btn-ghost" onClick={onClose}>Depois</button>
          <button type="button" className="gx-btn" onClick={onOpenSeasons || onClose}>Começar</button>
        </footer>
      </div>
    </div>
  )
}
