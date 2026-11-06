import { Crosshair, Flame, Footprints, Shield, Swords, Wind } from 'lucide-react'
import { cmOnly, toCM } from '../utils/managerUtils'

// INSTRUÇÕES TÁTICAS simplificadas: seis decisões diretas. Cada escolha preenche as chaves
// completas do motor (estilo, ataque, passe, ritmo, marcação, desarme, cruzamento, gestão do jogo).
// Chutes de longe e bola parada ficam como estão.
const GROUPS = [
  {
    id: 'posture',
    label: 'Postura',
    Icon: Shield,
    read: (t) => t.style,
    options: [
      { v: 'defensive', label: 'Defensiva', effect: 'Time recuado: sofre menos gols e cria menos.', set: { style: 'defensive' } },
      { v: 'neutral', label: 'Equilibrada', effect: 'Equilíbrio entre atacar e defender.', set: { style: 'neutral' } },
      { v: 'attacking', label: 'Ofensiva', effect: 'Mais gente no ataque: cria mais e se expõe mais.', set: { style: 'attacking' } },
      { v: 'counter', label: 'Contra-ataque', effect: 'Defende baixo e sai rápido quando recupera a bola.', set: { style: 'counter' } },
    ],
  },
  {
    id: 'play',
    label: 'Jogo',
    Icon: Wind,
    read: (t) => (t.passing === 'short' ? 'short' : t.passing === 'long' ? 'direct' : 'mixed'),
    options: [
      { v: 'short', label: 'Toque de bola', effect: 'Passes curtos e paciência: mais posse e menos cansaço.', set: { passing: 'short', tempo: 'slow' } },
      { v: 'mixed', label: 'Misto', effect: 'Alterna passes curtos e longos no ritmo normal.', set: { passing: 'mixed', tempo: 'normal' } },
      { v: 'direct', label: 'Direto', effect: 'Bola longa e ritmo alto: chega mais vezes, com menos precisão.', set: { passing: 'long', tempo: 'fast' } },
    ],
  },
  {
    id: 'press',
    label: 'Marcação',
    Icon: Swords,
    read: (t) => t.marking,
    options: [
      { v: 'low', label: 'Recuada', effect: 'Bloco baixo e compacto: cansa menos, cede a bola.', set: { marking: 'low' } },
      { v: 'medium', label: 'Média', effect: 'Pressiona no meio-campo sem se desgastar demais.', set: { marking: 'medium' } },
      { v: 'high', label: 'Pressão alta', effect: 'Rouba bolas no campo rival, cansa mais e faz mais faltas.', set: { marking: 'high' } },
    ],
  },
  {
    id: 'tackle',
    label: 'Entrada',
    Icon: Footprints,
    read: (t) => t.tackling,
    options: [
      { v: 'light', label: 'Leve', effect: 'Evita o contato: bem menos cartões e expulsões, mas desarma menos.', set: { tackling: 'light' } },
      { v: 'balanced', label: 'Normal', effect: 'Disputa a bola com firmeza, sem exageros.', set: { tackling: 'balanced' } },
      { v: 'heavy', label: 'Dura', effect: 'Chega forte em toda dividida: intimida, mas o risco de expulsão dobra.', set: { tackling: 'heavy' } },
    ],
  },
  {
    id: 'route',
    label: 'Ataque por',
    Icon: Crosshair,
    read: (t) => (t.attack === 'central' ? 'central' : ['both', 'left', 'right'].includes(t.attack) ? 'wide' : 'mixed'),
    options: [
      { v: 'central', label: 'Pelo meio', effect: 'Tabelas por dentro, finalizações mais limpas.', set: { attack: 'central', crossing: 'rarely' } },
      { v: 'mixed', label: 'Variado', effect: 'Usa o meio e as pontas.', set: { attack: 'mixed', crossing: 'mixed' } },
      { v: 'wide', label: 'Pelas pontas', effect: 'Jogadas abertas e cruzamentos para a área.', set: { attack: 'both', crossing: 'byline' } },
    ],
  },
  {
    id: 'manage',
    label: 'Resultado',
    Icon: Flame,
    read: (t) => (t.manage === 'chase' ? 'chase' : 'normal'),
    options: [
      { v: 'normal', label: 'Padrão', effect: 'O time segue a postura escolhida do começo ao fim.', set: { manage: 'normal' } },
      { v: 'chase', label: 'Buscar', effect: 'Sem estar vencendo, o time se lança ao ataque o jogo todo (e mais ainda se perder no fim). Fica mais exposto atrás.', set: { manage: 'chase' } },
    ],
  },
]

export default function TacticsPanel({ tactics, onChange, compact = false }) {
  const t = toCM(tactics)
  const choose = (o) => onChange(cmOnly({ ...t, ...o.set }))

  return (
    <div className={`tps ${compact ? 'is-compact' : ''}`}>
      {GROUPS.map((g) => {
        const current = g.read(t)
        const on = g.options.find((o) => o.v === current)
        return (
          <section key={g.id} className="tps-group" role="radiogroup" aria-label={g.label}>
            <h4>
              <g.Icon size={15} /> {g.label}
            </h4>
            <div className="tps-opts" style={{ gridTemplateColumns: `repeat(${g.options.length}, minmax(0, 1fr))` }}>
              {g.options.map((o) => (
                <button key={o.v} type="button" role="radio" aria-checked={current === o.v} className={current === o.v ? 'is-on' : ''} title={o.effect} onClick={() => choose(o)}>
                  {o.label}
                </button>
              ))}
            </div>
            {!compact && on && <p>{on.effect}</p>}
          </section>
        )
      })}
    </div>
  )
}
