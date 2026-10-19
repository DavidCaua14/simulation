import {
  HomeIcon,
  TipsIcon,
  OnlineMatchIcon,
  SeasonsIcon,
  StoreIcon,
  EventsIcon,
  UserIcon
} from '../../../components/ui/icons'

// Igual aos modos: todos os atalhos aparecem no menu fixo, só o Início
// está liberado por enquanto.
export const TAB_ITEMS = [
  { id: 'home', label: 'Início', Icon: HomeIcon, locked: false },
  { id: 'tips', label: 'Palpites', Icon: TipsIcon, locked: false },
  { id: 'online-match', label: 'Partida', Icon: OnlineMatchIcon, locked: true },
  { id: 'seasons', label: 'Temporadas', Icon: SeasonsIcon, locked: true },
  { id: 'store', label: 'Loja', Icon: StoreIcon, locked: true },
  { id: 'events', label: 'Eventos', Icon: EventsIcon, locked: true },
  { id: 'profile', label: 'Perfil', Icon: UserIcon, locked: false },
]
