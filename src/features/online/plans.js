import { ArrowUpRight, MoveHorizontal, Repeat, Rocket, Shield, Users } from 'lucide-react'

// ESTILOS DE JOGO do modo online (motor em supabase/online/43_schedule_styles_roles.sql).
// what: o que o time faz em campo · attrs: atributos que mais pesam (aderência do elenco) · strong: estilos contra os
// quais ele leva vantagem (on_plan_vs). Pontos fracos não aparecem: o técnico descobre jogando.
export const PLANS = [
  {
    id: 'posse', label: 'Posse de bola', short: 'Posse', Icon: Repeat,
    what: 'Troca passes curtos com paciência, fica com a bola e cansa menos. Cria menos chances, mas melhores.',
    attrs: ['Posse', 'Precisão de passes', 'Criação'],
    keys: 'Técnica (criação e controle) do meio e do ataque.',
    strong: ['pontas', 'direto'],
  },
  {
    id: 'contra', label: 'Contra-ataque rápido', short: 'Contra rápido', Icon: Rocket,
    what: 'Pressiona no campo de ataque, rouba a bola e chega ao gol em poucos toques. Linha alta e muito desgaste.',
    attrs: ['Velocidade de transição', 'Pressão', 'Finalização'],
    keys: 'Fôlego e velocidade do time; velocidade do ataque contra a da defesa rival.',
    strong: ['posse', 'sobrecarga'],
  },
  {
    id: 'contra_longo', label: 'Contra-ataque com bolas longas', short: 'Contra longo', Icon: Shield,
    what: 'Defende compacto e baixo; quando recupera, lança nas costas da defesa. O adversário cria pouco.',
    attrs: ['Organização defensiva', 'Lançamentos', 'Velocidade'],
    keys: 'Defesa contra o ataque rival; velocidade do ataque contra a da defesa rival.',
    strong: ['posse', 'contra'],
  },
  {
    id: 'pontas', label: 'Pelas pontas', short: 'Pontas', Icon: MoveHorizontal,
    what: 'Abre o campo, ataca pelos lados com pontas e laterais e cruza na área para o cabeceio.',
    attrs: ['Cruzamentos', 'Amplitude', 'Movimentação dos pontas'],
    keys: 'Velocidade e criação de pontas e laterais contra os laterais rivais.',
    strong: ['contra_longo', 'sobrecarga'],
  },
  {
    id: 'direto', label: 'Bola longa', short: 'Bola longa', Icon: ArrowUpRight,
    what: 'Pula o meio-campo com bolas altas no centroavante e briga pela segunda bola. Muitas finalizações, muitas de cabeça.',
    attrs: ['Jogo aéreo', 'Força física', 'Segundas bolas'],
    keys: 'Cabeceio e força do centroavante contra os dos zagueiros rivais.',
    strong: ['contra', 'pontas'],
  },
  {
    id: 'sobrecarga', label: 'Sobrecarga', short: 'Sobrecarga', Icon: Users,
    what: 'Leva mais gente para perto da bola, cria superioridade numérica com passes curtos e pressiona alto. Deixa espaço atrás.',
    attrs: ['Superioridade numérica', 'Passes curtos', 'Pressão'],
    keys: 'Técnica do meio e do ataque e fôlego do time.',
    strong: ['contra_longo', 'direto'],
  },
]
export const PLAN_BY_ID = Object.fromEntries(PLANS.map((p) => [p.id, p]))
export const planLabel = (id) => PLAN_BY_ID[id]?.label || PLANS[0].label
export const planShort = (id) => PLAN_BY_ID[id]?.short || PLANS[0].short

// Planos antigos e formato antigo → estilo (mesma regra de on_plan_legacy no banco).
const OLD = { equilibrado: 'posse', pressao: 'contra', retranca: 'contra_longo', total: 'sobrecarga' }
export function planOf(t = {}) {
  if (PLAN_BY_ID[t.plan]) return t.plan
  if (OLD[t.plan]) return OLD[t.plan]
  if (t.style === 'counter') return 'contra'
  if (t.style === 'defensive') return 'contra_longo'
  if (t.style === 'attacking') return 'sobrecarga'
  if ((t.marking || t.pressing) === 'high') return 'contra'
  if (t.passing === 'long' || t.build === 'direct') return 'direto'
  if (['both', 'left', 'right'].includes(t.attack) || t.width === 'wide') return 'pontas'
  return 'posse'
}

// Instruções que valem por cima do estilo.
export const INSTRUCTIONS = [
  {
    id: 'manage', label: 'Resultado',
    options: [
      { v: 'keep', label: 'Segurar', effect: 'Vencendo, recua no fim para garantir.' },
      { v: 'normal', label: 'Padrão', effect: 'Mantém o estilo o jogo todo.' },
      { v: 'chase', label: 'Buscar', effect: 'Sem vencer, parte para o ataque.' },
    ],
  },
  {
    id: 'tackling', label: 'Entrada',
    options: [
      { v: 'light', label: 'Leve', effect: 'Evita cartões.' },
      { v: 'balanced', label: 'Normal', effect: 'Disputa firme.' },
      { v: 'heavy', label: 'Dura', effect: 'Intimida e ganha mais divididas, com mais faltas e cartões.' },
    ],
  },
  {
    id: 'long_shots', label: 'Chutes de fora',
    options: [
      { v: 'rarely', label: 'Raramente', effect: 'Só chuta de dentro da área.' },
      { v: 'sometimes', label: 'Às vezes', effect: 'Arrisca quando há espaço.' },
      { v: 'often', label: 'Sempre', effect: 'Chuta de longe sempre que pode (bom com finalizadores de média distância).' },
    ],
  },
]

// Até 2 marcações individuais: [{ by: meu jogador, on: jogador do adversário }]
export const MAX_MARKS = 2
