import { useCallback, useEffect, useState } from 'react'
import { ArrowLeft, CalendarRange, Database, Gauge, Gift, History, Megaphone, RefreshCw, Search, Send, Shield, Trophy, Users, XCircle } from 'lucide-react'
import AdminEvents from '../events/AdminEvents'
import { ConfirmSheet, Notice, Skeleton } from '../../components/ui/feedback'
import { adjustCareer, cancelAnnouncement, fetchActions, fetchAnnouncements, fetchCareer, fetchOverview, fetchPlayers, grantPlayer, saveAnnouncement, setCareerClub } from './adminApi'
import '../events/events.css'
import './admin.css'

// PAINEL ADMINISTRATIVO (desktop). Só contatodavidcaua@gmail.com: o servidor recusa qualquer outra conta.
// Toda ação sobre um jogador vira um comunicado em modal para ele (caixa de entrada).
const SECTIONS = [
  { id: 'overview', label: 'Visão geral', Icon: Gauge },
  { id: 'seasons', label: 'Temporadas', Icon: Trophy },
  { id: 'players', label: 'Jogadores', Icon: Users },
  { id: 'announcements', label: 'Avisos', Icon: Megaphone },
  { id: 'events', label: 'Eventos', Icon: CalendarRange },
  { id: 'log', label: 'Registro', Icon: History },
]
const CURRENCY = { coins: 'Moedas', diamonds: 'Diamantes', bonus_energy: 'Energia bônus' }
const REASON = { match_reward: 'Partidas', event_reward: 'Eventos', inbox_reward: 'Premiações', admin_grant: 'Administração', coach_salary: 'Salário de técnico', shop: 'Loja', store: 'Loja', base_cards_compensation: 'Conversão de cartas', opening_balance: 'Saldo inicial', competition_prize: 'Prêmios de competição', release_gift: 'Presente da atualização', streak_reward: 'Sequência diária', coach_signing: 'Luvas de técnico' }
const STATE = { live: 'No ar', scheduled: 'Agendado', ended: 'Encerrado', cancelled: 'Cancelado' }
const fmt = (n) => Number(n || 0).toLocaleString('pt-BR')
const fmtDate = (v) => (v ? new Date(v).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '—')
const mb = (bytes) => `${(Number(bytes || 0) / 1048576).toFixed(1).replace('.', ',')} MB`
// datas do formulário em horário de Brasília (UTC−3)
const toLocal = (iso) => (iso ? new Date(new Date(iso).getTime() - 3 * 3600000).toISOString().slice(0, 16) : '')
const fromLocal = (v) => (v ? `${v}:00-03:00` : null)
const rewardText = (r) => Object.entries(r || {}).filter(([, v]) => v > 0).map(([k, v]) => `${fmt(v)} ${CURRENCY[k].toLowerCase()}`).join(' · ')

function actionText(a) {
  const d = a.detail || {}
  if (a.action === 'grant') return `${d.amount > 0 ? 'Premiação' : 'Retirou'} ${fmt(Math.abs(d.amount))} ${CURRENCY[d.currency] || d.currency} · ${a.nickname || '—'} · ${d.reason}`
  if (a.action === 'broadcast') return `Aviso “${d.title}” para ${fmt(d.recipients)} jogadores`
  if (a.action === 'announcement') return `Aviso “${d.title}” · ${fmtDate(d.starts_at)} → ${fmtDate(d.ends_at)}`
  if (a.action === 'set_club') return `${a.nickname || '—'} levado de ${d.from || 'sem clube'} para ${d.to} · ${d.reason}`
  if (a.action === 'adjust') return `${a.nickname || '—'} · ${d.field === 'cash' ? 'caixa do clube' : 'reputação'} ${d.amount > 0 ? '+' : ''}${fmt(d.amount)} · ${d.reason}`
  return a.action
}

function Kpi({ label, value, sub }) {
  return <div className="ad-kpi"><small>{label}</small><b>{value}</b>{sub && <span>{sub}</span>}</div>
}

function Overview() {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const load = useCallback(() => {
    fetchOverview().then((d) => { setError(''); setData(d) }).catch((e) => setError(e.message))
  }, [])
  useEffect(load, [load])
  if (error) return <Notice kind="error">{error}</Notice>
  if (!data) return <Skeleton rows={4} />
  const used = data.database.size / data.database.limit
  const signups = data.users.signups || []
  const peak = Math.max(1, ...signups.map((s) => s.n))
  return (
    <>
      <div className="ad-head">
        <h2>Visão geral</h2>
        <button type="button" className="ad-btn-ghost" onClick={load}><RefreshCw size={15} /> Atualizar</button>
      </div>
      <div className="ad-kpis">
        <Kpi label="Jogadores cadastrados" value={fmt(data.users.total)} sub={`+${fmt(data.users.new_7d)} nos últimos 7 dias`} />
        <Kpi label="Ativos nas últimas 24h" value={fmt(data.users.active_24h)} sub={`${fmt(data.users.active_7d)} na semana`} />
        <Kpi label="Partidas jogadas" value={fmt(data.matches.today)} sub={`hoje · ${fmt(data.matches.week)} na semana`} />
        <Kpi label="No modo Temporadas" value={fmt(data.careers.seasons)} sub={`${fmt(data.careers.employed)} com clube · ${fmt(data.careers.unemployed)} sem clube`} />
      </div>
      <div className="ad-kpis">
        <Kpi label="Moedas que entraram (7 dias)" value={fmt(data.economy.in_7d)} sub={`${fmt(data.economy.out_7d)} gastas · ${fmt(data.economy.shop_7d)} compras na loja`} />
        <Kpi label="Eventos" value={`${fmt(data.events.live)} no ar`} sub={`${fmt(data.events.completions_7d)} concluídos · ${fmt(data.events.claims_7d)} resgatados (7 dias)`} />
        <Kpi label="Avisos" value={`${fmt(data.announcements.live)} no ar`} sub={`${fmt(data.announcements.scheduled)} agendados · ${fmt(data.announcements.unclaimed_rewards)} premiações sem resgate`} />
        <Kpi label="Nível médio" value={String(data.careers.avg_level ?? 0).replace('.', ',')} sub={`${fmt(data.careers.coins)} moedas nas carteiras`} />
      </div>
      <div className="ad-grid2">
        <section className="ad-card">
          <h3><Users size={16} /> Cadastros por dia (14 dias)</h3>
          <div className="ad-bars" role="img" aria-label={`Cadastros por dia: ${signups.map((s) => `${s.day}: ${s.n}`).join(', ')}`}>
            {signups.map((s) => (
              <span key={s.day} title={`${new Date(`${s.day}T12:00:00`).toLocaleDateString('pt-BR')}: ${s.n}`}>
                <i style={{ height: `${(s.n / peak) * 100}%` }} />
                <small>{s.day.slice(8, 10)}</small>
              </span>
            ))}
          </div>
          <h3 className="ad-sub"><Trophy size={16} /> Melhores jogadores</h3>
          <table className="ad-table">
            <thead><tr><th>Jogador</th><th className="num">Nível</th><th>Clube</th><th className="num">Títulos</th><th className="num">Reputação</th></tr></thead>
            <tbody>{data.careers.top_players.map((p) => <tr key={p.nickname}><td>{p.nickname}</td><td className="num">{p.level}</td><td>{p.club_id || '—'}</td><td className="num">{p.titles ?? 0}</td><td className="num">{p.reputation ?? '—'}</td></tr>)}</tbody>
          </table>
        </section>
        <section className="ad-card">
          <h3><Gift size={16} /> Economia da semana (moedas)</h3>
          <table className="ad-table">
            <tbody>{data.economy.reasons.length === 0 ? <tr><td className="ad-muted">Sem movimentação.</td></tr> : data.economy.reasons.map((r) => (
              <tr key={r.reason}><td>{REASON[r.reason] || r.reason}</td><td className="num">{fmt(r.n)}×</td><td className={`num ${r.total < 0 ? 'ad-neg' : 'ad-pos'}`}>{r.total > 0 ? '+' : ''}{fmt(r.total)}</td></tr>
            ))}</tbody>
          </table>
          <h3 className="ad-sub"><Shield size={16} /> Clubes mais escolhidos</h3>
          <p className="ad-muted">{data.careers.top_clubs.length ? data.careers.top_clubs.map((c) => `${c.club_id} (${c.n})`).join(' · ') : 'Ninguém com clube ainda.'}</p>
          <h3 className="ad-sub"><History size={16} /> Últimas ações</h3>
          {data.recent.length === 0 ? <p className="ad-muted">Nenhuma ação registrada ainda.</p> : (
            <ul className="ad-log">{data.recent.map((a, i) => <li key={i}><time>{fmtDate(a.at)}</time><span>{actionText(a)}</span></li>)}</ul>
          )}
        </section>
      </div>
      <section className="ad-card">
        <h3><Database size={16} /> Banco de dados</h3>
        <div className="ad-meter" role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(used * 100)} aria-label="Uso do banco">
          <i style={{ width: `${Math.min(100, used * 100)}%` }} className={used > 0.8 ? 'is-high' : ''} />
        </div>
        <p className="ad-muted">{mb(data.database.size)} de {mb(data.database.limit)} ({Math.round(used * 100)}%)</p>
        <table className="ad-table">
          <thead><tr><th>Tabela</th><th className="num">Tamanho</th><th className="num">Linhas</th></tr></thead>
          <tbody>{data.database.tables.map((t) => <tr key={t.name}><td>{t.name}</td><td className="num">{mb(t.bytes)}</td><td className="num">{fmt(t.rows)}</td></tr>)}</tbody>
        </table>
      </section>
    </>
  )
}

function useDone() {
  const [done, setDone] = useState(null)
  return [done, setDone]
}

function PlayerSearch({ onSearch, placeholder = 'Buscar por apelido ou e-mail' }) {
  const [query, setQuery] = useState('')
  return (
    <form className="ad-search" onSubmit={(e) => { e.preventDefault(); onSearch(query) }}>
      <Search size={15} />
      <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={placeholder} aria-label="Buscar jogador" />
      <button type="submit" className="ad-btn">Buscar</button>
    </form>
  )
}

function GrantForm({ player, onDone, onCancel }) {
  const [currency, setCurrency] = useState('coins')
  const [amount, setAmount] = useState(100)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function submit(e) {
    e.preventDefault()
    setBusy(true)
    setError('')
    try {
      await grantPlayer(player.id, currency, Number(amount), reason)
      onDone(Number(amount) > 0
        ? `Premiação de ${fmt(amount)} ${CURRENCY[currency].toLowerCase()} enviada para a caixa de entrada de ${player.nickname}.`
        : `Retirado: ${fmt(Math.abs(amount))} ${CURRENCY[currency].toLowerCase()} de ${player.nickname}.`)
    } catch (err) {
      setError(err.message)
    } finally {
      setBusy(false)
    }
  }
  return (
    <form className="ad-grant" onSubmit={submit}>
      <label>Item<select value={currency} onChange={(e) => setCurrency(e.target.value)}>{Object.entries(CURRENCY).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
      <label>Quantidade<input type="number" value={amount} min={-1000000} max={1000000} onChange={(e) => setAmount(e.target.value)} /></label>
      <label className="grow">Motivo (o jogador vê)<input value={reason} maxLength={200} placeholder="Ex.: compensação por erro na venda" onChange={(e) => setReason(e.target.value)} /></label>
      <button type="submit" className="ad-btn" disabled={busy || !reason.trim() || !Number(amount)}><Send size={15} /> {busy ? 'Enviando…' : 'Confirmar'}</button>
      <button type="button" className="ad-btn-ghost" onClick={onCancel}>Cancelar</button>
      {error && <p className="ad-error">{error}</p>}
      <p className="ad-muted grow">Positivo: vai para a caixa de entrada e o jogador resgata. Negativo: retira na hora. Nos dois casos ele recebe um aviso em modal.</p>
    </form>
  )
}

function Players({ onOpenCareer }) {
  const [rows, setRows] = useState(null)
  const [query, setQuery] = useState('')
  const [error, setError] = useState('')
  const [open, setOpen] = useState(null)
  const [done, setDone] = useDone()
  const load = useCallback((q) => {
    setQuery(q)
    fetchPlayers(q).then((r) => { setError(''); setRows(r) }).catch((e) => setError(e.message))
  }, [])
  useEffect(() => { fetchPlayers('').then(setRows).catch((e) => setError(e.message)) }, [])
  return (
    <>
      <div className="ad-head"><h2>Jogadores</h2><PlayerSearch onSearch={load} /></div>
      {done && <Notice kind="ok" onClose={() => setDone(null)}>{done}</Notice>}
      {error && <Notice kind="error">{error}</Notice>}
      {!rows ? <Skeleton rows={6} /> : (
        <section className="ad-card ad-scroll">
          <table className="ad-table">
            <thead><tr><th>Apelido</th><th>E-mail</th><th className="num">Nível</th><th className="num">Moedas</th><th className="num">Diamantes</th><th className="num">Energia</th><th>Clube</th><th>Último acesso</th><th /></tr></thead>
            <tbody>
              {rows.length === 0 && <tr><td colSpan={9} className="ad-muted">Nenhum jogador encontrado.</td></tr>}
              {rows.map((p) => (
                <PlayerRow key={p.id} p={p} open={open === p.id} onOpen={() => setOpen(open === p.id ? null : p.id)} onCareer={() => onOpenCareer(p.id)}
                  onDone={(msg) => { setOpen(null); setDone(msg); load(query) }} />
              ))}
            </tbody>
          </table>
        </section>
      )}
    </>
  )
}

function PlayerRow({ p, open, onOpen, onCareer, onDone }) {
  return (
    <>
      <tr className={open ? 'is-open' : ''}>
        <td><b>{p.nickname}</b>{p.in_seasons && <span className="ad-tag">Temporadas</span>}</td>
        <td className="ad-muted">{p.email}</td>
        <td className="num">{p.level}</td>
        <td className="num">{fmt(p.coins)}</td>
        <td className="num">{fmt(p.diamonds)}</td>
        <td className="num">{fmt(p.energy)} + {fmt(p.bonus_energy)}</td>
        <td>{p.club_id || '—'}</td>
        <td className="ad-muted">{fmtDate(p.last_sign_in_at)}</td>
        <td className="num ad-row-actions">
          {p.in_seasons && <button type="button" className="ad-btn-ghost" onClick={onCareer}>Carreira</button>}
          <button type="button" className="ad-btn-ghost" onClick={onOpen}>{open ? 'Fechar' : 'Premiar'}</button>
        </td>
      </tr>
      {open && <tr className="ad-expand"><td colSpan={9}><GrantForm player={p} onDone={onDone} onCancel={onOpen} /></td></tr>}
    </>
  )
}

function ActionForm({ title, children, onSubmit, busy, disabled, label = 'Aplicar' }) {
  return (
    <form className="ad-action" onSubmit={(e) => { e.preventDefault(); onSubmit() }}>
      <b>{title}</b>
      <div className="ad-grant">{children}<button type="submit" className="ad-btn" disabled={busy || disabled}>{busy ? 'Aplicando…' : label}</button></div>
    </form>
  )
}

function CareerPanel({ careerId, onBack }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [done, setDone] = useDone()
  const [busy, setBusy] = useState(null)
  const [club, setClub] = useState('')
  const [cash, setCash] = useState(100000)
  const [rep, setRep] = useState(5)
  const [reasons, setReasons] = useState({ club: '', cash: '', rep: '' })
  useEffect(() => { fetchCareer(careerId).then(setData).catch((e) => setError(e.message)) }, [careerId])

  async function run(key, fn, message) {
    setBusy(key)
    setError('')
    try {
      setData(await fn())
      setDone(message)
      setReasons((r) => ({ ...r, [key]: '' }))
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(null)
    }
  }
  if (!data) return error ? <Notice kind="error">{error}</Notice> : <Skeleton rows={5} />
  const c = data.coach
  const reasonInput = (key) => (
    <label className="grow">Motivo (o jogador vê)<input value={reasons[key]} maxLength={200} onChange={(e) => setReasons((r) => ({ ...r, [key]: e.target.value }))} /></label>
  )
  return (
    <>
      <div className="ad-head">
        <h2>{data.career.nickname}</h2>
        <button type="button" className="ad-btn-ghost" onClick={onBack}><ArrowLeft size={15} /> Voltar à lista</button>
      </div>
      {done && <Notice kind="ok" onClose={() => setDone(null)}>{done}</Notice>}
      {error && <Notice kind="error" onClose={() => setError('')}>{error}</Notice>}
      <div className="ad-kpis">
        <Kpi label="Clube" value={c?.status === 'employed' ? c.club_id : 'Sem clube'} sub={data.club ? `Caixa ${fmt(data.club.cash)} · folha ${fmt(data.club.payroll)}/mês` : '—'} />
        <Kpi label="Reputação" value={c?.reputation ?? '—'} sub={`Diretoria ${c?.board ?? '—'} · torcida ${c?.fans ?? '—'}`} />
        <Kpi label="Campanha" value={`${c?.wins ?? 0}V ${c?.draws ?? 0}E ${c?.losses ?? 0}D`} sub={`${c?.titles ?? 0} títulos · ${c?.fired ?? 0} demissões`} />
        <Kpi label="Data no mundo" value={data.world ? new Date(`${data.world.today}T12:00:00`).toLocaleDateString('pt-BR') : '—'} sub={`Nível ${data.career.level} · ${data.email || ''}`} />
      </div>
      {data.live_match && <Notice kind="info">O jogador está com uma partida em andamento: a troca de clube fica bloqueada até ela terminar.</Notice>}
      <section className="ad-card ad-actions-card">
        <h3><Trophy size={16} /> Ações no modo Temporadas</h3>
        <p className="ad-muted">Cada ação aparece para o jogador em um aviso em modal na próxima vez que ele abrir o jogo.</p>
        <ActionForm title="Levar para outro clube" busy={busy === 'club'} disabled={!club || reasons.club.trim().length < 3} label="Transferir técnico"
          onSubmit={() => run('club', () => setCareerClub(careerId, club, reasons.club), `${data.career.nickname} agora treina ${club}.`)}>
          <label>Clube<select value={club} onChange={(e) => setClub(e.target.value)}>
            <option value="">Escolha…</option>
            {['BRA', 'ENG'].map((region) => (
              <optgroup key={region} label={region === 'BRA' ? 'Brasil' : 'Inglaterra'}>
                {data.clubs.filter((x) => x.region === region).map((x) => <option key={x.id} value={x.id}>{x.name} ({x.tier.replace('_', ' ')})</option>)}
              </optgroup>
            ))}
          </select></label>
          {reasonInput('club')}
        </ActionForm>
        <ActionForm title="Caixa do clube" busy={busy === 'cash'} disabled={!data.club || !Number(cash) || reasons.cash.trim().length < 3}
          onSubmit={() => run('cash', () => adjustCareer(careerId, 'cash', Number(cash), reasons.cash), `Caixa ajustado em ${fmt(cash)}.`)}>
          <label>Valor (negativo retira)<input type="number" value={cash} onChange={(e) => setCash(e.target.value)} /></label>
          {reasonInput('cash')}
        </ActionForm>
        <ActionForm title="Reputação do técnico (0–100)" busy={busy === 'rep'} disabled={!Number(rep) || reasons.rep.trim().length < 3}
          onSubmit={() => run('rep', () => adjustCareer(careerId, 'reputation', Number(rep), reasons.rep), `Reputação ajustada em ${rep}.`)}>
          <label>Pontos (negativo reduz)<input type="number" value={rep} min={-100} max={100} onChange={(e) => setRep(e.target.value)} /></label>
          {reasonInput('rep')}
        </ActionForm>
      </section>
      <section className="ad-card">
        <h3><History size={16} /> Últimos avisos recebidos pelo jogador</h3>
        {data.notices.length === 0 ? <p className="ad-muted">Nenhum ainda.</p> : (
          <ul className="ad-log">{data.notices.map((n, i) => (
            <li key={i}><time>{fmtDate(n.created_at)}</time><span>{n.title}{rewardText(n.reward) ? ` · ${rewardText(n.reward)}` : ''} · {n.claimed_at ? 'resgatado' : n.seen_at ? 'visto' : 'ainda não visto'}</span></li>
          ))}</ul>
        )}
      </section>
    </>
  )
}

function Seasons({ careerId, onCareer }) {
  const [rows, setRows] = useState(null)
  const [error, setError] = useState('')
  const load = useCallback((q) => {
    fetchPlayers(q).then((r) => { setError(''); setRows(r.filter((p) => p.in_seasons)) }).catch((e) => setError(e.message))
  }, [])
  useEffect(() => { fetchPlayers('').then((r) => setRows(r.filter((p) => p.in_seasons))).catch((e) => setError(e.message)) }, [])
  if (careerId) return <CareerPanel key={careerId} careerId={careerId} onBack={() => onCareer(null)} />
  return (
    <>
      <div className="ad-head"><h2>Temporadas</h2><PlayerSearch onSearch={load} /></div>
      {error && <Notice kind="error">{error}</Notice>}
      {!rows ? <Skeleton rows={5} /> : (
        <section className="ad-card ad-scroll">
          <table className="ad-table">
            <thead><tr><th>Jogador</th><th>Clube</th><th className="num">Nível</th><th>Último acesso</th><th /></tr></thead>
            <tbody>
              {rows.length === 0 && <tr><td colSpan={5} className="ad-muted">Ninguém no modo Temporadas com essa busca.</td></tr>}
              {rows.map((p) => (
                <tr key={p.id}><td><b>{p.nickname}</b></td><td>{p.coach_status === 'employed' ? p.club_id : 'Sem clube'}</td><td className="num">{p.level}</td>
                  <td className="ad-muted">{fmtDate(p.last_sign_in_at)}</td><td className="num"><button type="button" className="ad-btn-ghost" onClick={() => onCareer(p.id)}>Gerenciar</button></td></tr>
              ))}
            </tbody>
          </table>
        </section>
      )}
    </>
  )
}

const blankAnnouncement = () => {
  const now = new Date()
  return { title: '', body: '', starts_at: toLocal(now.toISOString()), ends_at: toLocal(new Date(now.getTime() + 7 * 864e5).toISOString()), reward: { coins: '', diamonds: '', bonus_energy: '' } }
}

function Announcements() {
  const [list, setList] = useState(null)
  const [form, setForm] = useState(blankAnnouncement)
  const [msg, setMsg] = useState(null)
  const [busy, setBusy] = useState(false)
  const [confirm, setConfirm] = useState(false)
  const [cancelling, setCancelling] = useState(null)
  const load = useCallback(() => fetchAnnouncements().then(setList).catch((e) => setMsg({ kind: 'error', text: e.message })), [])
  useEffect(() => { load() }, [load])
  const set = (k, v) => setForm((f) => ({ ...f, [k]: v }))
  const setReward = (k, v) => setForm((f) => ({ ...f, reward: { ...f.reward, [k]: v } }))
  const valid = form.title.trim().length >= 3 && form.body.trim().length >= 3 && form.starts_at && form.ends_at && form.ends_at > form.starts_at

  async function save() {
    setBusy(true)
    try {
      const reward = Object.fromEntries(Object.entries(form.reward).filter(([, v]) => Number(v) > 0).map(([k, v]) => [k, Number(v)]))
      await saveAnnouncement({ id: form.id, title: form.title, body: form.body, starts_at: fromLocal(form.starts_at), ends_at: fromLocal(form.ends_at), reward })
      setMsg({ kind: 'ok', text: form.id ? 'Aviso atualizado.' : 'Aviso criado. Ele aparece em modal na tela inicial dentro do período.' })
      setForm(blankAnnouncement())
      load()
    } catch (e) {
      setMsg({ kind: 'error', text: e.message })
    } finally {
      setBusy(false)
      setConfirm(false)
    }
  }
  async function doCancel() {
    try {
      await cancelAnnouncement(cancelling.id)
      setMsg({ kind: 'ok', text: 'Aviso cancelado.' })
      load()
    } catch (e) {
      setMsg({ kind: 'error', text: e.message })
    } finally {
      setCancelling(null)
    }
  }
  const edit = (a) => setForm({ id: a.id, title: a.title, body: a.body, starts_at: toLocal(a.starts_at), ends_at: toLocal(a.ends_at), reward: { coins: a.reward.coins || '', diamonds: a.reward.diamonds || '', bonus_energy: a.reward.bonus_energy || '' } })

  return (
    <>
      <div className="ad-head"><h2>Avisos</h2></div>
      {msg && <Notice kind={msg.kind} onClose={() => setMsg(null)}>{msg.text}</Notice>}
      <div className="ad-grid2">
        <section className="ad-card">
          <h3><Megaphone size={16} /> {form.id ? 'Editar aviso' : 'Novo aviso'}</h3>
          <p className="ad-muted">Aparece em modal na tela inicial, uma vez para cada jogador, e fica na caixa de entrada enquanto estiver no período (horário de Brasília).</p>
          <label className="ad-field">Título<input value={form.title} maxLength={120} onChange={(e) => set('title', e.target.value)} placeholder="Ex.: Manutenção programada" /></label>
          <label className="ad-field">Mensagem<textarea value={form.body} maxLength={2000} rows={5} onChange={(e) => set('body', e.target.value)} placeholder="Texto que os jogadores vão ler" /></label>
          <div className="ad-grant">
            <label>Início<input type="datetime-local" value={form.starts_at} onChange={(e) => set('starts_at', e.target.value)} /></label>
            <label>Fim<input type="datetime-local" value={form.ends_at} onChange={(e) => set('ends_at', e.target.value)} /></label>
          </div>
          <p className="ad-muted"><b>Premiação (opcional)</b> — cada jogador resgata uma vez.</p>
          <div className="ad-grant">
            {Object.entries(CURRENCY).map(([k, label]) => <label key={k}>{label}<input type="number" min={0} max={1000000} value={form.reward[k]} onChange={(e) => setReward(k, e.target.value)} /></label>)}
          </div>
          <div className="ad-actions">
            {form.id ? <button type="button" className="ad-btn-ghost" onClick={() => setForm(blankAnnouncement())}>Cancelar edição</button> : <span />}
            <button type="button" className="ad-btn" disabled={!valid} onClick={() => setConfirm(true)}><Megaphone size={15} /> {form.id ? 'Salvar' : 'Publicar aviso'}</button>
          </div>
        </section>
        <section className="ad-card">
          <h3><History size={16} /> Avisos</h3>
          {!list ? <Skeleton rows={4} /> : list.length === 0 ? <p className="ad-muted">Nenhum aviso ainda.</p> : (
            <ul className="ad-alist">
              {list.map((a) => (
                <li key={a.id} className={`s-${a.state}`}>
                  <div>
                    <span className="ad-state">{STATE[a.state]}</span>
                    <b>{a.title}</b>
                    <small>{fmtDate(a.starts_at)} → {fmtDate(a.ends_at)}{rewardText(a.reward) ? ` · ${rewardText(a.reward)}` : ''}</small>
                    <small>{fmt(a.seen)} viram{Object.keys(a.reward).length ? ` · ${fmt(a.claimed)} resgataram` : ''}</small>
                  </div>
                  {['live', 'scheduled'].includes(a.state) && (
                    <span className="ad-row-actions">
                      <button type="button" className="ad-btn-ghost" onClick={() => edit(a)}>Editar</button>
                      <button type="button" className="ad-btn-ghost" aria-label={`Cancelar ${a.title}`} onClick={() => setCancelling(a)}><XCircle size={15} /></button>
                    </span>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
      {confirm && (
        <ConfirmSheet title={form.id ? 'Salvar alterações?' : 'Publicar aviso?'} text={`“${form.title}” aparece para todos os jogadores entre ${form.starts_at.replace('T', ' ')} e ${form.ends_at.replace('T', ' ')}.`}
          confirmLabel={form.id ? 'Salvar' : 'Publicar'} busy={busy} onConfirm={save} onCancel={() => setConfirm(false)} />
      )}
      {cancelling && (
        <ConfirmSheet title="Cancelar aviso?" text={`“${cancelling.title}” some da tela inicial e da caixa de entrada.`} confirmLabel="Cancelar aviso" danger onConfirm={doCancel} onCancel={() => setCancelling(null)} />
      )}
    </>
  )
}

function Log() {
  const [rows, setRows] = useState(null)
  const [error, setError] = useState('')
  useEffect(() => { fetchActions().then(setRows).catch((e) => setError(e.message)) }, [])
  return (
    <>
      <div className="ad-head"><h2>Registro</h2></div>
      {error && <Notice kind="error">{error}</Notice>}
      {!rows ? <Skeleton rows={6} /> : (
        <section className="ad-card">
          {rows.length === 0 ? <p className="ad-muted">Nenhuma ação registrada ainda.</p> : (
            <ul className="ad-log">{rows.map((a) => <li key={a.id}><time>{fmtDate(a.at)}</time><span>{actionText(a)}</span></li>)}</ul>
          )}
        </section>
      )}
    </>
  )
}

export default function AdminDashboard({ onBack }) {
  const [section, setSection] = useState('overview')
  const [careerId, setCareerId] = useState(null)
  const go = (id) => {
    setSection(id)
    if (id !== 'seasons') setCareerId(null)
  }
  return (
    <div className="ad">
      <aside className="ad-side">
        <div className="ad-brand"><b>Painel</b><small>Administração</small></div>
        <nav aria-label="Seções do painel">
          {SECTIONS.map(({ id, label, Icon }) => (
            <button key={id} type="button" className={section === id ? 'is-on' : ''} aria-current={section === id ? 'page' : undefined} onClick={() => go(id)}>
              <Icon size={17} /> {label}
            </button>
          ))}
        </nav>
        <button type="button" className="ad-back" onClick={onBack}><ArrowLeft size={16} /> Voltar ao jogo</button>
      </aside>
      <main className="ad-main">
        {section === 'overview' && <Overview />}
        {section === 'seasons' && <Seasons careerId={careerId} onCareer={setCareerId} />}
        {section === 'players' && <Players onOpenCareer={(id) => { setCareerId(id); setSection('seasons') }} />}
        {section === 'announcements' && <Announcements />}
        {section === 'events' && (
          <>
            <div className="ad-head"><h2>Eventos</h2></div>
            <section className="ad-card ad-events"><AdminEvents onChanged={() => {}} /></section>
          </>
        )}
        {section === 'log' && <Log />}
      </main>
    </div>
  )
}
