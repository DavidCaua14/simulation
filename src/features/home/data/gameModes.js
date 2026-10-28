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
    desc: 'Desafie outros técnicos e mostre sua estratégia!',
    Icon: OnlineMatchIcon,
    image: confronto,
    locked: true,
  },
  {
    id: 'seasons',
    title: 'Temporadas',
    desc: 'Seja o treinador: escale, defina a tática e comande clubes reais!',
    Icon: SeasonsIcon,
    image: temporadas,
    locked: false,
  },
  {
    id: 'ranking',
    title: 'Ranking',
    desc: 'Veja sua posição entre os melhores técnicos!',
    Icon: RankingIcon,
    image: ranking,
    locked: true,
  },
  {
    id: 'events',
    title: 'Eventos',
    desc: 'Desafios diários, semanais e especiais com recompensas — e a sequência diária.',
    Icon: EventsIcon,
    image: eventos,
    locked: false,
  },
  {
    id: 'store',
    title: 'Loja',
    desc: 'Cartas Destaque e Lenda por moedas ou diamantes.',
    Icon: StoreIcon,
    image: loja,
    locked: false,
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
    id: 'friends',
    title: 'Amigos',
    desc: 'Adicione amigos pelo username, aceite convites e veja perfis.',
    Icon: InvitesIcon,
    image: convites,
    locked: false,
  },
]
