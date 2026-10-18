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
import palpites from '../assets/palpites.webp'
import confronto from '../assets/confronto.webp'
import temporadas from '../assets/temporadas.webp'
import ranking from '../assets/ranking.webp'
import eventos from '../assets/eventos.webp'
import loja from '../assets/loja.webp'
import mensagens from '../assets/mensagens.webp'
import convites from '../assets/convites.webp'

// Todos os modos aparecem na tela (pra já mostrar a cara final do jogo),
// mas só ficam clicáveis conforme forem sendo construídos.
// `locked: false` libera o card; o clique é tratado em HomeScreen (onSelectMode).
export const GAME_MODES = [
  {
    id: 'tips',
    title: 'Palpites Esportivos',
    desc: 'Aposte nos resultados dos jogos reais e ganhe recompensas!',
    Icon: TipsIcon,
    image: palpites,
    locked: false,
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
    image: temporadas,
    locked: true,
  },
  {
    id: 'ranking',
    title: 'Ranking',
    desc: 'Veja sua posição entre os melhores jogadores!',
    Icon: RankingIcon,
    image: ranking,
    locked: true,
  },
  {
    id: 'events',
    title: 'Eventos',
    desc: 'Participe de eventos especiais e ganhe recompensas únicas!',
    Icon: EventsIcon,
    image: eventos,
    locked: true,
  },
  {
    id: 'store',
    title: 'Loja',
    desc: 'Compre itens, melhorias e muito mais!',
    Icon: StoreIcon,
    image: loja,
    locked: true,
  },
  {
    id: 'messages',
    title: 'Mensagens',
    desc: 'Confira suas mensagens e novidades do jogo.',
    Icon: MessagesIcon,
    image: mensagens,
    locked: true,
  },
  {
    id: 'invites',
    title: 'Convites',
    desc: 'Veja convites pra partidas, eventos e muito mais!',
    Icon: InvitesIcon,
    image: convites,
    locked: true,
  },
]
