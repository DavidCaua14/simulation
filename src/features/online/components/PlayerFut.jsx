import '@fontsource/press-start-2p/400.css'
import '@fontsource/pixelify-sans/600.css'
import '@fontsource/silkscreen/400.css'
import '@fontsource/silkscreen/700.css'
import ConditionArrow from './ConditionArrow'
import { TIER_LABEL, cardLabels, cardTier } from '../onlineUtils'
import { BtPhoto } from './BigTime'
import { FACE_H, FACE_W, pixelFaceUrl, shortName } from './pixelFace'
import './pitch-card.css'
import './pixel-card.css'

// Carta do jogador (retrato, nota, posição e os seis atributos) e peças menores usadas no mercado e no elenco.

// Retrato em pixel art a partir do nome (pele, cabelo e corte sempre iguais para o mesmo jogador); a camisa sai
// nas cores do clube. `size` é a largura; a altura segue a proporção do desenho.
export function PlayerFace({ seed, colors, size = 72, className = '' }) {
  const url = pixelFaceUrl(seed, colors?.a, colors?.b)
  if (!url) return null
  return <img className={`fut-face px-face ${className}`} src={url} width={size} height={Math.round((size * FACE_H) / FACE_W)} alt="" draggable={false} />
}


// Carta grande em pixel art. `club` pinta a camisa do retrato; `footer` recebe a ação (botão, preço…).
// Topo: posição, tipo e nota · retrato (Big Time: a foto real) com nacionalidade, condição e número · nome ·
// faixa com potencial e idade (Big Time: ano e adversário) · os seis atributos.
const TIER_CHIP = { normal: 'Base', special: 'Destaque', legend: 'Épica', bigtime: 'Big Time' }
export function FutCard({ p, club, size = 'md', onClick, selected = false, disabled = false, footer = null, delay = 0 }) {
  const tier = cardTier(p)
  const Tag = onClick ? 'button' : 'div'
  const long = (p.name || '').length > 16
  return (
    <Tag
      type={onClick ? 'button' : undefined}
      className={`pxc t-${tier} is-${size} ${selected ? 'is-sel' : ''}`}
      onClick={onClick}
      disabled={onClick ? disabled : undefined}
      style={{ animationDelay: `${delay}ms` }}
      aria-label={`${p.name}, ${p.pos} ${Math.round(p.ovr)}, carta ${TIER_CHIP[tier]}`}
    >
      {selected && <span className="pxc-check" aria-hidden="true">✓</span>}
      <span className="pxc-frame">
        <i className="pxc-cn bl" aria-hidden="true" /><i className="pxc-cn br" aria-hidden="true" />
        <span className="pxc-in">
          <span className="pxc-head">
            <span className="pxc-pos">{p.pos}</span>
            <span className="pxc-chip">{TIER_CHIP[tier]}</span>
            <span className="pxc-ovr">{Math.round(p.ovr)}</span>
          </span>
          <span className="pxc-art">
            {p.bt?.photo ? <BtPhoto bt={p.bt} className="is-fut" /> : <PlayerFace seed={p.name} colors={club?.colors} size={176} />}
            <span className="pxc-nat">{p.nat || 'BRA'}</span>
            {p.arrow != null && <span className="pxc-arrow"><ConditionArrow arrow={p.arrow} size={18} /></span>}
            {p.number != null && <span className="pxc-num">{p.number}</span>}
          </span>
          <strong className={`pxc-name ${long ? 'is-long' : ''}`}>{p.name}</strong>
          <span className="pxc-strip">
            {tier === 'bigtime' && p.bt ? <><b><i>{p.bt.year}</i></b><b>× {p.bt.opponent}</b></>
              : <><b>{p.pot != null ? <>POT <i>{p.pot}</i></> : TIER_LABEL[tier]}</b><b>{p.age != null ? <><i>{p.age}</i> ANOS</> : ''}</b></>}
          </span>
          {p.card && size !== 'sm' && (
            <span className="pxc-stats">
              {cardLabels(p.pos).map(([k, label]) => <span key={k}>{label}<b>{p.card[k]}</b></span>)}
            </span>
          )}
        </span>
      </span>
      {footer && <span className="pxc-foot">{footer}</span>}
    </Tag>
  )
}

// Miniatura da carta (mercado, leilão encerrado): moldura do tipo, nota e posição no topo e o rosto inteiro
// embaixo (Big Time: a foto real). size = largura em pixels; name mostra a faixa do nome.
export function MiniCard({ p, club, size = 62, name = false }) {
  if (!p) return null
  const tier = cardTier(p)
  return (
    <span className={`px-mini t-${tier}`}>
      <span className="pxm" style={{ '--pw': `${size}px` }}>
        <span className="pxm-art">
          {p.bt?.photo ? <BtPhoto bt={p.bt} className="is-tile" /> : <PlayerFace seed={p.name} colors={club?.colors} size={Math.round(size * 1.3)} />}
          <b className="pxm-ovr">{Math.round(p.ovr)}</b>
          <small className="pxm-pos">{p.pos}</small>
        </span>
        {name && <span className="pxm-name">{shortName(p.name)}</span>}
      </span>
    </span>
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
// tier força o tipo da carta (as Temporadas só têm carta normal).
export function PitchCard({ player, pos, colors, selected, live, onClick, label, tier: forcedTier }) {
  const Tag = onClick ? 'button' : 'div'
  if (!player) {
    return (
      <Tag type={onClick ? 'button' : undefined} className={`fut-pitch is-empty ${selected ? 'is-sel' : ''}`} onClick={onClick} aria-label={`${label || pos}: vaga vazia`}>
        <span className="pxm is-empty"><span><b>+</b><br /><small>{label || pos}</small></span></span>
      </Tag>
    )
  }
  const tier = forcedTier || cardTier({ ...player, ovr: player.ovr ?? player.overall })
  const rating = Math.round(player.ratings?.[pos] ?? player.ovr ?? player.overall ?? 0)
  // fora da posição de origem (nem secundária, nem aprendida): carta amarela e a posição dele embaixo
  const off = Boolean(pos && player.position && player.position !== pos && !(player.secondary || []).includes(pos) && !(player.learned || []).includes(pos))
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
      aria-label={`${label || pos}: ${name}, nota ${rating} nessa posição${off ? `, fora da posição (é ${player.position})` : ''}${cond != null ? `, condição ${Math.round(cond)}%` : ''}`}
    >
      <span className="pxm">
        <span className="pxm-art">
          {player.bt?.photo ? <BtPhoto bt={player.bt} className="is-pitch" /> : <PlayerFace seed={name} colors={colors ? { a: colors[0], b: colors[1] } : undefined} size={76} />}
          <b className="pxm-ovr">{rating}</b>
          <small className="pxm-pos">{pos || player.position}</small>
          {player.arrow != null && <span className="pxm-arrow"><ConditionArrow arrow={player.arrow} size={14} /></span>}
          {(injured || susp || (live && player.yellow > 0) || player.yellows > 0) && (
            <span className="pxm-flags">
              {injured && <i className="inj" title="Lesionado">+</i>}
              {!injured && susp && <i className="susp" title="Suspenso">S</i>}
              {((live && player.yellow > 0) || player.yellows > 0) && <i className="yel" title={live ? 'Amarelo' : `${player.yellows} amarelo(s) acumulado(s)`} />}
            </span>
          )}
        </span>
        <span className="pxm-name">{shortName(name)}</span>
        {cond != null && (
          <span className={`pxm-cond ${tone}`} title={`Condição física ${Math.round(cond)}%`}>
            <i style={{ width: `${Math.max(4, Math.min(100, cond))}%` }} />
            <em>{Math.round(cond)}%</em>
          </span>
        )}
      </span>
      {off && <span className="px-natpos" title={`Fora da posição: a posição de origem é ${player.position}`}>É {player.position}</span>}
    </Tag>
  )
}
