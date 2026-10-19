// Ícones da tela de palpites (lucide-react). Ficam aqui para não mexer no icons.jsx compartilhado.
import {
  AlertTriangle, CheckCircle2, Clock3, Coins, Flag, Info, Medal, Play, Star, Ticket, Timer, Trophy, Undo2, XCircle, Zap,
} from 'lucide-react'

export const CoinIcon = (p) => <Coins size={14} {...p} />
export const EnergyIcon = (p) => <Zap size={14} fill="currentColor" {...p} />
export const FavoriteIcon = (p) => <Star size={11} fill="currentColor" {...p} />
export const TimerIcon = (p) => <Timer size={13} {...p} />
export const TrophyIcon = (p) => <Trophy size={16} {...p} />
export const TicketIcon = (p) => <Ticket size={16} {...p} />

export const PICK_STATUS_ICON = {
  pending: Clock3,
  won: CheckCircle2,
  lost: XCircle,
  void: Undo2,
}

export const TOAST_ICON = { start: Play, finish: Flag, ticket: Ticket, alert: AlertTriangle, info: Info }

export function PickStatusIcon({ status, size = 16 }) {
  const Icon = PICK_STATUS_ICON[status] || Clock3
  return <Icon size={size} className={`pred-status-ic ${status}`} aria-hidden="true" />
}

export function ToastIcon({ kind = 'info' }) {
  const Icon = TOAST_ICON[kind] || Info
  return <Icon size={16} aria-hidden="true" />
}

export function MedalIcon({ position }) {
  const tone = position === 1 ? 'gold' : position === 2 ? 'silver' : 'bronze'
  return <Medal size={20} className={`pred-medal ${tone}`} aria-label={`${position}º lugar`} />
}

// Valores com ícone: <Amount icon="coin" value={120} />
export function Amount({ kind, value, sign = '' }) {
  const Icon = kind === 'energy' ? EnergyIcon : CoinIcon
  return (
    <span className={`pred-amt ${kind}`}>
      <Icon />
      <b>{sign}{value}</b>
    </span>
  )
}
