import {
  HomeIcon,
  TipsIcon,
  OnlineMatchIcon,
  SeasonsIcon,
  StoreIcon,
  EventsIcon,
  UserIcon
} from '../../../components/ui/icons'

// Igual aos modos: todos os atalhos aparecem no menu fixo; `locked` marca os que ainda não existem.
export const TAB_ITEMS = [
  { id: 'home', label: 'Início', Icon: HomeIcon, locked: false },
  { id: 'tips', label: 'Palpites', Icon: TipsIcon, locked: false },
  { id: 'online-match', label: 'Online', Icon: OnlineMatchIcon, locked: false },
  { id: 'seasons', label: 'Temporadas', Icon: SeasonsIcon, locked: true, testerOnly: true },
  { id: 'store', label: 'Loja', Icon: StoreIcon, locked: false },
  { id: 'events', label: 'Eventos', Icon: EventsIcon, locked: false },
  { id: 'profile', label: 'Perfil', Icon: UserIcon, locked: false },
]
