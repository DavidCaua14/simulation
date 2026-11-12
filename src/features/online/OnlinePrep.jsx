import { useState } from 'react'
import { Binoculars, Check, ChevronRight, Coins, Dumbbell, Flame, Megaphone, Shirt, X } from 'lucide-react'
import { Skeleton } from '../../components/ui/feedback'
import OnlineCrest from './components/OnlineCrest'
import { FutCard } from './components/PlayerFut'
import { fetchOnlineScout, sendOnlineTeamTalk } from './services/onlineApi'

const TALKS = [
  ['motivate', 'Motivar', 'Vamos para cima!'],
  ['focus', 'Concentrar', 'Atenção em cada lance.'],
  ['calm', 'Tranquilizar', 'Joguem o que sabem.'],
]
const TALK_LABEL = Object.fromEntries(TALKS.map(([id, label]) => [id, label]))
const STYLE = { defensive: 'Defensivo', neutral: 'Equilibrado', attacking: 'Ofensivo', counter: 'Contra-ataque' }
const LINES = [['DEF', 'Defesa'], ['MID', 'Meio'], ['ATT', 'Ataque']]
const FORM = { W: 'V', D: 'E', L: 'D' }

function Ring({ value }) {
  const r = 26
  const c = 2 * Math.PI * r
  return (
    <svg className="on-prep-ring" viewBox="0 0 64 64" aria-hidden="true">
      <circle cx="32" cy="32" r={r} className="is-track" />
      <circle cx="32" cy="32" r={r} className="is-fill" strokeDasharray={c} strokeDashoffset={c * (1 - value / 100)} />
      <text x="32" y="37" textAnchor="middle">{value}</text>
    </svg>
  )
}

function Scout({ data, onClose }) {
  const o = data?.opp
  return (
    <div className="on-modal" role="dialog" aria-modal="true" aria-label="Relatório do adversário">
      <div className="on-sheet">
        <button type="button" className="on-result-x" onClick={onClose} aria-label="Fechar"><X size={16} /></button>
        <small className="on-sheet-kicker"><Binoculars size={13} /> Relatório do olheiro</small>
        {!data ? <Skeleton rows={5} /> : (
          <>
            <header className="on-scout-head">
              <OnlineCrest club={o} size={52} />
              <div>
                <strong>{o.name}</strong>
                <span>{o.position}º na liga · {o.formation || '4-3-3'} · {STYLE[o.style] || STYLE.neutral}</span>
                <span className="on-form">{o.form.length === 0 && <i className="is-none" />}{o.form.map((r, i) => <i key={i} className={`is-${r}`}>{FORM[r]}</i>)}</span>
              </div>
            </header>
            <div className="on-scout-bars">
              {LINES.map(([k, label]) => {
                const me = Number(data.sectors?.me?.[k] ?? 0)
                const op = Number(data.sectors?.opp?.[k] ?? 0)
                return (
                  <div key={k} className={me >= op ? 'is-ahead' : 'is-behind'}>
                    <b>{Math.round(me)}</b>
                    <span><small>{label}</small><i><em style={{ width: `${me + op ? (me / (me + op)) * 100 : 50}%` }} /></i></span>
                    <b>{Math.round(op)}</b>
                  </div>
                )
              })}
            </div>
            <h3 className="on-h">Destaques</h3>
            <div className="on-scout-stars">{o.stars.map((p) => <FutCard key={p.id} p={p} club={o} size="sm" />)}</div>
            <button type="button" className="gx-btn" onClick={onClose}>Entendido</button>
          </>
        )}
      </div>
    </div>
  )
}

function Talk({ current, busy, onPick, onClose }) {
  return (
    <div className="on-modal" role="dialog" aria-modal="true" aria-label="Preleção">
      <div className="on-sheet">
        <button type="button" className="on-result-x" onClick={onClose} aria-label="Fechar"><X size={16} /></button>
        <small className="on-sheet-kicker"><Megaphone size={13} /> Preleção</small>
        <div className="on-talks">
          {TALKS.map(([id, label, line]) => (
            <button key={id} type="button" className={current === id ? 'is-on' : ''} disabled={busy} onClick={() => onPick(id)}>
              <strong>{label}</strong>
              <span>“{line}”</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}

// PREPARAÇÃO PARA O JOGO: quatro tarefas antes de cada partida. O percentual vira bônus de forma no pontapé;
// preparação completa em jogos seguidos forma uma sequência que rende moedas.
export default function OnlinePrep({ prep, go, notify, onReload }) {
  const [sheet, setSheet] = useState(null)
  const [scout, setScout] = useState(null)
  const [busy, setBusy] = useState(false)
  if (!prep) return null
  const openScout = () => {
    setSheet('scout')
    fetchOnlineScout()
      .then((d) => {
        setScout(d)
        onReload?.()
      })
      .catch((e) => {
        notify?.(e.message, 'alert')
        setSheet(null)
      })
  }
  const talk = (id) => {
    setBusy(true)
    sendOnlineTeamTalk(id)
      .then(() => {
        setSheet(null)
        onReload?.()
      })
      .catch((e) => notify?.(e.message, 'alert'))
      .finally(() => setBusy(false))
  }
  const tasks = [
    { id: 'lineup', Icon: Shirt, label: 'Escalação', done: prep.lineup, value: prep.lineup ? 'Definida' : 'Revisar', run: () => go('squad') },
    { id: 'train', Icon: Dumbbell, label: 'Treino', done: prep.train >= prep.train_max, value: `${prep.train}/${prep.train_max}`, run: () => go('club', 'train') },
    { id: 'scout', Icon: Binoculars, label: 'Adversário', done: prep.scout, value: prep.scout ? 'Estudado' : 'Estudar', run: openScout },
    { id: 'talk', Icon: Megaphone, label: 'Preleção', done: Boolean(prep.talk), value: TALK_LABEL[prep.talk] || 'Escolher', run: () => setSheet('talk') },
  ]
  const toNext = prep.streak_every - (prep.streak % prep.streak_every)
  return (
    <div className={`on-prep ${prep.score >= 100 ? 'is-full' : ''}`}>
      <header>
        <Ring value={prep.score} />
        <div className="on-prep-title">
          <small>Preparação para o jogo</small>
          <strong>{prep.score >= 100 ? 'Time pronto' : `+${String(prep.bonus).replace('.', ',')}% em campo`}</strong>
          <span className="on-prep-reward"><Coins size={11} /> {prep.coins} por jogo com 100%</span>
        </div>
        <div className={`on-prep-streak ${prep.streak > 0 ? 'is-on' : ''}`} title={`Recorde: ${prep.best}`}>
          <Flame size={18} />
          <b>{prep.streak}</b>
          <small>{toNext === 1 ? `+${prep.streak_coins}` : `faltam ${toNext}`}</small>
        </div>
      </header>
      <div className="on-prep-tasks">
        {tasks.map(({ id, Icon, label, done, value, run }) => (
          <button key={id} type="button" className={done ? 'is-done' : ''} onClick={run}>
            <span className="on-prep-icon">{done ? <Check size={16} /> : <Icon size={16} />}</span>
            <span className="on-prep-task"><strong>{label}</strong><small>{value}</small></span>
            <ChevronRight size={14} />
          </button>
        ))}
      </div>
      {sheet === 'scout' && <Scout data={scout} onClose={() => setSheet(null)} />}
      {sheet === 'talk' && <Talk current={prep.talk} busy={busy} onPick={talk} onClose={() => setSheet(null)} />}
    </div>
  )
}
