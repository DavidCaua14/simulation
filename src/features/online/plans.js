import { ArrowUpRight, Flame, MoveHorizontal, Repeat, Scale, Shield, Swords, Zap } from 'lucide-react'

// PLANOS DE JOGO do modo online. Os textos seguem o motor (supabase/online/33_tactical_plans.sql):
// o jeito de jogar, o que o plano exige do elenco (aderência) e os confrontos com os outros planos (on_plan_vs).
export const PLANS = [
  {
    id: 'equilibrado', label: 'Equilibrado', Icon: Scale,
    what: 'Ataca e defende na mesma medida. Não tem ponto fraco, mas também não explora o do adversário.',
    needs: 'Nada em especial.',
    strong: [], weak: [],
  },
  {
    id: 'posse', label: 'Posse de bola', Icon: Repeat,
    what: 'Passes curtos e paciência: fica mais com a bola, chuta menos e de posições melhores, e cansa menos.',
    needs: 'Técnica (passe e controle) do meio e do ataque.',
    strong: ['contra', 'direto'], weak: ['pressao', 'pontas'],
  },
  {
    id: 'pressao', label: 'Pressão alta', Icon: Flame,
    what: 'Marca na saída de bola do rival com a linha alta: rouba bolas perto do gol, mas cansa mais e faz mais faltas.',
    needs: 'Físico: fôlego e velocidade do time todo.',
    strong: ['posse', 'retranca'], weak: ['direto', 'contra'],
  },
  {
    id: 'contra', label: 'Contra-ataque', Icon: Zap,
    what: 'Defende recuado e sai em velocidade quando rouba a bola: pouca posse, chances poucas e perigosas.',
    needs: 'Atacantes mais rápidos que os defensores do rival.',
    strong: ['pressao', 'total', 'pontas'], weak: ['posse', 'retranca'],
  },
  {
    id: 'retranca', label: 'Retranca', Icon: Shield,
    what: 'Todo mundo atrás da linha da bola: o rival cria bem menos, e o seu time também. Boa para segurar resultado.',
    needs: 'Defesa forte (zagueiros, laterais e volantes) contra o ataque rival.',
    strong: ['total', 'direto', 'contra'], weak: ['pontas', 'pressao'],
  },
  {
    id: 'direto', label: 'Bola longa', Icon: ArrowUpRight,
    what: 'Lança direto para o centroavante: pula o meio-campo e fura a pressão, com menos precisão.',
    needs: 'Centroavante bom de cabeça e forte, melhor que os zagueiros rivais.',
    strong: ['pressao', 'total'], weak: ['posse', 'retranca'],
  },
  {
    id: 'pontas', label: 'Pelas pontas', Icon: MoveHorizontal,
    what: 'Abre o campo com pontas e laterais e cruza na área: muito mais jogadas de cabeça.',
    needs: 'Pontas e laterais rápidos e criativos, melhores que os laterais rivais.',
    strong: ['retranca', 'posse'], weak: ['contra'],
  },
  {
    id: 'total', label: 'Ataque total', Icon: Swords,
    what: 'Todo mundo ao ataque: cria muito mais, mas deixa a defesa exposta. Para buscar o resultado.',
    needs: 'Ataque forte contra a defesa rival.',
    strong: [], weak: ['retranca', 'contra', 'direto'],
  },
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
      { v: 'keep', label: 'Segurar', effect: 'Vencendo a partir dos 70 minutos, o time recua para garantir o resultado.' },
      { v: 'normal', label: 'Padrão', effect: 'O time segue o plano do começo ao fim.' },
      { v: 'chase', label: 'Buscar', effect: 'Sem estar vencendo, o time se lança ao ataque (mais ainda se perder no fim) e fica exposto atrás.' },
    ],
  },
  {
    id: 'tackling', label: 'Entrada',
    options: [
      { v: 'light', label: 'Leve', effect: 'Evita o contato: bem menos cartões, mas desarma menos.' },
      { v: 'balanced', label: 'Normal', effect: 'Disputa a bola com firmeza, sem exageros.' },
      { v: 'heavy', label: 'Dura', effect: 'Chega forte em toda dividida: intimida, mas o risco de expulsão dobra.' },
    ],
  },
  {
    id: 'long_shots', label: 'Chutes de fora',
    options: [
      { v: 'rarely', label: 'Raramente', effect: 'Só chuta de dentro da área: menos chutes, mais limpos.' },
      { v: 'sometimes', label: 'Às vezes', effect: 'Arrisca de fora quando aparece espaço.' },
      { v: 'often', label: 'Sempre', effect: 'Chuta de longe sempre que pode: bom com bons finalizadores.' },
    ],
  },
  {
    id: 'set_pieces', label: 'Bola parada', def: 'cross',
    options: [
      { v: 'cross', label: 'Cruzar', effect: 'Escanteios e faltas na área, para quem cabeceia bem.' },
      { v: 'shoot', label: 'Chutar', effect: 'Falta direta no gol: rende com um bom cobrador.' },
      { v: 'short', label: 'Curta', effect: 'Cobrança curta para manter a bola.' },
    ],
  },
]
