import { useCallback, useEffect, useState } from 'react'
import { Check, CircleAlert, Clock, Coins, Flame, Gem, Package, Sparkles, Wallet, X, Zap } from 'lucide-react'
import { Skeleton } from '../../../components/ui/feedback'
import { useAudio } from '../../audio/AudioContext'
import { drawPack, fetchPacks } from '../../online/services/onlineApi'
import BigTimeCard, { BigTimeFacts } from '../../online/components/BigTime'
import { FutCard } from '../../online/components/PlayerFut'
import { btDate, btMatch } from '../../online/components/bigtimeUtils'
import GoldenWhistle from '../../online/components/GoldenWhistle'
import { fmt } from './storeUtils'
import './packs.css'

// CAIXAS BIG TIME: cada caixa tem um número fixo de prêmios. Cada tiragem custa diamantes e o prêmio sai da caixa
// (sorteio sem reposição, por técnico). Carta que o clube já tem não sai de novo. A loja não mostra quantidades nem chances.

const PRIZE = {
  energy: { Icon: Zap, label: (q) => `${q} de energia de treino` },
  coins: { Icon: Coins, label: (q) => `${fmt(q)} moedas` },
  cash: { Icon: Wallet, label: (q) => `$ ${fmt(q)} no caixa do clube` },
  whistle: { Icon: null, label: (q) => `${q} Apito${q > 1 ? 's' : ''} de Ouro` },
}

// Contador: "6d 23:59:12" (ou "23:59:12" no último dia)
const two = (n) => String(n).padStart(2, '0')
function left(ms) {
  if (!(ms > 0)) return 'encerrada'
  const t = Math.floor(ms / 1000)
  const d = Math.floor(t / 86400)
  const hms = `${two(Math.floor((t % 86400) / 3600))}:${two(Math.floor((t % 3600) / 60))}:${two(t % 60)}`
  return d > 0 ? `${d}d ${hms}` : hms
}

function useNow(ms = 1000) {
  const [now, setNow] = useState(() => Date.now())
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), ms)
    return () => clearInterval(id)
  }, [ms])
  return now
}

function PrizeIcon({ kind, size = 22 }) {
  if (kind === 'whistle') return <GoldenWhistle size={size + 6} />
  const P = PRIZE[kind]?.Icon || Package
  return <P size={size} />
}

// Banner da caixa (vitrine): cartas em leque, contagem regressiva e quantos prêmios ainda restam.
function PackBanner({ pack, now, onOpen }) {
  const cards = pack.items.filter((i) => i.kind === 'bigtime')
  const fan = cards.slice(0, 3)
  return (
    <button type="button" className="pk-banner" onClick={onOpen}>
      <span className="pk-banner-bg" aria-hidden="true" />
      <span className="pk-banner-txt">
        <small><Flame size={12} /> Big Time · caixa especial</small>
        <strong>{pack.title}</strong>
        {pack.subtitle && <em>{pack.subtitle}</em>}
        <span className="pk-banner-meta">
          <span className="pk-clock"><Clock size={12} /> Termina em {left(new Date(pack.ends_at).getTime() - now)}</span>
          <span>{cards.length} Big Time · cartas base · itens</span>
        </span>
        <span className="pk-banner-cta"><Gem size={14} /> {fmt(pack.price)} por tiragem</span>
      </span>
      <span className={`pk-fan n-${fan.length}`} aria-hidden="true">
        {fan.map((i, k) => <span key={i.id} style={{ '--k': k - (fan.length - 1) / 2 }}><BigTimeCard bt={i.bt} size="sm" delay={k * 90} /></span>)}
      </span>
    </button>
  )
}

// Revelação: tela escura, a caixa treme, explode em vermelho e mostra o prêmio.
function Reveal({ prize, onClose, onAgain, canAgain, price }) {
  const [stage, setStage] = useState(0)
  const { playSfx } = useAudio()
  useEffect(() => {
    const t1 = setTimeout(() => setStage(1), 900)
    const t2 = setTimeout(() => { setStage(2); playSfx(prize.kind === 'bigtime' ? 'levelup' : 'reward') }, 1500)
    return () => { clearTimeout(t1); clearTimeout(t2) }
  }, [prize, playSfx])
  const bt = prize.bt
  return (
    <div className={`pk-reveal s-${stage} ${bt ? 'is-bt' : ''}`} role="dialog" aria-modal="true" aria-label="Prêmio da caixa">
      <span className="pk-reveal-rays" aria-hidden="true" />
      {stage < 2 ? (
        <span className="pk-box" aria-hidden="true"><Package size={74} /></span>
      ) : (
        <div className="pk-prize">
          {bt ? (
            <>
              <small className="pk-prize-kicker"><Sparkles size={13} /> Big Time!</small>
              <BigTimeCard bt={bt} size="lg" />
              <p>{btMatch(bt)} · {btDate(bt.match_date)}</p>
              <p className="pk-prize-note">Chega ao seu elenco com overall {bt.start_rating}. Treine para levar ao máximo, {bt.rating}.</p>
            </>
          ) : prize.card ? (
            <>
              <small className="pk-prize-kicker is-base">Carta base</small>
              <div className="pk-prize-fut"><FutCard p={prize.card} size="md" /></div>
              <p className="pk-prize-note">Já está no seu elenco. Se não quiser, dispense pela ficha dele.</p>
            </>
          ) : (
            <>
              <span className="pk-prize-ico"><PrizeIcon kind={prize.kind} size={44} /></span>
              <strong>{PRIZE[prize.kind]?.label(prize.qty)}</strong>
              <p className="pk-prize-note">Entregue agora.</p>
            </>
          )}
          <div className="pk-prize-actions">
            <button type="button" className="pk-close" onClick={onClose}>Fechar</button>
            {canAgain && <button type="button" className="pk-again" onClick={onAgain}>Abrir de novo · <Gem size={13} /> {fmt(price)}</button>}
          </div>
        </div>
      )}
    </div>
  )
}

// Detalhe da caixa: tudo o que tem dentro e o que já saiu para você (sem quantidades).
function PackDetail({ pack, diamonds, now, busy, error, onDraw, onClose }) {
  const [card, setCard] = useState(null)
  const cards = pack.items.filter((i) => i.kind === 'bigtime')
  const base = pack.items.filter((i) => i.kind === 'player' && i.player)
  // itens iguais aparecem uma vez; riscado só quando todos daquele tipo já saíram
  const other = Object.values(pack.items.filter((i) => !['bigtime', 'player'].includes(i.kind)).reduce((m, i) => {
    const k = `${i.kind}:${i.qty}`
    m[k] = m[k] ? { ...m[k], got: m[k].got && i.got } : i
    return m
  }, {}))
  const poor = diamonds < pack.price
  return (
    <div className="pk-sheet" role="dialog" aria-modal="true" aria-label={pack.title} onClick={onClose}>
      <div className="pk-sheet-card" onClick={(e) => e.stopPropagation()}>
        <header>
          <span>
            <small><Flame size={12} /> Big Time</small>
            <h3>{pack.title}</h3>
            <span className="pk-clock is-big"><Clock size={13} /> Termina em {left(new Date(pack.ends_at).getTime() - now)}</span>
          </span>
          <button type="button" className="pk-x" onClick={onClose} aria-label="Fechar"><X size={18} /></button>
        </header>
        <div className="pk-sheet-body">
          <p className="pk-rule">Cada tiragem tira um prêmio da caixa, ao acaso. O que saiu não volta, e carta que você já tem não sai de novo. A Big Time chega com overall menor: treine para levar ao máximo.</p>
          <h4>Cartas Big Time</h4>
          <div className="pk-cards">
            {cards.map((i) => (
              <div key={i.id} className={`pk-cardslot ${i.got ? 'is-out' : ''}`}>
                <BigTimeCard bt={i.bt} size="sm" onClick={() => setCard(i.bt)} />
                {i.got && <em>Já é sua</em>}
              </div>
            ))}
          </div>
          {base.length > 0 && (
            <>
              <h4>Cartas base</h4>
              <ul className="pk-base">
                {base.map((i) => (
                  <li key={i.id} className={i.got ? 'is-out' : ''}>
                    <b>{i.player.ovr}</b><small>{i.player.pos}</small><span>{i.player.name}</span>
                    {i.got && <Check size={13} className="pk-got" aria-label="Já ganhou" />}
                  </li>
                ))}
              </ul>
            </>
          )}
          {other.length > 0 && (
            <>
              <h4>Itens</h4>
              <ul className="pk-others">
                {other.map((i) => (
                  <li key={i.id} className={i.got ? 'is-out' : ''}>
                    <span className="pk-others-ico"><PrizeIcon kind={i.kind} size={18} /></span>
                    <span>{PRIZE[i.kind]?.label(i.qty)}</span>
                    {i.got && <em className="pk-gotlabel"><Check size={12} /> Já ganhou</em>}
                  </li>
                ))}
              </ul>
            </>
          )}
          {error && <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p>}
        </div>
        <footer>
          <span className="pk-wallet"><Gem size={14} /> {fmt(diamonds)}</span>
          <button type="button" className="pk-draw" disabled={busy || pack.empty || poor} onClick={onDraw}>
            {pack.empty ? 'Você já tirou tudo' : poor ? 'Diamantes insuficientes' : busy ? 'Abrindo…' : <>Abrir · <Gem size={15} /> {fmt(pack.price)}</>}
          </button>
        </footer>
        {card && (
          <div className="pk-cardview" onClick={() => setCard(null)}>
            <div onClick={(e) => e.stopPropagation()}>
              <BigTimeCard bt={card} size="lg" />
              <p className="pk-rule">Overall máximo {card.rating}. Chega com {card.start_rating} e evolui com treino.</p>
              <BigTimeFacts bt={card} />
              <button type="button" className="gx-btn-ghost" onClick={() => setCard(null)}>Voltar</button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

export default function PacksTab({ onChanged, onEmpty }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [openId, setOpenId] = useState(null)
  const [busy, setBusy] = useState(false)
  const [prize, setPrize] = useState(null)
  const now = useNow()
  const load = useCallback(() => fetchPacks().then(setData).catch((e) => setError(e.message)), [])
  useEffect(() => { load() }, [load])
  if (!data) return error ? <p className="sh-msg is-error"><CircleAlert size={14} /> {error}</p> : <Skeleton rows={3} />
  if (!data.enabled) return null
  const pack = data.packs.find((p) => p.id === openId)
  const draw = () => {
    setBusy(true)
    setError('')
    drawPack(openId)
      .then((r) => {
        setPrize(r.prize)
        setData(r.store)
        onChanged?.()
      })
      .catch((e) => setError(e.message))
      .finally(() => setBusy(false))
  }
  return (
    <section className="pk">
      {data.packs.length === 0 ? (
        <div className="pk-empty">
          <Flame size={30} />
          <b>Nenhuma caixa Big Time agora</b>
          <small>Toda semana chegam novas atuações históricas. Volte em breve.</small>
          {onEmpty && <button type="button" className="gx-btn-ghost" onClick={onEmpty}>Ver energia e itens</button>}
        </div>
      ) : (
        data.packs.map((p) => <PackBanner key={p.id} pack={p} now={now} onOpen={() => { setError(''); setOpenId(p.id) }} />)
      )}
      {!data.has_club && data.packs.length > 0 && <p className="sh-msg">As cartas Big Time vão para o elenco do modo Online. Entre no modo Online para abrir as caixas.</p>}
      {pack && <PackDetail pack={pack} diamonds={data.diamonds} now={now} busy={busy} error={error} onDraw={draw} onClose={() => setOpenId(null)} />}
      {prize && (
        <Reveal
          prize={prize}
          price={pack?.price}
          canAgain={Boolean(pack && !pack.empty && data.diamonds >= pack.price)}
          onClose={() => setPrize(null)}
          onAgain={() => { setPrize(null); draw() }}
        />
      )}
    </section>
  )
}
