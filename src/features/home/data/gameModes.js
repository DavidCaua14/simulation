import {
  TipsIcon,
  OnlineMatchIcon,
  SeasonsIcon,
  RankingIcon,
  EventsIcon,
  StoreIcon,
  MessagesIcon,
  InvitesIcon,
} from '../../../components/ui/icons'
import classico from '../assets/classico.webp'
import confronto from '../assets/confronto.webp'

// Todos os modos aparecem na tela (pra já mostrar a cara final do jogo),
// mas só ficam clicáveis conforme forem sendo construídos — por enquanto,
// `locked: true` em todos.
export const GAME_MODES = [
  {
    id: 'tips',
    title: 'Palpites Esportivos',
    desc: 'Aposte nos resultados dos jogos reais e ganhe recompensas!',
    Icon: TipsIcon,
    image: classico,
    locked: true,
  },
  {
    id: 'online-match',
    title: 'Partida Online',
    desc: 'Desafie outros jogadores e mostre seu talento!',
    Icon: OnlineMatchIcon,
    image: confronto,
    locked: true,
  },
  {
    id: 'seasons',
    title: 'Temporadas',
    desc: 'Jogue partidas offline e evolua com seu time!',
    Icon: SeasonsIcon,
    locked: true,
  },
  {
    id: 'ranking',
    title: 'Ranking',
    desc: 'Veja sua posição entre os melhores jogadores!',
    Icon: RankingIcon,
    locked: true,
  },
  {
    id: 'events',
    title: 'Eventos',
    desc: 'Participe de eventos especiais e ganhe recompensas únicas!',
    Icon: EventsIcon,
    locked: true,
  },
  {
    id: 'store',
    title: 'Loja',
    desc: 'Compre itens, melhorias e muito mais!',
    Icon: StoreIcon,
    locked: true,
  },
  {
    id: 'messages',
    title: 'Mensagens',
    desc: 'Confira suas mensagens e novidades do jogo.',
    Icon: MessagesIcon,
    locked: true,
  },
  {
    id: 'invites',
    title: 'Convites',
    desc: 'Veja convites pra partidas, eventos e muito mais!',
    Icon: InvitesIcon,
    locked: true,
  },
]
