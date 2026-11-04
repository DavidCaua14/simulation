import { useState } from 'react'
import { ChevronRight, X } from 'lucide-react'
import agentPhoto from '../../club/assets/agent-photo.webp'
import { assistantKey as key } from '../utils/assistantStore'

// Assistente da primeira temporada (29A): opcional, com "pular". Lembrado só neste navegador, por carreira.
const STEPS = [
  { tab: 'home', title: 'Bem-vindo ao clube, professor!', text: 'Sou seu auxiliar. Aqui no Início você vê o próximo jogo, a diretoria e o botão para avançar até a partida.' },
  { tab: 'team', title: 'Monte o time', text: 'Em Time você escala, define a tática e vê o elenco. Avisos mostram quem está cansado ou fora de posição.' },
  { tab: 'team', title: 'Desenvolva o clube', text: 'Na aba Clube (dentro de Time) ficam treino, estrutura, comissão técnica, base, empréstimos e olheiros. Os atletas evoluem todo mês.' },
  { tab: 'matches', title: 'Calendário', text: 'Em Jogos ficam suas partidas e resultados. No dia do jogo você confere o rival e entra em campo — a transmissão mostra cada lance.' },
  { tab: 'world', title: 'Mercado e finanças', text: 'Mundo reúne notícias, mercado, negociações, contratos e o caixa do clube. A diretoria só aprova o que o orçamento sustenta.' },
  { tab: 'career', title: 'Sua carreira', text: 'Reputação e títulos abrem portas para clubes maiores. Resultados ruins derrubam a confiança da diretoria. Boa sorte!' },
]


export default function CoachAssistant({ careerId, onTab, onClose }) {
  const [i, setI] = useState(0)
  const step = STEPS[i]
  const finish = () => {
    try {
      window.localStorage.setItem(key(careerId), 'done')
    } catch {
      /* sem armazenamento: o assistente pode aparecer de novo */
    }
    onClose()
  }
  const next = () => {
    if (i + 1 >= STEPS.length) return finish()
    onTab?.(STEPS[i + 1].tab)
    setI(i + 1)
  }
  return (
    <div className="ca" role="dialog" aria-modal="false" aria-label="Assistente técnico">
      <img className="ca-photo" src={agentPhoto} alt="" />
      <div className="ca-bubble">
        <button type="button" className="ca-close" onClick={finish} aria-label="Pular assistente">
          <X size={16} />
        </button>
        <small>
          Auxiliar · {i + 1}/{STEPS.length}
        </small>
        <b>{step.title}</b>
        <p>{step.text}</p>
        <div className="ca-actions">
          <button type="button" className="ca-skip" onClick={finish}>
            Pular
          </button>
          <button type="button" className="ca-next" onClick={next}>
            {i + 1 >= STEPS.length ? 'Começar' : 'Próximo'} <ChevronRight size={16} />
          </button>
        </div>
      </div>
    </div>
  )
}
