import { useCallback, useEffect, useMemo, useState } from 'react'
import { Flame, ImageUp, Package, Plus, Save, Trash2 } from 'lucide-react'
import { Notice, Skeleton } from '../../components/ui/feedback'
import BigTimeCard, { BigTimeFacts } from '../online/components/BigTime'
import { fetchBigTime, pickPoolPlayers, saveBigTime, savePack, uploadBigTimePhoto } from './adminApi'
import './admin-bigtime.css'

// PAINEL: cartas BIG TIME e caixas da loja. A carta é gerada na hora a partir do cadastro e da foto.
const fmt = (n) => Number(n || 0).toLocaleString('pt-BR')
const toLocal = (iso) => (iso ? new Date(new Date(iso).getTime() - 3 * 3600000).toISOString().slice(0, 16) : '')
const fromLocal = (v) => (v ? `${v}:00-03:00` : null)
const PRIZES = { energy: 'Energia de treino', coins: 'Moedas', cash: 'Dinheiro do clube ($)', whistle: 'Apito de Ouro' }

const blankCard = () => ({ id: '', name: '', full_name: '', pos: 'ATA', sec: [], nat: 'BRA', rating: 106, start_rating: 96, age: 25, match_date: '', opponent: '', team: '', competition: '', score: '', story: '', photo: '', photo_pos: { x: 50, y: 20, zoom: 1 }, style_off: '', style_def: '', ai_styles: [], traits: [], active: true })
const blankPack = () => {
  const now = new Date()
  // padrão: 100 diamantes por giro, 7 dias, ~70 cartas base e ~60 itens; com 2 Big Time a média para tirar as duas fica perto de 9 mil
  return { id: '', title: '', subtitle: '', price: 100, starts_at: toLocal(now.toISOString()), ends_at: toLocal(new Date(now.getTime() + 7 * 864e5).toISOString()), cards: [], base: [],
    others: [{ kind: 'energy', qty: 3, balls: 20 }, { kind: 'coins', qty: 300, balls: 18 }, { kind: 'cash', qty: 50000, balls: 15 }, { kind: 'energy', qty: 10, balls: 4 }, { kind: 'whistle', qty: 1, balls: 3 }] }
}

// Reduz a foto para no máximo 1000 px (webp) antes de enviar.
function shrink(file) {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => {
      const k = Math.min(1, 1000 / Math.max(img.width, img.height))
      const c = document.createElement('canvas')
      c.width = Math.round(img.width * k)
      c.height = Math.round(img.height * k)
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height)
      c.toBlob((b) => (b ? resolve(new File([b], 'foto.webp', { type: 'image/webp' })) : reject(new Error('Não deu para ler a foto'))), 'image/webp', 0.86)
      URL.revokeObjectURL(img.src)
    }
    img.onerror = () => reject(new Error('Arquivo de imagem inválido'))
    img.src = URL.createObjectURL(file)
  })
}

function CardForm({ meta, initial, onSaved, onCancel }) {
  const [f, setF] = useState(initial)
  const [busy, setBusy] = useState(false)
  const [up, setUp] = useState(false)
  const [msg, setMsg] = useState(null)
  const set = (k, v) => setF((x) => ({ ...x, [k]: v }))
  const setPos = (k, v) => setF((x) => ({ ...x, photo_pos: { ...x.photo_pos, [k]: v } }))
  const toggle = (k, v, max) => setF((x) => ({ ...x, [k]: x[k].includes(v) ? x[k].filter((y) => y !== v) : x[k].length >= max ? x[k] : [...x[k], v] }))
  const styles = (kind) => meta.styles.filter((s) => s.kind === kind)
  const preview = useMemo(() => ({
    ...f, rating: Number(f.rating), year: f.match_date ? Number(f.match_date.slice(0, 4)) : '',
    skills: meta.traits.filter((t) => f.traits.includes(t.code)).map((t) => t.name),
  }), [f, meta.traits])
  const valid = f.name.trim() && f.opponent.trim() && f.match_date && Number(f.rating) >= 106 && Number(f.rating) <= 115 && Number(f.start_rating) >= 85 && Number(f.start_rating) <= Number(f.rating)
  const pick = async (e) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setUp(true)
    setMsg(null)
    try {
      set('photo', await uploadBigTimePhoto(await shrink(file)))
    } catch (err) {
      setMsg({ kind: 'error', text: err.message })
    } finally {
      setUp(false)
    }
  }
  const save = async () => {
    setBusy(true)
    setMsg(null)
    try {
      const card = await saveBigTime({ ...f, rating: Number(f.rating), start_rating: Number(f.start_rating), age: Number(f.age) })
      onSaved(card)
    } catch (e) {
      setMsg({ kind: 'error', text: e.message })
    } finally {
      setBusy(false)
    }
  }
  return (
    <div className="abt-form">
      <section className="ad-card">
        <h3><Flame size={16} /> {f.id ? `Editar ${f.name}` : 'Nova carta Big Time'}</h3>
        {msg && <Notice kind={msg.kind} onClose={() => setMsg(null)}>{msg.text}</Notice>}
        <div className="abt-grid">
          <label className="ad-field">Nome na carta<input value={f.name} maxLength={28} onChange={(e) => set('name', e.target.value)} placeholder="Ronaldinho" /></label>
          <label className="ad-field">Nome completo<input value={f.full_name} maxLength={80} onChange={(e) => set('full_name', e.target.value)} placeholder="Ronaldo de Assis Moreira" /></label>
          <label className="ad-field">Overall máximo (106 a 115)<input type="number" min={106} max={115} value={f.rating} onChange={(e) => setF((x) => ({ ...x, rating: e.target.value, start_rating: Math.max(85, Number(e.target.value) - 10) }))} /></label>
          <label className="ad-field">Overall inicial (treina até o máximo)<input type="number" min={85} max={f.rating} value={f.start_rating} onChange={(e) => set('start_rating', e.target.value)} /></label>
          <label className="ad-field">Posição<select value={f.pos} onChange={(e) => set('pos', e.target.value)}>{meta.positions.map((p) => <option key={p}>{p}</option>)}</select></label>
          <label className="ad-field">Nacionalidade (sigla)<input value={f.nat} maxLength={3} onChange={(e) => set('nat', e.target.value.toUpperCase())} /></label>
          <label className="ad-field">Idade no dia do jogo<input type="number" min={15} max={45} value={f.age} onChange={(e) => set('age', e.target.value)} /></label>
        </div>
        <div className="ad-field"><span>Posições secundárias</span>
          <div className="abt-chips">{meta.positions.filter((p) => p !== f.pos).map((p) => (
            <button key={p} type="button" className={f.sec.includes(p) ? 'is-on' : ''} onClick={() => toggle('sec', p, 4)}>{p}</button>
          ))}</div>
        </div>
        <h3 className="ad-sub">A atuação</h3>
        <div className="abt-grid">
          <label className="ad-field">Data do jogo<input type="date" value={f.match_date || ''} onChange={(e) => set('match_date', e.target.value)} /></label>
          <label className="ad-field">Time dele<input value={f.team} maxLength={40} onChange={(e) => set('team', e.target.value)} placeholder="Barcelona" /></label>
          <label className="ad-field">Adversário<input value={f.opponent} maxLength={40} onChange={(e) => set('opponent', e.target.value)} placeholder="Real Madrid" /></label>
          <label className="ad-field">Competição<input value={f.competition} maxLength={40} onChange={(e) => set('competition', e.target.value)} placeholder="La Liga" /></label>
          <label className="ad-field">Placar<input value={f.score} maxLength={12} onChange={(e) => set('score', e.target.value)} placeholder="3 x 0" /></label>
        </div>
        <label className="ad-field">História da atuação<textarea rows={3} maxLength={600} value={f.story} onChange={(e) => set('story', e.target.value)} placeholder="Dois gols e o Bernabéu aplaudindo de pé." /></label>
        <h3 className="ad-sub">Foto</h3>
        <div className="abt-photo">
          <label className="ad-btn-ghost abt-upload"><ImageUp size={15} /> {up ? 'Enviando…' : f.photo ? 'Trocar foto' : 'Enviar foto'}
            <input type="file" accept="image/png,image/jpeg,image/webp" onChange={pick} disabled={up} hidden />
          </label>
          <label>Horizontal<input type="range" min={0} max={100} value={f.photo_pos.x} onChange={(e) => setPos('x', Number(e.target.value))} /></label>
          <label>Vertical<input type="range" min={0} max={100} value={f.photo_pos.y} onChange={(e) => setPos('y', Number(e.target.value))} /></label>
          <label>Zoom<input type="range" min={1} max={2.5} step={0.05} value={f.photo_pos.zoom} onChange={(e) => setPos('zoom', Number(e.target.value))} /></label>
        </div>
        <h3 className="ad-sub">Estilo e habilidades</h3>
        <div className="abt-grid">
          <label className="ad-field">Com a bola<select value={f.style_off || ''} onChange={(e) => set('style_off', e.target.value)}><option value="">Automático</option>{styles('off').map((s) => <option key={s.code} value={s.code}>{s.name}</option>)}</select></label>
          <label className="ad-field">Sem a bola<select value={f.style_def || ''} onChange={(e) => set('style_def', e.target.value)}><option value="">Automático</option>{styles('def').map((s) => <option key={s.code} value={s.code}>{s.name}</option>)}</select></label>
        </div>
        <div className="ad-field"><span>Habilidades (até 6)</span>
          <div className="abt-chips">{meta.traits.map((t) => (
            <button key={t.code} type="button" title={t.descr} className={f.traits.includes(t.code) ? 'is-on' : ''} onClick={() => toggle('traits', t.code, 6)}>{t.name}</button>
          ))}</div>
        </div>
        <div className="ad-field"><span>Estilos da IA (até 3)</span>
          <div className="abt-chips">{styles('ai').map((s) => (
            <button key={s.code} type="button" title={s.descr} className={f.ai_styles.includes(s.code) ? 'is-on' : ''} onClick={() => toggle('ai_styles', s.code, 3)}>{s.name}</button>
          ))}</div>
        </div>
        <div className="ad-actions">
          {onCancel ? <button type="button" className="ad-btn-ghost" onClick={onCancel}>Cancelar</button> : <span />}
          <button type="button" className="ad-btn" disabled={!valid || busy || up} onClick={save}><Save size={15} /> {busy ? 'Salvando…' : f.id ? 'Salvar carta' : 'Criar carta'}</button>
        </div>
      </section>
      <aside className="ad-card abt-preview">
        <h3>Prévia</h3>
        <BigTimeCard bt={preview} size="lg" />
        <BigTimeFacts bt={preview} />
      </aside>
    </div>
  )
}

function PackForm({ cards, initial, onSaved, onCancel }) {
  const [f, setF] = useState(initial)
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState(null)
  const set = (k, v) => setF((x) => ({ ...x, [k]: v }))
  const toggleCard = (id) => set('cards', f.cards.includes(id) ? f.cards.filter((x) => x !== id) : [...f.cards, id])
  const setOther = (i, k, v) => set('others', f.others.map((o, j) => (j === i ? { ...o, [k]: v } : o)))
  const [pick, setPick] = useState({ n: 70, lo: 68, hi: 82 })
  const [picking, setPicking] = useState(false)
  const total = f.cards.length + f.base.length + f.others.reduce((s, o) => s + Number(o.balls || 0), 0)
  // sem reposição: média de tiragens para tirar todas as k Big Time = k(N+1)/(k+1); pior caso = N
  const k = f.cards.length
  const avg = k ? Math.round((k * (total + 1)) / (k + 1)) : 0
  const addBase = async () => {
    setPicking(true)
    try {
      const got = await pickPoolPlayers(Number(pick.n), Number(pick.lo), Number(pick.hi))
      const have = new Set(f.base.map((b) => b.src))
      set('base', [...f.base, ...got.filter((g) => !have.has(g.src))])
    } catch (e) {
      setMsg({ kind: 'error', text: e.message })
    } finally {
      setPicking(false)
    }
  }
  const valid = f.title.trim() && f.cards.length > 0 && Number(f.price) > 0 && f.ends_at > f.starts_at
  const save = async () => {
    setBusy(true)
    setMsg(null)
    try {
      const items = [
        ...f.cards.map((ref) => ({ id: f.itemIds?.[ref] || '', kind: 'bigtime', ref })),
        ...f.base.map((b) => ({ id: b.itemId || '', kind: 'player', src: b.src })),
        ...f.others.filter((o) => Number(o.qty) > 0 && Number(o.balls) > 0).map((o) => ({ id: o.id || '', kind: o.kind, qty: Number(o.qty), balls: Number(o.balls) })),
      ]
      await savePack({ id: f.id, title: f.title, subtitle: f.subtitle, price: Number(f.price), starts_at: fromLocal(f.starts_at), ends_at: fromLocal(f.ends_at), items })
      onSaved()
    } catch (e) {
      setMsg({ kind: 'error', text: e.message })
    } finally {
      setBusy(false)
    }
  }
  return (
    <section className="ad-card">
      <h3><Package size={16} /> {f.id ? 'Editar caixa' : 'Nova caixa da semana'}</h3>
      {msg && <Notice kind={msg.kind} onClose={() => setMsg(null)}>{msg.text}</Notice>}
      <div className="abt-grid">
        <label className="ad-field">Nome da caixa<input value={f.title} maxLength={60} onChange={(e) => set('title', e.target.value)} placeholder="Big Time · Clássicos" /></label>
        <label className="ad-field">Subtítulo<input value={f.subtitle} maxLength={120} onChange={(e) => set('subtitle', e.target.value)} placeholder="Atuações históricas contra rivais" /></label>
        <label className="ad-field">Diamantes por tiragem<input type="number" min={1} max={10000} value={f.price} onChange={(e) => set('price', e.target.value)} /></label>
        <label className="ad-field">Início (Brasília)<input type="datetime-local" value={f.starts_at} onChange={(e) => set('starts_at', e.target.value)} /></label>
        <label className="ad-field">Fim (Brasília)<input type="datetime-local" value={f.ends_at} onChange={(e) => set('ends_at', e.target.value)} /></label>
      </div>
      <h3 className="ad-sub">Cartas na caixa ({f.cards.length})</h3>
      <div className="abt-pick">
        {cards.filter((c) => c.active || f.cards.includes(c.id)).map((c) => (
          <button key={c.id} type="button" className={f.cards.includes(c.id) ? 'is-on' : ''} onClick={() => toggleCard(c.id)} aria-pressed={f.cards.includes(c.id)}>
            <BigTimeCard bt={c} size="sm" />
          </button>
        ))}
        {cards.length === 0 && <p className="ad-muted">Cadastre uma carta primeiro.</p>}
      </div>
      <h3 className="ad-sub">Cartas base ({f.base.length})</h3>
      <div className="abt-photo">
        <label>Quantas<input type="number" min={1} max={200} value={pick.n} onChange={(e) => setPick({ ...pick, n: e.target.value })} /></label>
        <label>Overall de<input type="number" min={40} max={95} value={pick.lo} onChange={(e) => setPick({ ...pick, lo: e.target.value })} /></label>
        <label>até<input type="number" min={40} max={99} value={pick.hi} onChange={(e) => setPick({ ...pick, hi: e.target.value })} /></label>
        <button type="button" className="ad-btn-ghost" disabled={picking} onClick={addBase}><Plus size={14} /> {picking ? 'Sorteando…' : 'Sortear cartas base'}</button>
        {f.base.some((b) => !b.itemId) && <button type="button" className="ad-btn-ghost" onClick={() => set('base', f.base.filter((b) => b.itemId))}><Trash2 size={14} /> Limpar novas</button>}
      </div>
      <div className="abt-base">
        {f.base.map((b) => (
          <span key={b.src}><b>{b.ovr}</b> {b.pos} · {b.name}{!b.itemId && <button type="button" aria-label={`Tirar ${b.name}`} onClick={() => set('base', f.base.filter((x) => x.src !== b.src))}>×</button>}</span>
        ))}
      </div>
      <h3 className="ad-sub">Outros prêmios</h3>
      <table className="ad-table abt-others">
        <thead><tr><th>Prêmio</th><th className="num">Quantidade</th><th className="num">Vezes na caixa</th><th /></tr></thead>
        <tbody>
          {f.others.map((o, i) => (
            <tr key={i}>
              <td><select value={o.kind} disabled={Boolean(o.id)} onChange={(e) => setOther(i, 'kind', e.target.value)}>{Object.entries(PRIZES).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></td>
              <td className="num"><input type="number" min={1} value={o.qty} onChange={(e) => setOther(i, 'qty', e.target.value)} /></td>
              <td className="num"><input type="number" min={1} max={200} value={o.balls} onChange={(e) => setOther(i, 'balls', e.target.value)} /></td>
              <td className="num">{!o.id && <button type="button" className="ad-btn-ghost" aria-label="Tirar prêmio" onClick={() => set('others', f.others.filter((_, j) => j !== i))}><Trash2 size={14} /></button>}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <button type="button" className="ad-btn-ghost" onClick={() => set('others', [...f.others, { kind: 'cash', qty: 100000, balls: 2 }])}><Plus size={14} /> Prêmio</button>
      <p className="ad-muted">Só aqui no painel: cada técnico tem a própria caixa com {total} prêmio(s). Para tirar {k > 1 ? `as ${k} Big Time` : 'a Big Time'}, em média {fmt(avg)} giros ({fmt(avg * Number(f.price || 0))} diamantes); no pior caso {fmt(total)} giros ({fmt(total * Number(f.price || 0))}). A loja não mostra esses números.</p>
      <div className="ad-actions">
        {onCancel ? <button type="button" className="ad-btn-ghost" onClick={onCancel}>Cancelar</button> : <span />}
        <button type="button" className="ad-btn" disabled={!valid || busy} onClick={save}><Save size={15} /> {busy ? 'Salvando…' : f.id ? 'Salvar caixa' : 'Publicar caixa'}</button>
      </div>
    </section>
  )
}

export default function AdminBigTime() {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [card, setCard] = useState(null) // formulário de carta aberto
  const [pack, setPack] = useState(null)
  const [msg, setMsg] = useState('')
  const [now] = useState(() => Date.now())
  const load = useCallback(() => fetchBigTime().then(setData).catch((e) => setError(e.message)), [])
  useEffect(() => { load() }, [load])
  if (error) return <Notice kind="error">{error}</Notice>
  if (!data) return <Skeleton rows={6} />
  const editPack = (p) => setPack({
    id: p.id, title: p.title, subtitle: p.subtitle || '', price: p.price, starts_at: toLocal(p.starts_at), ends_at: toLocal(p.ends_at),
    cards: p.items.filter((i) => i.kind === 'bigtime').map((i) => i.bt.id),
    base: p.items.filter((i) => i.kind === 'player' && i.player).map((i) => ({ ...i.player, itemId: i.id })),
    itemIds: Object.fromEntries(p.items.filter((i) => i.kind === 'bigtime').map((i) => [i.bt.id, i.id])),
    others: p.items.filter((i) => !['bigtime', 'player'].includes(i.kind)).map((i) => ({ id: i.id, kind: i.kind, qty: i.qty, balls: i.balls })),
  })
  return (
    <>
      <div className="ad-head">
        <h2>Big Time</h2>
        <span className="ad-row-actions">
          <button type="button" className="ad-btn-ghost" onClick={() => { setPack(null); setCard(blankCard()) }}><Plus size={15} /> Nova carta</button>
          <button type="button" className="ad-btn" onClick={() => { setCard(null); setPack(blankPack()) }}><Package size={15} /> Nova caixa</button>
        </span>
      </div>
      {msg && <Notice kind="ok" onClose={() => setMsg('')}>{msg}</Notice>}
      {card && <CardForm key={card.id || 'new'} meta={data} initial={card} onCancel={() => setCard(null)} onSaved={(c) => { setCard(null); setMsg(`${c.name} salvo.`); load() }} />}
      {pack && <PackForm key={pack.id || 'new'} cards={data.cards} initial={pack} onCancel={() => setPack(null)} onSaved={() => { setPack(null); setMsg('Caixa salva. Ela aparece na Loja dentro do período.'); load() }} />}
      <section className="ad-card">
        <h3><Package size={16} /> Caixas</h3>
        {data.packs.length === 0 ? <p className="ad-muted">Nenhuma caixa ainda.</p> : (
          <table className="ad-table">
            <thead><tr><th>Caixa</th><th>Período</th><th className="num">Preço</th><th className="num">Prêmios</th><th className="num">Tiragens</th><th className="num">Diamantes</th><th /></tr></thead>
            <tbody>
              {data.packs.map((p) => {
                const live = new Date(p.starts_at).getTime() <= now && new Date(p.ends_at).getTime() > now
                return (
                  <tr key={p.id}>
                    <td><b>{p.title}</b>{live && <span className="abt-live">No ar</span>}</td>
                    <td className="ad-muted">{new Date(p.starts_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })} → {new Date(p.ends_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })}</td>
                    <td className="num">{fmt(p.price)}</td>
                    <td className="num">{p.total}</td>
                    <td className="num">{fmt(p.draws)}</td>
                    <td className="num">{fmt(p.diamonds)}</td>
                    <td className="num"><button type="button" className="ad-btn-ghost" onClick={() => { setCard(null); editPack(p) }}>Editar</button></td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </section>
      <section className="ad-card">
        <h3><Flame size={16} /> Cartas ({data.cards.length})</h3>
        <div className="abt-list">
          {data.cards.map((c) => (
            <div key={c.id} className="abt-item">
              <BigTimeCard bt={c} size="sm" onClick={() => { setPack(null); setCard({ ...blankCard(), ...c, match_date: c.match_date?.slice(0, 10), full_name: c.full_name || '', team: c.team || '', competition: c.competition || '', score: c.score || '', story: c.story || '', photo: c.photo || '', style_off: c.style_off || '', style_def: c.style_def || '' }) }} />
              <small>{fmt(c.owners)} clube(s)</small>
            </div>
          ))}
          {data.cards.length === 0 && <p className="ad-muted">Nenhuma carta cadastrada.</p>}
        </div>
      </section>
    </>
  )
}
