import { Flame } from 'lucide-react'
import { POS_NAME } from '../../seasons/utils/managerUtils'
import { btDate, btMatch } from './bigtimeUtils'
import './bigtime.css'
import './pixel-card.css'

// CARTAS BIG TIME (vermelhas): atuação real de um jogador num dia específico. A foto vem do painel do administrador
// (Storage, bucket bigtime) com o enquadramento salvo em photo_pos {x, y, zoom}.

// Foto recortada no quadro, com o enquadramento escolhido no painel.
export function BtPhoto({ bt, className = '', alt = '' }) {
  const pos = bt?.photo_pos || {}
  if (!bt?.photo) return <span className={`bt-photo is-empty ${className}`} aria-hidden="true"><Flame size={28} /></span>
  return (
    <span className={`bt-photo ${className}`}>
      <img
        src={bt.photo}
        alt={alt}
        loading="lazy"
        draggable={false}
        style={{ objectPosition: `${pos.x ?? 50}% ${pos.y ?? 20}%`, transform: `scale(${pos.zoom ?? 1})`, transformOrigin: `${pos.x ?? 50}% ${pos.y ?? 20}%` }}
      />
    </span>
  )
}

// Carta grande (loja, revelação da caixa, ficha) no layout em pixel art das outras cartas, com a foto real do
// jogador sem alteração. size: sm | md | lg.
export default function BigTimeCard({ bt, ovr, pos, size = 'md', onClick, delay = 0, footer = null }) {
  if (!bt) return null
  const Tag = onClick ? 'button' : 'div'
  const rating = Math.round(ovr ?? bt.rating)
  const at = pos || bt.pos
  return (
    <Tag type={onClick ? 'button' : undefined} className={`pxc t-bigtime is-${size}`} onClick={onClick} style={{ animationDelay: `${delay}ms` }}
      aria-label={`Big Time ${bt.name}, ${at} ${rating}, ${btMatch(bt)} em ${btDate(bt.match_date)}`}>
      <span className="pxc-frame">
        <i className="pxc-cn bl" aria-hidden="true" /><i className="pxc-cn br" aria-hidden="true" />
        <span className="pxc-in">
          <span className="pxc-head">
            <span className="pxc-pos">{at}</span>
            <span className="pxc-chip">Big Time</span>
            <span className="pxc-ovr">{rating}</span>
          </span>
          <span className="pxc-art">
            <BtPhoto bt={bt} className="is-fut" />
            {bt.nat && <span className="pxc-nat">{bt.nat}</span>}
          </span>
          <strong className={`pxc-name ${(bt.name || '').length > 16 ? 'is-long' : ''}`}>{bt.name}</strong>
          <span className="pxc-strip"><b><i>{bt.year}</i></b><b>{bt.team ? `× ${bt.opponent}` : `vs ${bt.opponent}`}</b></span>
        </span>
      </span>
      {footer && <span className="pxc-foot">{footer}</span>}
    </Tag>
  )
}

// Bloco "A atuação" para a ficha do jogador: data, jogo, competição, idade naquele dia, habilidades e a história.
export function BigTimeFacts({ bt, compact = false }) {
  if (!bt) return null
  const positions = [bt.pos, ...(bt.sec || [])].map((x) => POS_NAME[x] || x).join(' · ')
  return (
    <section className={`btf ${compact ? 'is-compact' : ''}`}>
      <h5><Flame size={13} /> A atuação</h5>
      <dl>
        <div><dt>Data</dt><dd>{btDate(bt.match_date)}</dd></div>
        <div><dt>Jogo</dt><dd>{btMatch(bt)}</dd></div>
        {bt.competition && <div><dt>Competição</dt><dd>{bt.competition}</dd></div>}
        <div><dt>Idade naquele dia</dt><dd>{bt.age} anos</dd></div>
        <div><dt>Posições</dt><dd>{positions}</dd></div>
        <div><dt>Nacionalidade</dt><dd>{bt.nat}</dd></div>
        <div><dt>Regularidade</dt><dd>B · nunca abaixo da seta amarela</dd></div>
      </dl>
      {bt.skills?.length > 0 && (
        <div className="btf-skills">
          <small>Habilidades</small>
          <ul>{bt.skills.map((s) => <li key={s}>{s}</li>)}</ul>
        </div>
      )}
      {bt.story && !compact && <p className="btf-story">{bt.story}</p>}
    </section>
  )
}
