import { CalendarClock, Coins, Gavel, RotateCcw, ShieldCheck, Trophy, X } from 'lucide-react'
import './update.css'

// ANÚNCIO: nova era (13/11/2026). Temporadas recomeça em 2026, premiação em moedas pelo futebol real, ranking pelo
// modo Online e novo ritmo da liga. Aparece uma vez por carreira (release_news; versão em updateApi.NEW_ERA_NEWS_RELEASE).
const SECTIONS = [
  ['Temporadas recomeçou em 2026', RotateCcw, [
    'O modo está liberado para todos. Você começa sem clube, com três propostas de times da Série B.',
    'Nível, XP, moedas, diamantes e a sala de troféus continuam com você.',
    'Quem tinha títulos recebeu moedas na caixa de mensagens.',
    'Jogadores não envelhecem nem se aposentam, e não existe mais insatisfação de elenco.',
    'Não dá mais para investir moedas no clube do modo Temporadas.',
  ]],
  ['Jogue Temporadas, invista no Online', Coins, [
    'Brasileirão: 1 milhão ao campeão, 950 mil ao vice, até 340 mil ao 16º.',
    'Copa do Brasil: até 1,5 milhão. Libertadores: até 2,5 milhões. Série B: 150 mil ao campeão.',
    'Vitória: 1.000 na Série B, 2.500 no Brasileirão, até 4.000 na Libertadores.',
    '1 moeda vale $ 1 no caixa do seu clube no modo Online.',
  ]],
  ['Liga Online', CalendarClock, [
    'Uma rodada a cada 7 horas.',
    'Vitória rende 5.000 moedas; empate, 1.500.',
    'Fim de temporada: 500 mil moedas ao campeão, 400 mil ao vice, até 40 mil ao 12º. Copa: 250 mil.',
    'Os prêmios vão para a sua conta: você decide se investe no clube.',
  ]],
  ['Ranking', Trophy, [
    'O ranking geral foi zerado e só a Liga Online pontua.',
    'Vencer outro técnico vale 50 pontos; perder para outro técnico tira 15.',
    'Também contam gols, jogos sem sofrer gol, preparação completa, colocação na liga e copa.',
  ]],
  ['Mercado', Gavel, [
    'Aberto das 08:00 às 18:30, todos os dias.',
    'Destaque às 11:00 e 16:00; lenda às 12:00 e 17:00. Bots não disputam essas cartas.',
    'Você pode leiloar um jogador do seu elenco por uma hora.',
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
