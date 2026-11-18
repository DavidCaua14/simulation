import { ArrowUpRight, Flame, MoveHorizontal, Repeat, Scale, Shield, Swords, Zap } from 'lucide-react'

// PLANOS DE JOGO do modo online (motor em supabase/online/33_tactical_plans.sql). Textos curtos e só com o que
// funciona: o que o plano faz, com que elenco funciona (encaixe) e contra quais planos ele é melhor (on_plan_vs).
// Pontos fracos não aparecem: o técnico descobre jogando.
export const PLANS = [
  { id: 'equilibrado', label: 'Equilibrado', Icon: Scale, what: 'Ataca e defende na mesma medida.', needs: 'Qualquer elenco.', strong: [] },
  { id: 'posse', label: 'Posse de bola', Icon: Repeat, what: 'Troca passes, fica com a bola e cansa menos.', needs: 'Meio e ataque técnicos (passe e controle).', strong: ['contra', 'direto'] },
  { id: 'pressao', label: 'Pressão alta', Icon: Flame, what: 'Rouba a bola perto do gol adversário.', needs: 'Time com fôlego e velocidade.', strong: ['posse', 'retranca'] },
  { id: 'contra', label: 'Contra-ataque', Icon: Zap, what: 'Defende atrás e sai rápido quando rouba a bola.', needs: 'Atacantes rápidos.', strong: ['pressao', 'total', 'pontas'] },
  { id: 'retranca', label: 'Retranca', Icon: Shield, what: 'Fecha a defesa: o adversário quase não cria.', needs: 'Zaga e volantes fortes.', strong: ['total', 'direto', 'contra'] },
  { id: 'direto', label: 'Bola longa', Icon: ArrowUpRight, what: 'Lança direto para o centroavante.', needs: 'Centroavante forte e bom de cabeça.', strong: ['pressao', 'total'] },
  { id: 'pontas', label: 'Pelas pontas', Icon: MoveHorizontal, what: 'Ataca pelos lados e cruza na área.', needs: 'Pontas e laterais rápidos.', strong: ['retranca', 'posse'] },
  { id: 'total', label: 'Ataque total', Icon: Swords, what: 'Todo mundo no ataque para buscar o gol.', needs: 'Ataque forte.', strong: [] },
]
export const PLAN_BY_ID = Object.fromEntries(PLANS.map((p) => [p.id, p]))
export const planLabel = (id) => PLAN_BY_ID[id]?.label || 'Equilibrado'

// Formato antigo das táticas → plano (mesma regra de on_plan_legacy no banco).
export function planOf(t = {}) {
  if (PLAN_BY_ID[t.plan]) return t.plan
  if (t.style === 'counter') return 'contra'
  if (t.style === 'defensive') return 'retranca'
  if (t.style === 'attacking') return 'total'
  if ((t.marking || t.pressing) === 'high') return 'pressao'
  if (t.passing === 'short' || t.build === 'short') return 'posse'
  if (t.passing === 'long' || t.build === 'direct') return 'direto'
  if (['both', 'left', 'right'].includes(t.attack) || t.width === 'wide') return 'pontas'
  return 'equilibrado'
}

// Instruções que valem por cima do plano.
export const INSTRUCTIONS = [
  {
    id: 'manage', label: 'Resultado',
    options: [
      { v: 'keep', label: 'Segurar', effect: 'Vencendo, recua no fim para garantir.' },
      { v: 'normal', label: 'Padrão', effect: 'Mantém o plano o jogo todo.' },
      { v: 'chase', label: 'Buscar', effect: 'Sem vencer, parte para o ataque.' },
    ],
  },
  {
    id: 'tackling', label: 'Entrada',
    options: [
      { v: 'light', label: 'Leve', effect: 'Evita cartões.' },
      { v: 'balanced', label: 'Normal', effect: 'Disputa firme.' },
      { v: 'heavy', label: 'Dura', effect: 'Intimida e ganha mais divididas.' },
    ],
  },
  {
    id: 'long_shots', label: 'Chutes de fora',
    options: [
      { v: 'rarely', label: 'Raramente', effect: 'Só chuta de dentro da área.' },
      { v: 'sometimes', label: 'Às vezes', effect: 'Arrisca quando há espaço.' },
      { v: 'often', label: 'Sempre', effect: 'Chuta de longe sempre que pode.' },
    ],
  },
  {
    id: 'set_pieces', label: 'Bola parada', def: 'cross',
    options: [
      { v: 'cross', label: 'Cruzar', effect: 'Bola na área para o cabeceio.' },
      { v: 'shoot', label: 'Chutar', effect: 'Falta direta no gol.' },
      { v: 'short', label: 'Curta', effect: 'Cobrança curta para manter a bola.' },
    ],
  },
]
