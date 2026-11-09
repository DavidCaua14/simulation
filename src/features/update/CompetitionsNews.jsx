import { useState } from 'react'
import { ChevronLeft, ChevronRight, X } from 'lucide-react'
import GameIcon from '../../components/ui/GameIcon'
import CompEmblem from '../seasons/ui/CompEmblem'
import './update.css'

// NOVIDADES DOS CAMPEONATOS — copas nacionais das ligas estrangeiras e Liga dos Campeões.
// Aparece uma vez por carreira (release_news; versão em updateApi.COMPETITIONS_NEWS_RELEASE). Pode ser revista no Perfil → Novidades.
const CUPS_EUROPE = [
  { id: 'fa_cup', name: 'FA Cup', from: 'Premier League' },
  { id: 'esp_copa_rey', name: 'Copa del Rey', from: 'La Liga' },
  { id: 'ita_coppa', name: 'Coppa Italia', from: 'Serie A' },
  { id: 'ger_pokal', name: 'DFB-Pokal', from: 'Bundesliga' },
  { id: 'fra_coupe', name: 'Coupe de France', from: 'Ligue 1' },
  { id: 'por_taca', name: 'Taça de Portugal', from: 'Primeira Liga', theme: { c1: '#006600', c2: '#ff0000', code: 'TP' } },
]
const CUPS_SOUTH = [
  { id: 'arg_copa', name: 'Copa Argentina', from: 'Liga Argentina', theme: { c1: '#75aadb', c2: '#1d2b4a', code: 'CA' } },
  { id: 'uru_copa', name: 'Copa AUF Uruguay', from: 'Liga Uruguaya', theme: { c1: '#5cbfeb', c2: '#0b2a4a', code: 'CU' } },
  { id: 'chi_copa', name: 'Copa Chile', from: 'Liga Chilena', theme: { c1: '#d52b1e', c2: '#0039a6', code: 'CCH' } },
  { id: 'col_copa', name: 'Copa Colombia', from: 'Liga Colombiana', theme: { c1: '#fcd116', c2: '#003893', code: 'CC' } },
  { id: 'par_copa', name: 'Copa Paraguay', from: 'Liga Paraguaia', theme: { c1: '#d52b1e', c2: '#0038a8', code: 'CP' } },
]
const UCL_SLOTS = [
  ['Inglaterra', 4], ['Espanha', 4], ['Itália', 4], ['Alemanha', 4], ['França', 3], ['Portugal', 3], ['Outros países', 10],
]

function CupList({ items }) {
  return (
    <ul className="uw-comps">
      {items.map((c) => (
        <li key={c.id}>
          <CompEmblem comp={c.id} theme={c.theme} size={34} />
          <span><b>{c.name}</b><small>{c.from}</small></span>
        </li>
      ))}
    </ul>
  )
}

export default function CompetitionsNews({ onClose, onOpenSeasons, replay = false }) {
  const [page, setPage] = useState(0)
  const pages = ['Liga dos Campeões', 'Copas nacionais', 'Como funciona']
  const last = page === pages.length - 1

  return (
    <div className="uw" role="dialog" aria-modal="true" aria-label="Novidades dos campeonatos">
      <div className="uw-card">
        <header className="uw-head">
          <div>
            <small>{replay ? 'Novidades dos campeonatos' : 'Novos campeonatos!'}</small>
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
              <div className="uw-hero-comp">
                <CompEmblem comp="ucl" size={88} />
                <p className="uw-lead">Treinando na Europa, seu clube pode disputar a <b>Liga dos Campeões</b>: 32 clubes, 8 grupos de 4, oitavas, quartas, semifinal e final única.</p>
              </div>
              <section className="uw-sec">
                <h3><GameIcon name="crown" size={20} /> Vagas por país</h3>
                <ul className="uw-slots">
                  {UCL_SLOTS.map(([country, n]) => <li key={country}><span>{country}</span><b>{n}</b></li>)}
                </ul>
                <p>As vagas saem da classificação da temporada anterior. Termine entre os primeiros da sua liga para jogar a Champions no ano seguinte.</p>
              </section>
            </>
          )}

          {page === 1 && (
            <>
              <section className="uw-sec">
                <h3><GameIcon name="trophy" size={20} /> Europa</h3>
                <CupList items={CUPS_EUROPE} />
              </section>
              <section className="uw-sec">
                <h3><GameIcon name="trophy" size={20} /> América do Sul</h3>
                <CupList items={CUPS_SOUTH} />
              </section>
            </>
          )}

          {page === 2 && (
            <div className="uw-how">
              <section>
                <h3>Nada é fixo</h3>
                <p>Quem joga cada copa e a Champions sai da tabela final da temporada anterior da <b>sua carreira</b>. Muda a cada ano e é diferente em cada carreira.</p>
              </section>
              <section>
                <h3>Formato das copas</h3>
                <p>Os 16 melhores da liga do país (8 no Paraguai) jogam mata-mata em ida e volta, com final em jogo único. É o mesmo formato da Copa do Brasil.</p>
              </section>
              <section>
                <h3>Quando começa</h3>
                <p>Os novos campeonatos entram a partir da <b>próxima temporada</b> da liga onde você treina. A temporada atual e o seu progresso continuam como estão.</p>
              </section>
              <section>
                <h3>Quem treina no Brasil</h3>
                <p>Nada muda: Brasileirão, Copa do Brasil e Libertadores seguem iguais. As copas estrangeiras e a Champions aparecem quando você aceita uma proposta de um clube de fora.</p>
              </section>
            </div>
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
              Ver temporada
            </button>
          )}
        </footer>
      </div>
    </div>
  )
}
