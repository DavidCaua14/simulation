import { useCallback, useEffect, useRef, useState } from 'react'
import { Building2, Coins, Dumbbell, GraduationCap, HeartPulse, Landmark, Receipt, Star, Trophy, Zap } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import MiniGame from './components/MiniGames'
import { GAMES } from './components/miniGamesInfo'
import { buildOnline, convertOnlineCoins, fetchOnlineClub, fetchOnlineFinance, fetchOnlineSquad, finishOnlineTraining, startOnlineTraining } from './services/onlineApi'
import { cardTier, money } from './onlineUtils'

const BUILDINGS = [
  { id: 'stadium', label: 'Estádio', Icon: Landmark, effect: (n) => `Bilheteria de $ ${(8000 + 3000 * n).toLocaleString('pt-BR')} por jogo em casa` },
  { id: 'training', label: 'Centro de treino', Icon: Dumbbell, effect: (n) => `+${n * 10}% de experiência nos treinos` },
  { id: 'medical', label: 'Departamento médico', Icon: HeartPulse, effect: (n) => `+${n * 5} de condição por dia` },
  { id: 'youth', label: 'Categoria de base', Icon: GraduationCap, effect: (n) => `${n * 4}% de chance por dia de revelar um jovem` },
]
const KIND = { buy: 'Compra', sell: 'Venda', wage: 'Salários', gate: 'Bilheteria', build: 'Obra', renew: 'Renovação', coins: 'Moedas', prize: 'Prêmio' }
const hours = (s) => (s >= 3600 ? `${Math.round(s / 3600)} h` : `${Math.round(s / 60)} min`)
const left = (iso) => {
  const ms = new Date(iso).getTime() - Date.now()
  if (ms <= 0) return 'concluindo'
  const m = Math.ceil(ms / 60000)
  return m >= 60 ? `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}` : `${m} min`
}

function Training({ club, notify, onChanged }) {
  const [squad, setSquad] = useState(null)
  const [game, setGame] = useState('timing')
  const [picked, setPicked] = useState([])
  const [session, setSession] = useState(null)
  const [result, setResult] = useState(null)
  const [busy, setBusy] = useState(false)
  const doneRef = useRef(false)
  useEffect(() => {
    fetchOnlineSquad().then(setSquad).catch(() => setSquad({ players: [] }))
  }, [result])
  const left = club.train.max - club.train.used
  const toggle = (id) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : p.length >= 6 ? p : [...p, id]))
  const start = () => {
    setBusy(true)
    startOnlineTraining(game, picked)
      .then((s) => {
        doneRef.current = false
        setSession({ ...s, t0: Date.now() })
        setResult(null)
        onChanged?.()
      })
      .catch((e) => notify?.(e.message, 'alert'))
      .finally(() => setBusy(false))
  }
  const finish = useCallback(
    async (score) => {
      if (doneRef.current) return
      doneRef.current = true
      const wait = 9000 - (Date.now() - session.t0) // o servidor recusa sessões com menos de 8 s
      if (wait > 0) await new Promise((r) => setTimeout(r, wait))
      try {
        const r = await finishOnlineTraining(session.session, score)
        setResult(r)
        setPicked([])
      } catch (e) {
        notify?.(e.message, 'alert')
      } finally {
        setSession(null)
        onChanged?.()
      }
    },
    [session, notify, onChanged],
  )

  if (session) {
    return (
      <div className="on-train-play">
        <MiniGame game={session.game} onDone={finish} />
      </div>
    )
  }
  return (
    <div className="on-train">
      {result && (
        <div className="on-train-result">
          <Trophy size={20} />
          <div>
            <b>Treino concluído: {Math.round(result.score * 100)}%</b>
            <ul>
              {result.players.map((p) => (
                <li key={p.id}>{p.name}: +{p.gain} de experiência{p.gain > 0 && p.xp < p.gain ? ' · subiu de nível!' : ''} (nota {Number(p.ovr).toFixed(1)})</li>
              ))}
            </ul>
          </div>
        </div>
      )}
      <div className="on-games">
        {Object.entries(GAMES).map(([id, g]) => (
          <button key={id} type="button" className={`on-game g-${id} ${game === id ? 'is-on' : ''}`} onClick={() => setGame(id)} aria-pressed={game === id}>
            <small>{g.group}</small>
            <b>{g.title}</b>
          </button>
        ))}
      </div>
      <p className="on-hint">
        <Zap size={13} /> {left} de {club.train.max} treinos hoje. Cada treino gasta {club.train.cond_cost}% de condição de quem treina.
        {club.match_today && <b className="on-warn-txt"> Seu time joga hoje: evite cansar os titulares.</b>}
      </p>
      <h3 className="gx-subtitle">Quem treina ({picked.length}/6)</h3>
      {!squad ? (
        <Skeleton rows={4} />
      ) : (
        <div className="on-train-pick">
          {squad.players.map((p) => {
            const g = { timing: 3, reaction: 0, passing: 1, aim: 2 }[game]
            const out = p.injured || p.cond < 30
            return (
              <button key={p.id} type="button" disabled={out} className={`on-chip t-${cardTier(p.ovr, p.star)} ${picked.includes(p.id) ? 'is-on' : ''}`} onClick={() => toggle(p.id)}>
                <b>{Math.round(p.ovr)}</b>
                <span>{p.star && <Star size={10} />}{p.name}<small>{p.pos} · {p.cond}%</small></span>
                <i className="on-xp" title={`Experiência no grupo: ${p.xp?.[g] ?? 0}/100`}><em style={{ width: `${p.xp?.[g] ?? 0}%` }} /></i>
              </button>
            )
          })}
        </div>
      )}
      <button type="button" className="gx-btn on-train-go" disabled={busy || !picked.length || left <= 0} onClick={start}>
        <Dumbbell size={16} /> Treinar {GAMES[game].title}
      </button>
    </div>
  )
}

function Structure({ club, notify, onChanged }) {
  const [busy, setBusy] = useState(false)
  const build = (id) => {
    setBusy(true)
    buildOnline(id).then(() => onChanged?.()).catch((e) => notify?.(e.message, 'alert')).finally(() => setBusy(false))
  }
  return (
    <div className="on-builds">
      {BUILDINGS.map(({ id, label, Icon, effect }) => {
        const lv = Number(club.levels?.[id] || 0)
        const cost = club.costs?.[id]
        const building = club.build?.kind === id
        return (
          <article key={id} className={`on-build ${building ? 'is-building' : ''}`}>
            <span className="on-build-icon"><Icon size={26} /></span>
            <div className="on-build-info">
              <strong>{label}</strong>
              <span className="on-stars" aria-label={`Nível ${lv} de 5`}>{[1, 2, 3, 4, 5].map((n) => <i key={n} className={n <= lv ? 'is-on' : ''} />)}</span>
              <small>{effect(lv)}</small>
              {lv < 5 && <small className="is-next">Próximo: {effect(lv + 1)}</small>}
            </div>
            {building ? (
              <span className="on-build-timer"><Building2 size={14} /> {left(club.build.until)}</span>
            ) : lv >= 5 ? (
              <span className="on-build-timer">Máximo</span>
            ) : (
              <button type="button" className="gx-btn" disabled={busy || Boolean(club.build) || club.cash - club.reserved < cost.cost} onClick={() => build(id)}>
                {money(cost.cost)}
                <small>{hours(cost.time)}</small>
              </button>
            )}
          </article>
        )
      })}
      {club.build && <p className="on-hint"><Building2 size={13} /> Uma obra por vez.</p>}
    </div>
  )
}

function Finance({ club, notify, onChanged }) {
  const [data, setData] = useState(null)
  const [coins, setCoins] = useState('')
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    fetchOnlineFinance().then(setData).catch(() => setData({ ledger: [], news: [] }))
  }, [club])
  const c = club.coins
  const room = Math.max(0, c.cap - c.converted)
  const convert = (e) => {
    e.preventDefault()
    const n = Math.round(Number(coins))
    if (!n) return
    setBusy(true)
    convertOnlineCoins(n)
      .then(() => {
        setCoins('')
        notify?.(`${n} moedas viraram ${money(n * c.rate)} no caixa.`, 'success')
        onChanged?.()
      })
      .catch((err) => notify?.(err.message, 'alert'))
      .finally(() => setBusy(false))
  }
  return (
    <div className="on-finance">
      <div className="on-wallet">
        <span><small>Caixa</small><b>{money(club.cash)}</b></span>
        <span><small>Salários/dia</small><b>{money(club.wages)}</b></span>
        <span className={club.debt > 0 ? 'is-bad' : ''}><small>Dívida</small><b>{money(club.debt)}</b></span>
      </div>
      <form className="on-coins" onSubmit={convert}>
        <Coins size={22} />
        <div>
          <b>Moedas da conta → caixa</b>
          <small>1 moeda = {money(c.rate)} · você tem {c.wallet ?? 0} · ainda dá para converter {room} nesta temporada</small>
        </div>
        <input inputMode="numeric" value={coins} onChange={(e) => setCoins(e.target.value.replace(/\D/g, ''))} placeholder="0" aria-label="Moedas" />
        <button type="submit" className="gx-btn" disabled={busy || !coins || room <= 0}>Converter</button>
      </form>
      <h3 className="gx-subtitle">Avisos</h3>
      <ul className="on-feed">
        {(data?.news || []).length === 0 && <li className="on-hint">Nenhum aviso.</li>}
        {(data?.news || []).map((n, i) => <li key={i} className={`k-${n.kind}`}><small>{new Date(n.at).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}</small>{n.text}</li>)}
      </ul>
      <h3 className="gx-subtitle">Extrato</h3>
      <ul className="on-ledger">
        {(data?.ledger || []).map((x, i) => (
          <li key={i}>
            <span><b>{KIND[x.kind] || x.kind}</b><small>{x.note}</small></span>
            <em className={x.amount >= 0 ? 'is-in' : 'is-out'}>{x.amount >= 0 ? '+' : ''}{money(x.amount)}</em>
          </li>
        ))}
      </ul>
    </div>
  )
}

// CLUBE: treino (mini-games), estrutura, finanças e moedas.
export default function OnlineClub({ notify, onChanged }) {
  const [club, setClub] = useState(null)
  const [error, setError] = useState('')
  const [view, setView] = useState('train')
  const load = useCallback(() => fetchOnlineClub().then(setClub).catch((e) => setError(e.message)), [])
  useEffect(() => {
    load()
  }, [load])
  const changed = () => {
    load()
    onChanged?.()
  }
  if (!club) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={6} />
  return (
    <section className="on-clubtab">
      <div className="on-seg on-seg-3" role="tablist" aria-label="Clube">
        <button type="button" role="tab" aria-selected={view === 'train'} className={view === 'train' ? 'is-on' : ''} onClick={() => setView('train')}><Dumbbell size={15} /> Treino</button>
        <button type="button" role="tab" aria-selected={view === 'build'} className={view === 'build' ? 'is-on' : ''} onClick={() => setView('build')}><Building2 size={15} /> Estrutura</button>
        <button type="button" role="tab" aria-selected={view === 'money'} className={view === 'money' ? 'is-on' : ''} onClick={() => setView('money')}><Receipt size={15} /> Finanças</button>
      </div>
      {view === 'train' && <Training club={club} notify={notify} onChanged={changed} />}
      {view === 'build' && <Structure club={club} notify={notify} onChanged={changed} />}
      {view === 'money' && <Finance club={club} notify={notify} onChanged={changed} />}
    </section>
  )
}
