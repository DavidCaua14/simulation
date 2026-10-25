import { Activity, Award, CalendarDays, Crown, Flame, Gem, Layers, Shield, Star, Store, Trophy, Zap } from 'lucide-react'

// Ícones usados por emblemas (cosméticos) e insígnias. O nome vem do banco; desconhecido vira um troféu genérico.
const ICONS = { zap: Zap, star: Star, shield: Shield, flame: Flame, crown: Crown, trophy: Trophy, activity: Activity,
  calendar: CalendarDays, layers: Layers, gem: Gem, store: Store, award: Award }

export default function CosmeticIcon({ name, size = 16, ...rest }) {
  const Icon = ICONS[name] || Award
  return <Icon size={size} {...rest} />
}
