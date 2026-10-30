import { useCallback, useEffect, useState } from 'react'
import { ArrowLeft, CalendarRange, Database, Gauge, History, Megaphone, RefreshCw, Search, Send, Users } from 'lucide-react'
import AdminEvents from '../events/AdminEvents'
import { ConfirmSheet, Notice, Skeleton } from '../../components/ui/feedback'
import { broadcast, fetchActions, fetchOverview, fetchPlayers, grantPlayer } from './adminApi'
import '../events/events.css'
import './admin.css'

// PAINEL ADMINISTRATIVO (desktop). Só contatodavidcaua@gmail.com: o servidor recusa qualquer outra conta.
const SECTIONS = [
  { id: 'overview', label: 'Visão geral', Icon: Gauge },
  { id: 'events', label: 'Eventos', Icon: CalendarRange },
  { id: 'players', label: 'Jogadores', Icon: Users },
  { id: 'broadcast', label: 'Avisos', Icon: Megaphone },
  { id: 'log', label: 'Registro', Icon: History },
]
const CURRENCY = { coins: 'Moedas', diamonds: 'Diamantes', bonus_energy: 'Energia bônus' }
const fmt = (n) => Number(n || 0).toLocaleString('pt-BR')
const fmtDate = (v) => (v ? new Date(v).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '—')
const mb = (bytes) => `${(Number(bytes || 0) / 1048576).toFixed(1).replace('.', ',')} MB`

function actionText(a) {
  if (a.action === 'grant') return `${a.detail.amount > 0 ? 'Enviou' : 'Retirou'} ${fmt(Math.abs(a.detail.amount))} ${CURRENCY[a.detail.currency] || a.detail.currency} · ${a.nickname || '—'} · ${a.detail.reason}`
  if (a.action === 'broadcast') return `Aviso “${a.detail.title}” para ${fmt(a.detail.recipients)} jogadores`
  return a.action
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
  return (
    <>
      <div className="ad-head">
        <h2>Visão geral</h2>
        <button type="button" className="ad-btn-ghost" onClick={load}><RefreshCw size={15} /> Atualizar</button>
      </div>
      <div className="ad-kpis">
        <div className="ad-kpi"><small>Jogadores cadastrados</small><b>{fmt(data.users.total)}</b><span>+{fmt(data.users.new_7d)} nos últimos 7 dias</span></div>
        <div className="ad-kpi"><small>Ativos nas últimas 24h</small><b>{fmt(data.users.active_24h)}</b><span>{fmt(data.users.active_7d)} na semana</span></div>
        <div className="ad-kpi"><small>Carreiras</small><b>{fmt(data.careers.total)}</b><span>{fmt(data.careers.seasons)} no modo Temporadas</span></div>
        <div className="ad-kpi"><small>Eventos</small><b>{fmt(data.events.live)} ao vivo</b><span>{fmt(data.events.scheduled)} agendados · {fmt(data.events.drafts)} rascunhos</span></div>
      </div>
      <div className="ad-grid2">
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
        <section className="ad-card">
          <h3><History size={16} /> Últimas ações</h3>
          {data.recent.length === 0 ? <p className="ad-muted">Nenhuma ação registrada ainda.</p> : (
            <ul className="ad-log">{data.recent.map((a, i) => <li key={i}><time>{fmtDate(a.at)}</time><span>{actionText(a)}</span></li>)}</ul>
          )}
          <h3 className="ad-sub">Economia</h3>
          <p className="ad-muted">{fmt(data.careers.coins)} moedas e {fmt(data.careers.diamonds)} diamantes nas carteiras dos jogadores.</p>
        </section>
      </div>
    </>
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
      onDone(`${Number(amount) > 0 ? 'Enviado' : 'Retirado'}: ${fmt(Math.abs(amount))} ${CURRENCY[currency]} para ${player.nickname}.`)
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
      <label className="grow">Motivo<input value={reason} maxLength={200} placeholder="Ex.: compensação por erro na venda" onChange={(e) => setReason(e.target.value)} /></label>
      <button type="submit" className="ad-btn" disabled={busy || !reason.trim() || !Number(amount)}><Send size={15} /> {busy ? 'Enviando…' : 'Confirmar'}</button>
      <button type="button" className="ad-btn-ghost" onClick={onCancel}>Cancelar</button>
      {error && <p className="ad-error">{error}</p>}
      <p className="ad-muted grow">Use valor negativo para retirar. Fica registrado com o motivo.</p>
    </form>
  )
}

function Players() {
  const [query, setQuery] = useState('')
  const [rows, setRows] = useState(null)
  const [error, setError] = useState('')
  const [open, setOpen] = useState(null)
  const [done, setDone] = useState('')
  const load = useCallback((q) => {
    fetchPlayers(q).then((r) => { setError(''); setRows(r) }).catch((e) => setError(e.message))
  }, [])
  useEffect(() => load(''), [load])
  return (
    <>
      <div className="ad-head">
        <h2>Jogadores</h2>
        <form className="ad-search" onSubmit={(e) => { e.preventDefault(); load(query) }}>
          <Search size={15} />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar por apelido ou e-mail" aria-label="Buscar jogador" />
          <button type="submit" className="ad-btn">Buscar</button>
        </form>
      </div>
      {done && <Notice kind="ok" onClose={() => setDone('')}>{done}</Notice>}
      {error && <Notice kind="error">{error}</Notice>}
      {!rows ? <Skeleton rows={6} /> : (
        <section className="ad-card ad-scroll">
          <table className="ad-table">
            <thead><tr><th>Apelido</th><th>E-mail</th><th className="num">Nível</th><th className="num">Moedas</th><th className="num">Diamantes</th><th className="num">Energia</th><th>Clube</th><th>Último acesso</th><th /></tr></thead>
            <tbody>
              {rows.length === 0 && <tr><td colSpan={9} className="ad-muted">Nenhum jogador encontrado.</td></tr>}
              {rows.map((p) => (
                <Row key={p.id} p={p} open={open === p.id} onOpen={() => setOpen(open === p.id ? null : p.id)}
                  onDone={(msg) => { setOpen(null); setDone(msg); load(query) }} />
              ))}
            </tbody>
          </table>
        </section>
      )}
    </>
  )
}

function Row({ p, open, onOpen, onDone }) {
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
        <td className="num"><button type="button" className="ad-btn-ghost" onClick={onOpen}>{open ? 'Fechar' : 'Enviar itens'}</button></td>
      </tr>
      {open && <tr className="ad-expand"><td colSpan={9}><GrantForm player={p} onDone={onDone} onCancel={onOpen} /></td></tr>}
    </>
  )
}

function Broadcast() {
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [confirm, setConfirm] = useState(false)
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(null)
  async function send() {
    setBusy(true)
    try {
      const r = await broadcast(title, body)
      setMsg({ kind: 'ok', text: `Aviso enviado para ${fmt(r.recipients)} jogadores.` })
      setTitle('')
      setBody('')
    } catch (e) {
      setMsg({ kind: 'error', text: e.message })
    } finally {
      setBusy(false)
      setConfirm(false)
    }
  }
  return (
    <>
      <div className="ad-head"><h2>Avisos</h2></div>
      {msg && <Notice kind={msg.kind} onClose={() => setMsg(null)}>{msg.text}</Notice>}
      <section className="ad-card ad-narrow">
        <p className="ad-muted">O aviso chega na caixa de mensagens de todos os jogadores (assunto Clube).</p>
        <label className="ad-field">Título<input value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} placeholder="Ex.: Manutenção programada" /></label>
        <label className="ad-field">Mensagem<textarea value={body} maxLength={2000} rows={6} onChange={(e) => setBody(e.target.value)} placeholder="Texto que os jogadores vão ler" /></label>
        <div className="ad-actions">
          <small className="ad-muted">{body.length}/2000</small>
          <button type="button" className="ad-btn" disabled={title.trim().length < 3 || body.trim().length < 3} onClick={() => setConfirm(true)}><Megaphone size={15} /> Enviar para todos</button>
        </div>
      </section>
      {confirm && (
        <ConfirmSheet title="Enviar aviso para todos?" text={`“${title}” vai para a caixa de mensagens de todos os jogadores. Não dá para desfazer.`}
          confirmLabel="Enviar" busy={busy} onConfirm={send} onCancel={() => setConfirm(false)} />
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
  return (
    <div className="ad">
      <aside className="ad-side">
        <div className="ad-brand"><b>Painel</b><small>Administração</small></div>
        <nav aria-label="Seções do painel">
          {SECTIONS.map(({ id, label, Icon }) => (
            <button key={id} type="button" className={section === id ? 'is-on' : ''} aria-current={section === id ? 'page' : undefined} onClick={() => setSection(id)}>
              <Icon size={17} /> {label}
            </button>
          ))}
        </nav>
        <button type="button" className="ad-back" onClick={onBack}><ArrowLeft size={16} /> Voltar ao jogo</button>
      </aside>
      <main className="ad-main">
        {section === 'overview' && <Overview />}
        {section === 'events' && (
          <>
            <div className="ad-head"><h2>Eventos</h2></div>
            <section className="ad-card ad-events"><AdminEvents onChanged={() => {}} /></section>
          </>
        )}
        {section === 'players' && <Players />}
        {section === 'broadcast' && <Broadcast />}
        {section === 'log' && <Log />}
      </main>
    </div>
  )
}
