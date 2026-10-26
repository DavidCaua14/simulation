import { useCallback, useEffect, useState } from 'react'
import { CircleAlert, Pencil, Plus, Send, Trash2, X, XCircle } from 'lucide-react'
import { adminList, adminSave, adminSetStatus } from './eventsApi'
import { BANNER_ICONS, CATEGORY_LABEL, fmtDate, rewardText } from './eventsUi'

// Painel de eventos (só administradores — o servidor confere de novo em cada chamada).
// Objetivos e recompensas vêm de listas fechadas: não existe campo de código livre.
const STATUS_LABEL = { draft: 'Rascunho', published: 'Publicado', cancelled: 'Cancelado' }
const BANNERS = [
  'linear-gradient(135deg,#0b4a2a,#1f9d55)', 'linear-gradient(135deg,#6b4a06,#e0a82e)', 'linear-gradient(135deg,#4d0a12,#d6283a)',
  'linear-gradient(135deg,#0a1633,#2447a8)', 'linear-gradient(135deg,#2a1055,#7a3df0)', 'linear-gradient(135deg,#1b1f27,#d97706)',
]
const REWARD_KINDS = [['coins', 'Moedas'], ['diamonds', 'Diamantes'], ['energy', 'Energia bônus'], ['box', 'Caixa'], ['cosmetic', 'Item visual'], ['badge', 'Insígnia']]
const PARAM_LABEL = { competition: 'Competição', region: 'País', min_opponent_strength: 'Força mín. do adversário', tier: 'Raridade' }

// datas do formulário em horário de Brasília (UTC−3, sem horário de verão desde 2019)
const toLocal = (iso) => (iso ? new Date(new Date(iso).getTime() - 3 * 3600000).toISOString().slice(0, 16) : '')
const fromLocal = (v) => (v ? `${v}:00-03:00` : null)

const blank = () => ({
  slug: '', name: '', description: '', category: 'themed', recurrence: 'none', starts_at: '', ends_at: '',
  min_level: 1, max_completions: '', claim_grace_hours: 48, banner: { css: BANNERS[3], icon: 'trophy' },
  objectives: [{ kind: 'match_won', target: 1, params: {}, label: '' }], rewards: [{ kind: 'coins', amount: 100, ref: '' }],
})

function EventForm({ initial, meta, onCancel, onSaved }) {
  const [f, setF] = useState(initial)
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  const set = (k, v) => setF((s) => ({ ...s, [k]: v }))
  const setObj = (i, patch) => setF((s) => ({ ...s, objectives: s.objectives.map((o, j) => (j === i ? { ...o, ...patch } : o)) }))
  const setRew = (i, patch) => setF((s) => ({ ...s, rewards: s.rewards.map((r, j) => (j === i ? { ...r, ...patch } : r)) }))
  const kinds = meta.kinds || []
  const opt = meta.options || {}

  async function save(e) {
    e.preventDefault()
    setErr('')
    setBusy(true)
    try {
      const objectives = f.objectives.map((o) => {
        const params = Object.fromEntries(Object.entries(o.params || {}).filter(([, v]) => v !== '' && v != null))
        if (params.min_opponent_strength) params.min_opponent_strength = Number(params.min_opponent_strength)
        return { kind: o.kind, target: Number(o.target), params, label: o.label }
      })
      const rewards = f.rewards.map((r) => ({ kind: r.kind, amount: Number(r.amount) || 1, ref: r.ref || null }))
      await adminSave({
        ...f, starts_at: fromLocal(f.starts_at), ends_at: fromLocal(f.ends_at), min_level: Number(f.min_level) || 1,
        max_completions: f.max_completions === '' ? null : Number(f.max_completions), claim_grace_hours: Number(f.claim_grace_hours),
        objectives, rewards,
      })
      onSaved()
    } catch (e2) {
      setErr(e2.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="ev-form" onSubmit={save}>
      <header className="ev-form-head">
        <strong>{f.id ? 'Editar evento' : 'Novo evento'}</strong>
        <button type="button" className="ev-x" onClick={onCancel} aria-label="Fechar"><X size={16} /></button>
      </header>
      <label>Nome<input value={f.name} onChange={(e) => set('name', e.target.value)} maxLength={80} required /></label>
      <label>Identificador (letras minúsculas, números e hífen)<input value={f.slug} onChange={(e) => set('slug', e.target.value.toLowerCase())} pattern="[a-z0-9-]{3,60}" required /></label>
      <label>Descrição<textarea value={f.description} onChange={(e) => set('description', e.target.value)} maxLength={600} rows={2} /></label>
      <div className="ev-form-row">
        <label>Categoria
          <select value={f.category} onChange={(e) => set('category', e.target.value)}>
            {Object.entries(CATEGORY_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </label>
        <label>Repete
          <select value={f.recurrence} onChange={(e) => set('recurrence', e.target.value)}>
            <option value="none">Não (período único)</option><option value="daily">Todo dia</option><option value="weekly">Toda semana</option>
          </select>
        </label>
      </div>
      <div className="ev-form-row">
        <label>Início (Brasília)<input type="datetime-local" value={f.starts_at} onChange={(e) => set('starts_at', e.target.value)} required /></label>
        <label>Fim (Brasília)<input type="datetime-local" value={f.ends_at} onChange={(e) => set('ends_at', e.target.value)} required /></label>
      </div>
      <div className="ev-form-row three">
        <label>Nível mín.<input type="number" min={1} value={f.min_level} onChange={(e) => set('min_level', e.target.value)} /></label>
        <label>Máx. conclusões<input type="number" min={1} placeholder="sem limite" value={f.max_completions ?? ''} onChange={(e) => set('max_completions', e.target.value)} /></label>
        <label>Prazo resgate (h)<input type="number" min={0} max={720} value={f.claim_grace_hours} onChange={(e) => set('claim_grace_hours', e.target.value)} /></label>
      </div>
      <div className="ev-form-banner">
        {BANNERS.map((b) => (
          <button key={b} type="button" aria-label="cor do banner" className={f.banner?.css === b ? 'is-on' : ''} style={{ backgroundImage: b }} onClick={() => set('banner', { ...f.banner, css: b })} />
        ))}
        <select value={f.banner?.icon} onChange={(e) => set('banner', { ...f.banner, icon: e.target.value })} aria-label="ícone">
          {Object.keys(BANNER_ICONS).map((k) => <option key={k} value={k}>{k}</option>)}
        </select>
      </div>

      <h4 className="mk-h">Objetivos</h4>
      {f.objectives.map((o, i) => {
        const kind = kinds.find((k) => k.id === o.kind)
        return (
          <div key={i} className="ev-form-item">
            <div className="ev-form-row">
              <select value={o.kind} onChange={(e) => setObj(i, { kind: e.target.value, params: {} })}>
                {kinds.map((k) => <option key={k.id} value={k.id}>{k.label}</option>)}
              </select>
              <input type="number" min={1} value={o.target} onChange={(e) => setObj(i, { target: e.target.value })} aria-label="meta" />
              {f.objectives.length > 1 && <button type="button" className="ev-x" onClick={() => set('objectives', f.objectives.filter((_, j) => j !== i))} aria-label="Remover objetivo"><Trash2 size={14} /></button>}
            </div>
            <input placeholder={`Texto exibido (padrão: ${kind?.label || ''})`} value={o.label} onChange={(e) => setObj(i, { label: e.target.value })} />
            {(kind?.params || []).map((p) => (
              <label key={p} className="ev-param">{PARAM_LABEL[p] || p}
                {p === 'competition' ? (
                  <select value={o.params?.[p] || ''} onChange={(e) => setObj(i, { params: { ...o.params, [p]: e.target.value } })}>
                    <option value="">qualquer</option>
                    {(opt.competitions || []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                  </select>
                ) : p === 'region' ? (
                  <select value={o.params?.[p] || ''} onChange={(e) => setObj(i, { params: { ...o.params, [p]: e.target.value } })}>
                    <option value="">qualquer</option><option value="BRA">Brasil</option><option value="ENG">Inglaterra</option>
                  </select>
                ) : p === 'tier' ? (
                  <select value={o.params?.[p] || ''} onChange={(e) => setObj(i, { params: { ...o.params, [p]: e.target.value } })}>
                    <option value="">qualquer</option>
                    {(opt.tiers || []).map((t) => <option key={t} value={t}>{t}</option>)}
                  </select>
                ) : (
                  <input type="number" min={1} max={99} placeholder="qualquer" value={o.params?.[p] || ''} onChange={(e) => setObj(i, { params: { ...o.params, [p]: e.target.value } })} />
                )}
              </label>
            ))}
          </div>
        )
      })}
      <button type="button" className="ev-add" onClick={() => set('objectives', [...f.objectives, { kind: 'match_played', target: 1, params: {}, label: '' }])}><Plus size={14} /> objetivo</button>

      <h4 className="mk-h">Recompensas</h4>
      {f.rewards.map((r, i) => (
        <div key={i} className="ev-form-row ev-form-item">
          <select value={r.kind} onChange={(e) => setRew(i, { kind: e.target.value, ref: '' })}>
            {REWARD_KINDS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
          {['coins', 'diamonds', 'energy', 'box'].includes(r.kind) && <input type="number" min={1} value={r.amount} onChange={(e) => setRew(i, { amount: e.target.value })} aria-label="quantidade" />}
          {r.kind === 'box' && (
            <select value={r.ref} onChange={(e) => setRew(i, { ref: e.target.value })} required>
              <option value="">raridade…</option>{(opt.tiers || []).map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
          )}
          {r.kind === 'cosmetic' && (
            <select value={r.ref} onChange={(e) => setRew(i, { ref: e.target.value })} required>
              <option value="">escolha…</option>{(opt.cosmetics || []).map((c) => <option key={c.id} value={c.id}>{c.kind}: {c.label}</option>)}
            </select>
          )}
          {r.kind === 'badge' && (
            <select value={r.ref} onChange={(e) => setRew(i, { ref: e.target.value })} required>
              <option value="">escolha…</option>{(opt.badges || []).map((b) => <option key={b.id} value={b.id}>{b.label}</option>)}
            </select>
          )}
          {f.rewards.length > 1 && <button type="button" className="ev-x" onClick={() => set('rewards', f.rewards.filter((_, j) => j !== i))} aria-label="Remover recompensa"><Trash2 size={14} /></button>}
        </div>
      ))}
      <button type="button" className="ev-add" onClick={() => set('rewards', [...f.rewards, { kind: 'coins', amount: 50, ref: '' }])}><Plus size={14} /> recompensa</button>

      {err && <p className="fr-msg is-error"><CircleAlert size={14} /> {err}</p>}
      <button type="submit" className="gx-btn" disabled={busy}>{busy ? 'Salvando…' : 'Salvar como rascunho'}</button>
      <p className="ev-note">Depois de salvo, publique na lista. Evento publicado que já começou não pode ser alterado (cancele e crie outro).</p>
    </form>
  )
}

export default function AdminEvents({ onChanged }) {
  const [meta, setMeta] = useState(null)
  const [err, setErr] = useState('')
  const [editing, setEditing] = useState(null)
  const [busy, setBusy] = useState(null)

  const load = useCallback(async () => {
    try {
      setMeta(await adminList())
      setErr('')
    } catch (e) {
      setErr(e.message)
    }
  }, [])
  useEffect(() => { load() }, [load])

  async function setStatus(ev, status) {
    setBusy(ev.id)
    try {
      await adminSetStatus(ev.id, status)
      await load()
      onChanged?.()
    } catch (e) {
      setErr(e.message)
    } finally {
      setBusy(null)
    }
  }

  if (err && !meta) return <p className="fr-msg is-error"><CircleAlert size={14} /> {err}</p>
  if (!meta) return <p className="cx-hint center">Carregando…</p>
  if (editing) {
    return <EventForm initial={editing} meta={meta} onCancel={() => setEditing(null)} onSaved={() => { setEditing(null); load(); onChanged?.() }} />
  }
  const now = Date.now()
  return (
    <div className="ev-admin">
      <button type="button" className="gx-btn" onClick={() => setEditing(blank())}><Plus size={16} /> Novo evento</button>
      {err && <p className="fr-msg is-error"><CircleAlert size={14} /> {err}</p>}
      {meta.events.map((ev) => {
        const started = new Date(ev.starts_at).getTime() <= now
        const ended = new Date(ev.ends_at).getTime() <= now
        return (
          <div key={ev.id} className={`ev-admin-row is-${ev.status}`}>
            <span className="ev-admin-main">
              <strong>{ev.name}</strong>
              <small>{STATUS_LABEL[ev.status]}{ended ? ' · encerrado' : ''} · {CATEGORY_LABEL[ev.category]} · {fmtDate(ev.starts_at, true)} → {fmtDate(ev.ends_at, true)}</small>
              <small>{ev.objectives.map((o) => `${o.label} (${o.target})`).join(' · ')}</small>
              <small>{ev.rewards.map((r) => rewardText(r)).join(' · ')} · {ev.completions} {ev.completions === 1 ? 'conclusão' : 'conclusões'}</small>
            </span>
            <span className="ev-admin-actions">
              {!(ev.status === 'published' && started) && ev.status !== 'cancelled' && (
                <button type="button" onClick={() => setEditing({ ...ev, starts_at: toLocal(ev.starts_at), ends_at: toLocal(ev.ends_at), max_completions: ev.max_completions ?? '' })} aria-label="Editar"><Pencil size={14} /></button>
              )}
              {ev.status === 'draft' && !ended && <button type="button" disabled={busy === ev.id} onClick={() => setStatus(ev, 'published')} aria-label="Publicar"><Send size={14} /></button>}
              {ev.status === 'published' && !ended && <button type="button" disabled={busy === ev.id} onClick={() => setStatus(ev, 'cancelled')} aria-label="Cancelar" className="is-danger"><XCircle size={14} /></button>}
            </span>
          </div>
        )
      })}
    </div>
  )
}
