import { useEffect, useRef, useState } from 'react'
import { FileSignature, Gavel, Sparkles, TrendingUp, UserMinus, X } from 'lucide-react'
import GoldenWhistle from './GoldenWhistle'
import { POS_NAME } from '../../seasons/utils/managerUtils'
import { FutCard } from './PlayerFut'
import { money } from '../onlineUtils'

const AUCTION_STEPS = [[0.5, 'Mínimo'], [0.75, '75%'], [1, 'Valor'], [1.5, '+50%'], [2, 'Dobro']]
const round100 = (n) => Math.ceil(n / 100) * 100
// salário pela nota (mesma fórmula de on_wage no banco)
const wageFor = (ovr, age) => Math.ceil((Math.max(1, ovr - 45) ** 2 * 0.65 + Math.max(0, ovr - 75) ** 2 * 12) * (age < 24 ? 1.1 : age >= 31 ? 0.9 : 1))

// FICHA DO JOGADOR do elenco: carta, nota atual e até onde pode chegar, contrato e as ações (leiloar, dispensar, renovar).
// items: resposta de online_items (enabled quando o item está liberado); onUseItem(p) devolve a promessa do uso.
export default function PlayerSheet({ p, club, seasonId, busy, listed, onClose, onSell, onRenew, onAuction, items, onUseItem }) {
  const [mode, setMode] = useState(null)
  const [step, setStep] = useState(1)
  const [train, setTrain] = useState(null) // {from, to} durante o treino de elite
  const [maxed, setMaxed] = useState(null) // {from, to} depois dele
  const [itemErr, setItemErr] = useState('')
  const whistle = items?.enabled ? items.items?.golden_whistle : null
  const left = (p.contract_end ?? 0) - (seasonId || 0)
  const ovr = Math.round(p.ovr)
  const pot = Math.max(ovr, Math.round(p.pot ?? p.ovr))
  const room = pot - ovr
  const startPrice = step === 0.5 ? Math.max(500, Math.round(p.value * 0.5)) : round100(p.value * step)
  const positions = [p.pos, ...(p.sec || [])].map((x) => POS_NAME[x] || x).join(' · ')
  const startWhistle = () => {
    setItemErr('')
    const from = ovr
    setTrain({ from, to: pot })
    // o treino dura pelo menos 4,2 s na tela, mesmo que o servidor responda antes
    const wait = new Promise((r) => setTimeout(r, 4200))
    Promise.all([onUseItem(p), wait])
      .then(([r]) => {
        setMaxed({ from, to: Math.round(r?.player?.ovr ?? pot) })
        setMode(null)
      })
      .catch((e) => {
        setItemErr(e.message)
        setMode('item')
      })
      .finally(() => setTrain(null))
  }
  if (train) return <EliteTraining name={p.name} from={train.from} to={train.to} />
  return (
    <div className="on-modal on-ps" role="dialog" aria-modal="true" aria-label={p.name} onClick={onClose}>
      <div className="on-ps-card gx-panel" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="on-result-x" onClick={onClose} aria-label="Fechar"><X size={16} /></button>
        <div className="on-ps-top">
          <FutCard p={p} club={club} size="sm" />
          <div className="on-ps-id">
            <h3>{p.name}</h3>
            <small>{positions}</small>
            <small>{p.age} anos{p.nat ? ` · ${p.nat}` : ''}{p.number != null ? ` · camisa ${p.number}` : ''}</small>
            {listed && <span className="on-ps-tag"><Gavel size={12} /> Em leilão</span>}
          </div>
        </div>
        {maxed && (
          <div className="on-ps-maxed" role="status">
            <GoldenWhistle size={34} />
            <span><b>Nível máximo atingido!</b><small>{maxed.from} → {maxed.to} com o treino de elite</small></span>
          </div>
        )}
        <div className={`on-ps-grow ${maxed ? 'is-maxed' : ''}`}>
          <span><small>Nota atual</small><b>{ovr}</b></span>
          <i aria-hidden="true"><TrendingUp size={18} /></i>
          <span className="is-pot"><small>Pode chegar a</small><b>{pot}</b></span>
          <em>{room > 0 ? `+${room} de evolução` : 'No auge'}</em>
          {/* barra até o potencial: cheia quando o jogador chega ao auge */}
          <span className="on-ps-bar" role="progressbar" aria-valuemin={40} aria-valuemax={pot} aria-valuenow={ovr}>
            <i className="is-pot" style={{ width: '100%' }} />
            <i style={{ width: `${pot > 40 ? Math.min(100, Math.max(0, ((ovr - 40) / (pot - 40)) * 100)) : 100}%` }} />
          </span>
        </div>
        <dl className="on-ps-stats">
          <div><dt>Valor</dt><dd>{money(p.value)}</dd></div>
          <div><dt>Salário</dt><dd>{money(p.wage)}/dia</dd></div>
          <div><dt>Contrato</dt><dd>{left <= 0 ? 'Último ano' : `+${left} temp.`}</dd></div>
          <div><dt>Condição</dt><dd>{Math.round(p.cond)}%</dd></div>
        </dl>

        {!mode && (
          <div className="on-ps-actions">
            <button type="button" className="gx-btn" disabled={busy || listed} onClick={() => setMode('auction')}><Gavel size={15} /> Leiloar</button>
            <button type="button" className="gx-btn-ghost" disabled={busy || left >= 3} onClick={() => setMode('renew')}><FileSignature size={15} /> Renovar</button>
            <button type="button" className="gx-btn-ghost" disabled={busy || listed} onClick={() => setMode('sell')}><UserMinus size={15} /> Dispensar</button>
            {whistle && (
              <button type="button" className="on-ps-item" disabled={busy || room <= 0} onClick={() => { setItemErr(''); setMode('item') }}>
                <GoldenWhistle size={22} /> {room > 0 ? 'Apito de Ouro' : 'Já no nível máximo'}
                {room > 0 && <em>{whistle.qty}</em>}
              </button>
            )}
          </div>
        )}
        {mode === 'item' && whistle && (
          <div className="on-ps-step on-ps-itemstep">
            <div className="on-ps-itemhead">
              <GoldenWhistle size={46} />
              <span><b>Apito de Ouro</b><small>Treino de elite: {ovr} → {pot} agora, sem gastar condição</small></span>
            </div>
            {whistle.qty > 0 ? (
              <>
                <small>Você tem {whistle.qty} {whistle.qty === 1 ? 'apito' : 'apitos'}. Usar 1 em {p.name}?</small>
                <button type="button" className="on-ps-item is-go" disabled={busy || room <= 0} onClick={startWhistle}><Sparkles size={15} /> Usar e treinar</button>
              </>
            ) : (
              <small>Você não tem Apito de Ouro. Compre na Loja → Itens ({whistle.price} diamantes).</small>
            )}
            {itemErr && <small className="on-ps-err">{itemErr}</small>}
            <button type="button" className="gx-btn-ghost" onClick={() => setMode(null)}>Voltar</button>
          </div>
        )}
        {mode === 'auction' && (
          <div className="on-ps-step">
            <small>Lance inicial · 1 hora no mercado</small>
            <div className="on-auc-steps" role="group" aria-label="Lance inicial">
              {AUCTION_STEPS.map(([v, label]) => <button key={v} type="button" className={step === v ? 'is-on' : ''} onClick={() => setStep(v)}>{label}</button>)}
            </div>
            <button type="button" className="gx-btn" disabled={busy} onClick={() => onAuction(p, startPrice)}><Gavel size={15} /> Leiloar por {money(startPrice)}</button>
            <button type="button" className="gx-btn-ghost" onClick={() => setMode(null)}>Voltar</button>
          </div>
        )}
        {mode === 'sell' && (
          <div className="on-ps-step">
            <small>Ele deixa o clube agora e volta ao mercado</small>
            <button type="button" className="gx-btn" disabled={busy} onClick={() => onSell(p)}><UserMinus size={15} /> Dispensar · +{money(p.sell ?? Math.round(p.value * 0.6))}</button>
            <button type="button" className="gx-btn-ghost" onClick={() => setMode(null)}>Voltar</button>
          </div>
        )}
        {mode === 'renew' && (
          <div className="on-ps-step">
            <small>Salário {money(p.wage)} → {money(wageFor(p.ovr, p.age))}/dia</small>
            {[1, 2, 3].filter((y) => left + y <= 3).map((y) => (
              <button key={y} type="button" className="gx-btn-ghost" disabled={busy} onClick={() => onRenew(p, y)}>
                +{y} temporada{y > 1 ? 's' : ''} · luva {money(wageFor(p.ovr, p.age) * 8 * y)}
              </button>
            ))}
            <button type="button" className="gx-btn-ghost" onClick={() => setMode(null)}>Voltar</button>
          </div>
        )}
      </div>
    </div>
  )
}

const STAGES = ['Aquecimento', 'Treino físico', 'Treino técnico', 'Treino tático', 'Avaliação final']

// Tela do treino de elite: barra que enche, etapas do treino e a nota subindo até o potencial.
function EliteTraining({ name, from, to }) {
  const [t, setT] = useState(0)
  const start = useRef(0)
  useEffect(() => {
    let raf = 0
    const tick = (now) => {
      if (!start.current) start.current = now
      setT(Math.min(1, (now - start.current) / 4000))
      raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [])
  const ease = 1 - (1 - t) ** 2
  const stage = STAGES[Math.min(STAGES.length - 1, Math.floor(t * STAGES.length))]
  return (
    <div className="on-modal on-ps on-elite" role="dialog" aria-modal="true" aria-label={`Treino de elite de ${name}`}>
      <div className="on-elite-card gx-panel">
        <span className="on-elite-art"><GoldenWhistle size={88} /></span>
        <small>Treino de elite</small>
        <h3>{name}</h3>
        <b className="on-elite-ovr">{Math.round(from + (to - from) * ease)}</b>
        <span className="on-elite-bar" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(t * 100)}>
          <i style={{ width: `${t * 100}%` }} />
        </span>
        <em>{stage}…</em>
      </div>
    </div>
  )
}
