import { useCallback, useEffect, useRef, useState } from 'react'
import { ArrowUp, Building2, Check, Clock, Coins, Crosshair, Gem, Goal, Plus, X, Dumbbell, Footprints, GraduationCap, Hand, HeartPulse, Landmark, MapPin, Palette, Receipt, Save, Shield, Star, Timer, Trophy, User, Users, Waypoints, Zap } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import MiniGame from './components/MiniGames'
import { GAMES } from './components/miniGamesInfo'
import OnlineCrest from './components/OnlineCrest'
import { PlayerFace } from './components/PlayerFut'
import { buildOnline, buyOnlineTrainEnergy, convertOnlineCoins, fetchOnlineClub, fetchOnlineFinance, fetchOnlineSquad, finishOnlineTraining, saveOnlineIdentity, startOnlineTraining } from './services/onlineApi'
import { CREST_PATTERNS, CREST_SHAPES, cardTier, money, moneyShort } from './onlineUtils'

const BUILDINGS = [
  { id: 'stadium', label: 'Estádio', Icon: Landmark, effect: (n) => `Bilheteria ${moneyShort(8000 + 3000 * n)}` },
  { id: 'training', label: 'Centro de treino', Icon: Dumbbell, effect: (n) => `+${n * 10}% evolução` },
  { id: 'medical', label: 'Departamento médico', Icon: HeartPulse, effect: (n) => `+${n * 5} condição/dia` },
  { id: 'youth', label: 'Categoria de base', Icon: GraduationCap, effect: (n) => `${n * 4}% revelação/dia` },
]
const KIND = { buy: 'Compra', sell: 'Venda', wage: 'Salários', gate: 'Bilheteria', build: 'Obra', renew: 'Renovação', coins: 'Investimento', prize: 'Prêmio' }
const GAME_ICON = { penalty: Goal, aim: Crosshair, passing: Waypoints, tackle: Shield, reaction: Hand, dribble: Footprints, timing: Timer }
const MODES = [
  { id: 'solo', label: 'Individual', Icon: User, max: 1, bonus: '+50%' },
  { id: 'group', label: 'Grupo', Icon: Users, max: 6, bonus: '100%' },
  { id: 'team', label: 'Coletivo', Icon: Trophy, max: 11, bonus: '65%' },
]
const PALETTE = ['#e63946', '#b91c1c', '#f97316', '#facc15', '#16a34a', '#0f766e', '#06b6d4', '#2563eb', '#1e3a8a', '#7c3aed', '#db2777', '#111827', '#64748b', '#ffffff']
const PATTERN_LABEL = { stripes: 'Listras', hoops: 'Faixas', plain: 'Liso', sash: 'Diagonal', halves: 'Metades', chevron: 'Chevron' }
const SHAPE_LABEL = { shield: 'Escudo', round: 'Redondo', diamond: 'Losango' }
const hours = (s) => (s >= 3600 ? `${Math.round(s / 3600)} h` : `${Math.round(s / 60)} min`)
const until = (iso) => {
  const ms = new Date(iso).getTime() - Date.now()
  if (ms <= 0) return 'concluindo'
  const m = Math.ceil(ms / 60000)
  return m >= 60 ? `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}` : `${m} min`
}

// Energia de treino: quando os treinos grátis do dia acabam, cada treino gasta 1 de energia do estoque.
function EnergySheet({ club, busy, onBuy, onClose }) {
  const t = club.train
  const packs = Object.entries(t.packs || {}).sort((a, b) => a[1][0] - b[1][0])
  return (
    <div className="on-modal" role="dialog" aria-modal="true" aria-label="Energia de treino">
      <div className="on-sheet">
        <button type="button" className="on-result-x" onClick={onClose} aria-label="Fechar"><X size={16} /></button>
        <small className="on-sheet-kicker"><Zap size={13} /> Energia de treino</small>
        <div className="on-energy-now"><b>{t.energy}</b><span>em estoque</span><em>{t.free_left} de {t.max} treinos grátis hoje</em></div>
        <ul className="on-energy-how">
          <li><Clock size={14} /> {t.max} treinos grátis todo dia</li>
          <li><Coins size={14} /> 1 energia por {t.coin_cost} moedas</li>
          <li><Gem size={14} /> Pacotes com diamantes, aqui ou na Loja</li>
        </ul>
        <div className="on-energy-packs">
          <button type="button" className="gx-btn-ghost" disabled={busy || (club.coins?.wallet ?? 0) < t.coin_cost} onClick={() => onBuy('coin')}>
            <b><Zap size={13} /> 1</b><small><Coins size={11} /> {t.coin_cost}</small>
          </button>
          {packs.map(([id, [energy, price]]) => (
            <button key={id} type="button" className="gx-btn-ghost" disabled={busy || (club.coins?.diamonds ?? 0) < price} onClick={() => onBuy(id)}>
              <b><Zap size={13} /> {energy}</b><small><Gem size={11} /> {price}</small>
            </button>
          ))}
        </div>
        <small className="on-energy-wallet"><Coins size={11} /> {club.coins?.wallet ?? 0} · <Gem size={11} /> {club.coins?.diamonds ?? 0}</small>
      </div>
    </div>
  )
}

// Passo 2 do treino: quem treina. Abre ao tocar em um mini-game.
function TrainSheet({ game, club, squad, colors, busy, onStart, onClose }) {
  const info = GAMES[game]
  const modes = info.solo ? MODES.slice(0, 1) : MODES
  const [mode, setMode] = useState('solo')
  const [picked, setPicked] = useState([])
  const max = MODES.find((m) => m.id === mode).max
  const fit = (p) => !p.injured && p.cond >= 30
  const starters = new Set(Object.values(squad.lineup?.slots || {}))
  const changeMode = (id) => {
    setMode(id)
    const cap = MODES.find((m) => m.id === id).max
    if (id === 'team') setPicked(squad.players.filter((p) => starters.has(p.id) && fit(p)).slice(0, 11).map((p) => p.id))
    else setPicked((list) => list.slice(0, cap))
  }
  const toggle = (id) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : max === 1 ? [id] : p.length >= max ? p : [...p, id]))
  const free = club.train.free_left > 0
  const Icon = GAME_ICON[game]
  return (
    <div className="on-modal" role="dialog" aria-modal="true" aria-label={`Treino de ${info.title}`}>
      <div className="on-sheet on-train-sheet">
        <button type="button" className="on-result-x" onClick={onClose} aria-label="Fechar"><X size={16} /></button>
        <header className={`on-train-sheet-head g-${game}`}>
          <Icon size={26} />
          <div><strong>{info.title}</strong><small>Evolui {info.group}</small></div>
        </header>
        {modes.length > 1 && (
          <div className="on-seg on-seg-3" role="group" aria-label="Tipo de treino">
            {modes.map(({ id, label, Icon: I, bonus }) => (
              <button key={id} type="button" className={mode === id ? 'is-on' : ''} onClick={() => changeMode(id)}><I size={14} /> {label}<small>{bonus}</small></button>
            ))}
          </div>
        )}
        <h3 className="on-h">{max === 1 ? 'Escolha quem treina' : `Escolha até ${max} jogadores`} <small>{picked.length}/{max}</small></h3>
        <div className="on-train-pick">
          {squad.players.map((p) => (
            <button key={p.id} type="button" disabled={!fit(p)} className={`on-chip2 t-${cardTier(p)} ${picked.includes(p.id) ? 'is-on' : ''}`} onClick={() => toggle(p.id)}>
              <PlayerFace seed={p.name} colors={colors} size={34} />
              <span><strong>{p.star && <Star size={10} />}{p.name}</strong><small>{p.pos} · {Math.round(p.ovr)} · {p.cond}%</small></span>
              <i className="on-xp"><em style={{ width: `${p.xp?.[info.gi] ?? 0}%` }} /></i>
              {picked.includes(p.id) && <b className="on-chip2-check"><Check size={12} /></b>}
            </button>
          ))}
        </div>
        <button type="button" className="gx-btn on-train-start" disabled={busy || !picked.length} onClick={() => onStart(game, picked)}>
          <Dumbbell size={16} /> {picked.length ? 'Começar treino' : max === 1 ? 'Escolha um jogador' : 'Escolha os jogadores'}
          {picked.length > 0 && <em>{free ? 'Grátis' : <><Zap size={12} /> 1</>}</em>}
        </button>
      </div>
    </div>
  )
}

function Training({ club, colors, notify, onChanged }) {
  const [squad, setSquad] = useState(null)
  const [sheet, setSheet] = useState(null) // id do mini-game aberto ou 'energy'
  const [session, setSession] = useState(null)
  const [result, setResult] = useState(null)
  const [busy, setBusy] = useState(false)
  const doneRef = useRef(false)
  useEffect(() => {
    fetchOnlineSquad().then(setSquad).catch(() => setSquad({ players: [] }))
  }, [result])
  const t = club.train
  const canTrain = t.free_left > 0 || t.energy > 0
  const start = (game, picked) => {
    setBusy(true)
    startOnlineTraining(game, picked)
      .then((s) => {
        doneRef.current = false
        setSheet(null)
        setSession({ ...s, t0: Date.now() })
        setResult(null)
        onChanged?.()
      })
      .catch((e) => notify?.(e.message, 'alert'))
      .finally(() => setBusy(false))
  }
  const buy = (pack) => {
    setBusy(true)
    buyOnlineTrainEnergy(pack)
      .then(() => {
        notify?.('Energia de treino comprada', 'success')
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
        setResult(await finishOnlineTraining(session.session, score))
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
          <header><Trophy size={18} /> <b>{Math.round(result.score * 100)}%</b><small>{GAMES[Object.keys(GAMES).find((k) => GAMES[k].gi === result.group - 1)]?.group}</small></header>
          <ul>
            {result.players.map((p) => (
              <li key={p.id}>
                <span>{p.name}</span>
                <em>+{p.gain} XP</em>
                {Number(p.ovr) > Number(p.before) && <b><ArrowUp size={12} /> {Number(p.ovr).toFixed(1)}</b>}
              </li>
            ))}
          </ul>
        </div>
      )}
      <div className="on-train-bar">
        <span><small>Treinos grátis hoje</small><b>{t.free_left}/{t.max}</b></span>
        <span><small>Energia</small><b><Zap size={14} /> {t.energy}</b></span>
        <button type="button" className="gx-btn-ghost" onClick={() => setSheet('energy')}><Plus size={15} /> Energia</button>
      </div>
      <h3 className="on-h">Escolha o treino</h3>
      <div className="on-games">
        {Object.entries(GAMES).map(([id, g]) => {
          const Icon = GAME_ICON[id]
          return (
            <button key={id} type="button" className={`on-game g-${id}`} onClick={() => setSheet(canTrain ? id : 'energy')}>
              <Icon size={20} />
              <b>{g.title}</b>
              <small>{g.group}{g.solo ? ' · individual' : ''}</small>
            </button>
          )
        })}
      </div>
      {sheet === 'energy' && <EnergySheet club={club} busy={busy} onBuy={buy} onClose={() => setSheet(null)} />}
      {sheet && sheet !== 'energy' && squad && (
        <TrainSheet game={sheet} club={club} squad={squad} colors={colors} busy={busy} onStart={start} onClose={() => setSheet(null)} />
      )}
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
              <small>{effect(lv)}{lv < 5 && <em> → {effect(lv + 1)}</em>}</small>
            </div>
            {building ? (
              <span className="on-build-timer"><Building2 size={14} /> {until(club.build.until)}</span>
            ) : lv >= 5 ? (
              <span className="on-build-timer">MAX</span>
            ) : (
              <button type="button" className="gx-btn" disabled={busy || Boolean(club.build) || club.cash - club.reserved < cost.cost} onClick={() => build(id)}>
                {moneyShort(cost.cost)}
                <small>{hours(cost.time)}</small>
              </button>
            )}
          </article>
        )
      })}
    </div>
  )
}

function Finance({ club, notify, onChanged }) {
  const [data, setData] = useState(null)
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    fetchOnlineFinance().then(setData).catch(() => setData({ ledger: [], news: [] }))
  }, [club])
  const c = club.coins
  const room = Math.max(0, Math.min(c.cap - c.converted, c.wallet ?? 0))
  const [ask, setAsk] = useState(null)
  const invest = (n) => {
    if (!n) return
    setAsk(null)
    setBusy(true)
    convertOnlineCoins(n)
      .then(() => {
        notify?.(`+${money(n * c.rate)} no caixa`, 'success')
        onChanged?.()
      })
      .catch((err) => notify?.(err.message, 'alert'))
      .finally(() => setBusy(false))
  }
  return (
    <div className="on-finance">
      <div className="on-wallet">
        <span><small>Caixa</small><b>{moneyShort(club.cash)}</b></span>
        <span><small>Salários/dia</small><b>{moneyShort(club.wages)}</b></span>
        <span className={club.debt > 0 ? 'is-bad' : ''}><small>Dívida</small><b>{moneyShort(club.debt)}</b></span>
      </div>
      <div className="on-invest">
        <header>
          <Coins size={22} />
          <div><b>Investir no clube</b><small>{c.wallet ?? 0} moedas · 1 = {money(c.rate)} · limite {Math.max(0, c.cap - c.converted)}</small></div>
        </header>
        <div className="on-invest-opts">
          {[10, 50, 100].map((n) => (
            <button key={n} type="button" className="gx-btn-ghost" disabled={busy || room < n} onClick={() => setAsk(n)}>
              <b><Coins size={12} /> {n}</b><small>{moneyShort(n * c.rate)}</small>
            </button>
          ))}
          <button type="button" className="gx-btn" disabled={busy || room < 1} onClick={() => setAsk(room)}>
            <b>Tudo</b><small>{moneyShort(room * c.rate)}</small>
          </button>
        </div>
      </div>
      {ask && (
        <div className="on-modal" role="dialog" aria-modal="true" aria-label="Confirmar investimento">
          <div className="on-sheet on-confirm">
            <small className="on-sheet-kicker"><Coins size={13} /> Investir no clube</small>
            <div className="on-confirm-swap">
              <span><b><Coins size={16} /> {ask}</b><small>moedas da conta</small></span>
              <i>→</i>
              <span><b>{money(ask * c.rate)}</b><small>no caixa do clube</small></span>
            </div>
            <p>Depois de investidas, as moedas não voltam para a conta.</p>
            <div className="on-modal-actions">
              <button type="button" className="gx-btn-ghost" onClick={() => setAsk(null)}>Cancelar</button>
              <button type="button" className="gx-btn" disabled={busy} onClick={() => invest(ask)}>Confirmar</button>
            </div>
          </div>
        </div>
      )}
      <h3 className="on-h">Extrato</h3>
      <ul className="on-ledger">
        {(data?.ledger || []).length === 0 && <li className="is-empty">Sem movimentações</li>}
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

// Identidade: nome, sigla, estádio, cores, desenho e formato do escudo, com prévia ao vivo.
function Identity({ status, notify, onStatus }) {
  const saved = status.club
  const [form, setForm] = useState(() => ({
    name: saved.name,
    short: saved.short,
    stadium: saved.colors?.stadium || `Arena ${saved.short}`,
    a: saved.colors?.a || '#1d3557',
    b: saved.colors?.b || '#ffffff',
    pattern: saved.colors?.pattern || 'stripes',
    shape: saved.colors?.shape || 'shield',
  }))
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const set = (k, v) => setForm((f) => ({ ...f, [k]: v }))
  const preview = { id: saved.id, name: form.name, short: form.short.toUpperCase() || '?', colors: { a: form.a, b: form.b, pattern: form.pattern, shape: form.shape } }
  const base = { name: saved.name, short: saved.short, stadium: saved.colors?.stadium, a: saved.colors?.a, b: saved.colors?.b, pattern: saved.colors?.pattern || 'stripes', shape: saved.colors?.shape || 'shield' }
  const changes = Object.fromEntries(Object.entries(form).filter(([k, v]) => v !== base[k]))
  const dirty = Object.keys(changes).length > 0
  const save = (e) => {
    e.preventDefault()
    if (!dirty || busy) return
    setBusy(true)
    setError('')
    saveOnlineIdentity(changes)
      .then((s) => {
        onStatus?.(s)
        notify?.('Identidade do clube atualizada', 'success')
      })
      .catch((err) => setError(err.message))
      .finally(() => setBusy(false))
  }
  return (
    <form className="on-identity" onSubmit={save}>
      <div className="on-id-preview" style={{ '--a': form.a, '--b': form.b }}>
        <OnlineCrest club={preview} size={96} />
        <strong>{form.name || 'Seu clube'}</strong>
        <small><MapPin size={11} /> {form.stadium}</small>
        <span className="on-id-kit"><i style={{ background: form.a }} /><i style={{ background: form.b }} /></span>
      </div>
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}
      <div className="on-id-fields">
        <label className="is-wide">Nome do clube<input value={form.name} maxLength={24} onChange={(e) => set('name', e.target.value)} /></label>
        <label>Sigla<input value={form.short} maxLength={4} onChange={(e) => set('short', e.target.value.replace(/[^A-Za-z0-9]/g, '').toUpperCase())} /></label>
        <label className="is-wide2">Estádio<input value={form.stadium} maxLength={28} onChange={(e) => set('stadium', e.target.value)} /></label>
      </div>
      {[['a', 'Cor principal'], ['b', 'Cor secundária']].map(([k, label]) => (
        <div key={k} className="on-id-row">
          <h3 className="on-h"><Palette size={13} /> {label}</h3>
          <div className="on-swatches">
            {PALETTE.map((c) => <button key={c} type="button" className={form[k] === c ? 'is-on' : ''} style={{ background: c }} onClick={() => set(k, c)} aria-label={c} />)}
            <label className="on-swatch-custom" style={{ background: form[k] }}><input type="color" value={form[k]} onChange={(e) => set(k, e.target.value)} aria-label={`${label} personalizada`} /></label>
          </div>
        </div>
      ))}
      <div className="on-id-row">
        <h3 className="on-h">Escudo</h3>
        <div className="on-crest-opts">
          {CREST_PATTERNS.map((pt) => (
            <button key={pt} type="button" className={form.pattern === pt ? 'is-on' : ''} onClick={() => set('pattern', pt)} aria-label={PATTERN_LABEL[pt]}>
              <OnlineCrest club={{ ...preview, id: `p${pt}`, short: '', colors: { ...preview.colors, pattern: pt } }} size={34} />
            </button>
          ))}
        </div>
        <div className="on-seg on-seg-3" role="group" aria-label="Formato">
          {CREST_SHAPES.map((sh) => <button key={sh} type="button" className={form.shape === sh ? 'is-on' : ''} onClick={() => set('shape', sh)}>{SHAPE_LABEL[sh]}</button>)}
        </div>
      </div>
      <button type="submit" className="gx-btn on-id-save" disabled={!dirty || busy}><Save size={16} /> {busy ? 'Salvando…' : 'Salvar'}</button>
    </form>
  )
}

// CLUBE: treino (mini-games), estrutura, finanças e identidade.
export default function OnlineClub({ notify, onChanged, onStatus, status, initialView }) {
  const [club, setClub] = useState(null)
  const [error, setError] = useState('')
  const [view, setView] = useState(initialView || 'train')
  const load = useCallback(() => fetchOnlineClub().then(setClub).catch((e) => setError(e.message)), [])
  useEffect(() => {
    load()
  }, [load])
  const changed = () => {
    load()
    onChanged?.()
  }
  if (!club) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={6} />
  const tabs = [
    ['train', 'Treino', Dumbbell],
    ['build', 'Estrutura', Building2],
    ['money', 'Finanças', Receipt],
    ['identity', 'Identidade', Palette],
  ]
  return (
    <section className="on-clubtab">
      <div className="on-seg on-seg-4" role="tablist" aria-label="Clube">
        {tabs.map(([id, label, Icon]) => (
          <button key={id} type="button" role="tab" aria-selected={view === id} className={view === id ? 'is-on' : ''} onClick={() => setView(id)}><Icon size={14} /> {label}</button>
        ))}
      </div>
      {view === 'train' && <Training club={club} colors={status?.club?.colors} notify={notify} onChanged={changed} />}
      {view === 'build' && <Structure club={club} notify={notify} onChanged={changed} />}
      {view === 'money' && <Finance club={club} notify={notify} onChanged={changed} />}
      {view === 'identity' && status?.club && <Identity status={status} notify={notify} onStatus={onStatus} />}
    </section>
  )
}
