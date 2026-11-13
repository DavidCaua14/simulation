import { Crown } from 'lucide-react'
import { TIER_LABEL, cardLabels, cardTier } from '../onlineUtils'

// Carta do jogador (retrato, nota, posição e os seis atributos) e peças menores usadas no mercado e no elenco.

const hash = (s) => {
  let h = 2166136261
  for (const ch of String(s)) h = Math.imul(h ^ ch.charCodeAt(0), 16777619)
  return h >>> 0
}
const SKIN = ['#f3cfa6', '#e2b488', '#c98f62', '#a86f47', '#7d4f30', '#5a3a24']
const HAIR = ['#1a1310', '#2b1d14', '#4a2f1b', '#6b4a2a', '#111111', '#8a6b3d']

// Retrato desenhado a partir do nome: tom de pele, corte e cor de cabelo sempre iguais para o mesmo jogador.
export function PlayerFace({ seed, colors, size = 72 }) {
  const h = hash(seed)
  const skin = SKIN[h % SKIN.length]
  const hair = HAIR[(h >> 4) % HAIR.length]
  const cut = (h >> 8) % 5
  const beard = (h >> 12) % 4 === 0
  const a = colors?.a || '#1b3566'
  const b = colors?.b || '#ffffff'
  return (
    <svg className="fut-face" width={size} height={size} viewBox="0 0 80 80" aria-hidden="true">
      <path d="M8 80c0-17 13-25 32-25s32 8 32 25Z" fill={a} />
      <path d="M31 55h18l-9 11Z" fill={b} />
      <path d="M33 44h14v13c-3 4-11 4-14 0Z" fill={skin} />
      <path d="M33 44h14v13c-3 4-11 4-14 0Z" fill="rgba(0,0,0,.14)" />
      <ellipse cx="40" cy="31" rx="15" ry="18" fill={skin} />
      <ellipse cx="25" cy="33" rx="2.6" ry="4" fill={skin} />
      <ellipse cx="55" cy="33" rx="2.6" ry="4" fill={skin} />
      {beard && <path d="M26 36c1 13 8 16 14 16s13-3 14-16c-3 6-8 8-14 8s-11-2-14-8Z" fill={hair} opacity=".85" />}
      {cut === 0 && <path d="M25 30c-2-14 6-20 15-20s17 6 15 20c-2-7-5-10-15-10s-13 3-15 10Z" fill={hair} />}
      {cut === 1 && <path d="M24 31c-3-17 7-23 16-23s19 6 16 23c-1-8-3-12-6-13-6 3-16 3-22 0-2 2-3 6-4 13Z" fill={hair} />}
      {cut === 2 && <path d="M26 26c0-11 7-15 14-15s14 4 14 15c-3-5-7-7-14-7s-11 2-14 7Z" fill={hair} opacity=".55" />}
      {cut === 3 && <path d="M24 32c-4-19 8-25 17-25 10 0 18 7 15 25-1-6-3-10-5-12-8 1-15-1-19-5-4 4-7 9-8 17Z" fill={hair} />}
      {cut === 4 && <path d="M25 29c-1-12 6-18 15-18s16 6 15 18c-2-6-4-9-7-10l-3-6-4 5c-7-1-13 3-16 11Z" fill={hair} />}
      <path d="M33 31h4M43 31h4" stroke="#1a1310" strokeWidth="2.2" strokeLinecap="round" />
      <path d="M35 42c3 2 7 2 10 0" stroke="rgba(0,0,0,.4)" strokeWidth="1.6" fill="none" strokeLinecap="round" />
    </svg>
  )
}


// Nome sempre inteiro: quebra em até duas linhas e encolhe a fonte conforme o tamanho.
const nameSize = (name = '') => (name.length > 24 ? 'is-xlong' : name.length > 14 ? 'is-long' : '')

// Carta grande. `club` pinta a camisa do retrato; `footer` recebe a ação (botão, preço…).
export function FutCard({ p, club, size = 'md', onClick, selected = false, disabled = false, footer = null, delay = 0 }) {
  const tier = cardTier(p)
  const Tag = onClick ? 'button' : 'div'
  return (
    <Tag
      type={onClick ? 'button' : undefined}
      className={`fut t-${tier} is-${size} ${selected ? 'is-sel' : ''}`}
      onClick={onClick}
      disabled={onClick ? disabled : undefined}
      style={{ animationDelay: `${delay}ms` }}
    >
      <span className="fut-shine" aria-hidden="true" />
      {tier !== 'normal' && <span className="fut-kind">{tier === 'legend' && <Crown size={9} />}{TIER_LABEL[tier]}</span>}
      {selected && <span className="fut-check" aria-hidden="true">✓</span>}
      <span className="fut-top">
        <span className="fut-ovr"><b>{Math.round(p.ovr)}</b><small>{p.pos}</small><i className="fut-nat">{p.nat || 'BRA'}</i></span>
        <PlayerFace seed={p.name} colors={club?.colors} size={size === 'lg' ? 96 : size === 'sm' ? 54 : 78} />
      </span>
      <strong className={`fut-name ${nameSize(p.name)}`}>{p.name}</strong>
      {p.card && size !== 'sm' && (
        <span className="fut-stats">
          {cardLabels(p.pos).map(([k, label]) => (
            <span key={k}><b>{p.card[k]}</b><small>{label}</small></span>
          ))}
        </span>
      )}
      <span className="fut-meta">{tier === 'legend' ? <>Lenda{p.pot != null && <> · POT <b>{p.pot}</b></>}</> : <>{p.age} anos{p.pot != null && <> · POT <b>{p.pot}</b></>}</>}</span>
      {footer}
    </Tag>
  )
}

// Selo pequeno de nota e posição (listas).
export function OvrBadge({ p, small = false }) {
  return (
    <span className={`on-ovr t-${cardTier(p)} ${small ? 'is-small' : ''}`}><b>{Math.round(p.ovr)}</b><small>{p.pos}</small></span>
  )
}

// Carta pequena para o campo (escalação, vestiário e partida). Mesmas props da ficha do campo das Temporadas
// (PitchTokenContext): nota na posição da vaga, posição, retrato, nome e, embaixo da carta, a condição física.
export function PitchCard({ player, pos, colors, selected, live, onClick, label }) {
  const Tag = onClick ? 'button' : 'div'
  if (!player) {
    return (
      <Tag type={onClick ? 'button' : undefined} className={`fut-pitch is-empty ${selected ? 'is-sel' : ''}`} onClick={onClick} aria-label={`${label || pos}: vaga vazia`}>
        <span className="fut-pitch-card"><b>+</b><small>{label || pos}</small></span>
      </Tag>
    )
  }
  const tier = cardTier({ ...player, ovr: player.ovr ?? player.overall })
  const rating = Math.round(player.ratings?.[pos] ?? player.ovr ?? player.overall ?? 0)
  const off = pos && player.position && player.position !== pos && !(player.secondary || []).includes(pos)
  const cond = player.condition ?? player.cond
  const tone = cond == null ? '' : cond >= 85 ? 'ok' : cond >= 70 ? 'warn' : 'bad'
  const injured = player.injured_days > 0 || player.injured
  const susp = player.suspended > 0
  const name = player.short_name || player.name || ''
  return (
    <Tag
      type={onClick ? 'button' : undefined}
      className={`fut-pitch t-${tier} ${selected ? 'is-sel' : ''} ${player.available === false ? 'is-out' : ''} ${off ? 'is-off' : ''}`}
      onClick={onClick}
      aria-label={`${label || pos}: ${name}, nota ${rating} nessa posição${cond != null ? `, condição ${Math.round(cond)}%` : ''}`}
    >
      <span className="fut-pitch-card">
        <span className="fut-pitch-ovr"><b>{rating}</b><small>{pos || player.position}</small></span>
        {tier === 'legend' && <Crown className="fut-pitch-crown" size={9} aria-hidden="true" />}
        <PlayerFace seed={name} colors={colors ? { a: colors[0], b: colors[1] } : undefined} size={34} />
        <strong className={`fut-pitch-name ${name.length > 12 ? 'is-long' : ''}`}>{name}</strong>
        {(injured || susp || (live && player.yellow > 0) || player.yellows > 0) && (
          <span className="fut-pitch-flags">
            {injured && <i className="inj" title="Lesionado">+</i>}
            {!injured && susp && <i className="susp" title="Suspenso">S</i>}
            {((live && player.yellow > 0) || player.yellows > 0) && <i className="yel" title={live ? 'Amarelo' : `${player.yellows} amarelo(s) acumulado(s)`} />}
          </span>
        )}
      </span>
      {cond != null && (
        <span className={`fut-pitch-cond ${tone}`} title={`Condição física ${Math.round(cond)}%`}>
          <i style={{ width: `${Math.max(4, Math.min(100, cond))}%` }} />
          <em>{Math.round(cond)}%</em>
        </span>
      )}
    </Tag>
  )
}
