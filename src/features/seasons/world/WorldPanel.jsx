import { useCallback, useEffect, useRef, useState } from 'react'
import { CalendarDays, Coins, Globe2, Newspaper } from 'lucide-react'
import { worldRpc, requestId, advanceWorld, searchPlayers, negotiations, newsFeed, readNews, financeHistory, money, dateLabel } from '../services/careerWorldApi'
import { fetchPlayer, fetchStandings, fetchFixtures } from '../services/managerApi'
import BasePlayerCard from '../../cards/components/BasePlayerCard'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { CLUB_CATALOG } from '../../club/data/clubCatalog'
import Sheet from '../ui/Sheet'
import PlayerSheet from '../components/PlayerSheet'
import StandingsTable from '../components/StandingsTable'
import { POS_ORDER } from '../utils/managerUtils'
import { COMP_SHORT } from '../utils/seasonUtils'
import { isSessionError } from '../../../lib/sessionRecovery'
import './world.css'

const clubName = id => getClubById(id)?.name || id || 'Livre no mercado'
const countries = [...new Set(Object.values(CLUB_CATALOG).map(c => c.country))].sort()
const roles = { key: 'Peça-chave', starter: 'Titular', rotation: 'Rotação', prospect: 'Promessa' }
const states = { seller_review: 'Sua decisão sobre a venda', club_pending: 'Clube analisando', club_counter: 'Contraproposta do clube', player_pending: 'Atleta analisando', player_counter: 'Negociar contrato do atleta', agreed: 'Aguardando janela', precontract: 'Pré-contrato assinado', completed: 'Concluída', rejected: 'Recusada', expired: 'Expirada', cancelled: 'Cancelada', failed_funds: 'Recursos insuficientes' }
function NumberField({ label, value, onChange, min = 0, max = 100000000 }) {
  return <label className="cw-field">{label}<input type="number" inputMode="numeric" min={min} max={max} step="1" required value={value} onChange={e => onChange(e.target.value)} /></label>
}
function ClubLine({ id }) { return <span className="cw-club"><ClubCrest clubId={id} size={22} />{clubName(id)}</span> }

export function WorldStrip({ ctx, actions }) {
  const w = ctx.hub.world
  if (!w) return null
  return <section className="sn-sec cw-strip">
    <div className="cw-row"><span><CalendarDays size={16} /> {dateLabel(w.today)}</span><button className="sn-link" onClick={() => actions.goTab('career', 'world')}>Mundo <Globe2 size={15} /></button></div>
    <small>Brasil e Europa · {w.news_unread || 0} notícias novas</small>
    {w.needs_sync && <p role="status">Atualização pendente: {w.due_matches} partidas do mundo. Atualize para continuar o calendário.</p>}
    <button type="button" className="gx-btn-ghost" disabled={!!ctx.busy || !!ctx.hub.live_match} onClick={() => actions.goTab('career', 'world')}>{w.needs_sync ? 'Atualizar mundo' : 'Calendário, mercado e finanças'}</button>
  </section>
}

export default function WorldPanel({ hub, onRefresh, initialArea = 'news', onReport, onHome }) {
  const [area, updateArea] = useState(initialArea)
  const areaRef = useRef(initialArea)
  const [rows, setRows] = useState([])
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [filters, setFilters] = useState({ p_query: '', p_country: '', p_position: '', p_region: '', p_club: '', p_max_value: null, p_page: 0 })
  const [player, setPlayer] = useState(null)
  const [detail, setDetail] = useState(null)
  const [offer, setOffer] = useState(null)
  const [clubFee, setClubFee] = useState(0)
  const [terms, setTerms] = useState({ fee: 0, installments: 1, bonus: 0, precontract: false, salary: 100, years: 3, signing: 0, role: 'rotation', appearance: 0, goal: 0 })
  const [investment, setInvestment] = useState(100)
  const [regional, setRegional] = useState(null)
  const [competition, setCompetition] = useState('')
  const [table, setTable] = useState([])
  const [matches, setMatches] = useState([])
  const [syncProgress, setSyncProgress] = useState(0)
  const mounted = useRef(true)
  const request = useRef(0)
  const w = hub.world
  const own = hub.coach.club_id
  function setArea(next) { areaRef.current = next; request.current++; updateArea(next); setRows([]) }
  const reload = useCallback(async () => {
    const key = ++request.current
    const data = area === 'market' || area === 'contracts' ? await searchPlayers({ ...filters, p_club: area === 'contracts' ? 'mine' : filters.p_club }) : area === 'deals' ? await negotiations() : area === 'finance' ? await financeHistory() : await newsFeed()
    if (mounted.current && key === request.current && areaRef.current === area) setRows(data || [])
  }, [area, filters])
  useEffect(() => { mounted.current = true; return () => { mounted.current = false } }, [])
  useEffect(() => { const timer = setTimeout(() => { setRows([]); reload().catch(e => { if (!isSessionError(e) && mounted.current) setError(e.message) }) }, 250); return () => clearTimeout(timer) }, [reload, hub.world.today, hub.coach.club_id])
  async function run(fn) {
    if (busy) return
    setBusy(true); setError(''); setMessage('')
    try { await fn(); await onRefresh?.(); if (mounted.current) await reload() }
    catch (e) { if (!isSessionError(e) && mounted.current) setError(e.message) }
    finally { if (mounted.current) setBusy(false) }
  }
  async function sync(days) {
    await run(async () => {
      setSyncProgress(0)
      let remaining = days
      let d = await advanceWorld(remaining)
      let total = d.matches || 0
      let advanced = d.days || 0
      remaining = Math.max(0, remaining - (d.days || 0))
      while (mounted.current && !(d.next_season_ready && days > 0) && (d.more || (remaining > 0 && !d.stopped_for_match))) {
        if (!d.more && !d.matches && !d.days) break
        setSyncProgress(total)
        d = await advanceWorld(d.more ? 0 : remaining)
        total += d.matches || 0
        advanced += d.days || 0
        remaining = Math.max(0, remaining - (d.days || 0))
      }
      if (mounted.current) {
        setSyncProgress(total)
        setMessage(d.next_season_ready ? 'A próxima temporada está pronta. Volte ao Início para começar e continuar o calendário.' : d.stopped_for_match ? `Dia de partida. Volte ao Início para comandar seu time. ${total} partidas atualizadas.` : `${advanced} dia(s) avançados · ${total} partidas atualizadas. Data: ${dateLabel(d.today)}.`)
      }
    })
  }
  const invoke = (fn, args) => worldRpc(fn, { ...args, p_request: requestId() })
  async function openPlayer(p) { setPlayer(p); setTerms(t => ({ ...t, fee: Math.round(p.value * 1.2), salary: Math.ceil((p.monthly_salary || p.value * .0065) * 1.15) })) }
  const buy = e => { e.preventDefault(); run(async () => { await invoke('career_transfer_bid', { p_player: player.id, p_fee: +terms.fee, p_installments: +terms.installments, p_bonus: +terms.bonus, p_precontract: terms.precontract }); setPlayer(null); setArea('deals'); setMessage('Proposta enviada. Os clubes respondem com o passar dos dias.') }) }
  const contract = e => { e.preventDefault(); run(async () => { await invoke('career_player_offer', { p_id: offer.id, p_salary: +terms.salary, p_years: +terms.years, p_signing: +terms.signing, p_role: terms.role, p_appearance: +terms.appearance, p_goal: +terms.goal }); setOffer(null); setMessage('Contrato enviado ao atleta. Aguarde a resposta nos próximos dias.') }) }
  const respond = (n, action, fee = n.fee) => run(async () => { await invoke('career_transfer_respond', { p_id: n.id, p_action: action, p_fee: +fee }); setOffer(null); setMessage('Resposta registrada.') })
  const loadRegion = async (s, comp) => { setRegional(s); setCompetition(comp); const key = ++request.current; try { const [t, f] = await Promise.all([fetchStandings(s.season_id, comp), fetchFixtures(s.season_id, comp)]); if (mounted.current && key === request.current) { setTable(t || []); setMatches(f.filter(x => x.status === 'played').slice(-10)) } } catch(e) { if (!isSessionError(e)) setError(e.message) } }
  const edit = field => value => setTerms(t => ({ ...t, [field]: value }))
  if (!w) return null
  return <div className="cw-panel">
    <section className="sn-sec">
      <div className="cw-row"><h2 className="gx-title"><Globe2 size={18} /> Mundo do futebol</h2><b>{dateLabel(w.today)}</b></div>
      <p className="sn-hint">Competições e contratos seguem a data da sua carreira.</p>
      {w.needs_sync && <p>Há {w.due_matches} partidas para atualizar. O processamento pode ser retomado ao voltar.</p>}
      <div className="cw-actions"><button className="gx-btn" disabled={busy || !!hub.live_match} onClick={() => sync(0)}>{busy ? 'Processando…' : 'Atualizar resultados'}</button><button className="gx-btn-ghost" disabled={busy || !!hub.live_match} onClick={() => sync(1)}>+1 dia</button><button className="gx-btn-ghost" disabled={busy || !!hub.live_match} onClick={() => sync(7)}>+7 dias</button></div>
      {onHome && hub.season.status === 'finished' && <button type="button" className="sn-link" onClick={onHome}>Ver a próxima temporada no Início</button>}
      {onHome && !w.needs_sync && hub.next_event?.kind === 'mine' && !(hub.next_event.days_until > 0) && <button type="button" className="sn-link" onClick={onHome}>Ir para a partida no Início</button>}
      {busy && <p role="status">Atualizando a carreira… {syncProgress > 0 ? `${syncProgress} partidas processadas` : ''}</p>}
    </section>
    {error && <p className="cw-alert" role="alert">{error}</p>}{message && <p className="cw-notice" role="status">{message}</p>}
    <div className="sn-seg cw-nav" role="tablist" aria-label="Gestão do clube">
      {[['news','Notícias'],['world','Campeonatos'],['finance','Finanças'],['market','Mercado'],['deals','Negociações'],['contracts','Contratos']].map(([id,label]) => <button key={id} role="tab" aria-selected={area===id} className={area===id?'is-on':''} onClick={() => setArea(id)}>{label}</button>)}
    </div>
    {area === 'news' && <div className="sn-stack">{rows.length===0 && <p className="sn-hint">Nenhuma notícia neste momento.</p>}{rows.map(n => <article key={n.id} className={`sn-sec cw-news ${n.read?'':'is-new'}`}>
      <small><Newspaper size={13}/> {dateLabel(n.on_date)}</small><h3>{n.title}</h3>
      {n.metadata?.big_signing && <div className="cw-announcement"><b>NOVA CONTRATAÇÃO</b><button className="cw-card-button" onClick={() => run(async () => setDetail(await fetchPlayer(n.player_id)))}><BasePlayerCard player={{ id:n.player_id,name:n.title.split(' assina')[0],club_id:n.club_id,overall:n.metadata.overall,position:n.metadata.position }} width={128}/></button><span>{clubName(n.metadata.from_club)} → {clubName(n.metadata.to_club)}</span><b>{money(n.metadata.fee)} moedas</b></div>}
      <p>{n.body}</p>{!n.read && <button className="sn-link" disabled={busy} onClick={() => run(() => readNews([n.id]))}>Marcar como lida</button>}
    </article>)}{rows.length>=40 && <button className="gx-btn-ghost" disabled={busy} onClick={async () => { try { const older = await newsFeed(Math.min(...rows.map(n=>n.id))); if (mounted.current) setRows(r=>[...r,...older]) } catch(e) { if (!isSessionError(e)) setError(e.message) } }}>Mais notícias</button>}</div>}
    {area==='world' && <section className="sn-sec"><h3>Temporadas regionais</h3><div className="sn-stack">{w.seasons.map(s=><div key={s.season_id}><b>{s.region==='BRA'?'Brasil':'Europa'} · {s.year}{s.region==='ENG'?`/${String(s.year+1).slice(-2)}`:''}</b><small> · {s.status==='active'?'Em andamento':'Encerrada'}</small><div className="cw-actions">{(s.region==='BRA'?['brasileirao','serie_b','copa_brasil','libertadores']:['premier_league','championship','fa_cup','efl_cup','ucl']).map(c=><button className="gx-btn-ghost" key={c} onClick={()=>loadRegion(s,c)}>{COMP_SHORT[c]||c}</button>)}</div></div>)}</div>
      {regional && <div><h3>{COMP_SHORT[competition]} · {regional.year}</h3><StandingsTable rows={table} myClub={own} zones={[]} /><div className="sn-stack">{matches.map(f=><button key={f.id} className="cw-result" onClick={() => onReport?.(f.id)}><ClubLine id={f.home_club}/><b>{f.home_goals} × {f.away_goals}</b><ClubLine id={f.away_club}/></button>)}</div></div>}
    </section>}
    {area==='finance' && <><section className="sn-sec"><h3><Coins size={17}/> Finanças do clube</h3>{w.club ? <><ClubLine id={own}/><div className="cw-grid">{[['Caixa',w.club.cash],['Dívidas',w.club.debt],['Folha mensal prevista',w.club.payroll],['Reservas e parcelas',w.club.reserved],['Livre para negociar',w.club.available],['Patrimônio investido',w.club.infrastructure]].map(([label,v])=><span key={label}><small>{label}</small><b>{money(v)}</b></span>)}</div><p>Risco financeiro: {Math.round(w.club.financial_risk)}% · {w.club.window_open?'Janela aberta':`Janela fechada · próxima: ${dateLabel(w.club.next_window)}`}</p><p className="sn-hint">O orçamento livre desconta compromissos, dívidas e dois meses da folha prevista, com estimativa dos bônus. Valores são moedas de simulação.</p><form onSubmit={e=>{e.preventDefault();run(async()=>{await invoke('career_club_invest',{p_amount:+investment});setMessage('Investimento transferido ao clube.')})}}><NumberField label={`Investir da sua carteira (${money(hub.career.coins)} moedas)`} value={investment} max={Math.min(hub.career.coins,1000000)} min={1} onChange={setInvestment}/><button className="gx-btn" disabled={busy}>Transferir ao clube</button></form></>:<p>Assuma um clube para administrar seu orçamento.</p>}</section><section className="sn-sec"><h3>Histórico financeiro</h3>{rows.map(r=><div key={r.id} className="cw-ledger"><span><b>{r.description}</b><small>{dateLabel(r.on_date)} · Saldo {money(r.cash_after)}</small></span><b className={r.amount<0?'cw-negative':'cw-positive'}>{r.amount>0?'+':''}{money(r.amount)}</b></div>)}</section></>}
    {(area==='market'||area==='contracts') && <>
      <form className="sn-sec cw-filters" onSubmit={e=>{e.preventDefault();reload().catch(e=>setError(e.message))}}>
        <label className="cw-field">Buscar atleta<input type="search" maxLength={60} value={filters.p_query} onChange={e=>setFilters(f=>({...f,p_query:e.target.value,p_page:0}))}/></label>
        <div className="cw-two"><label className="cw-field">Posição<select aria-label="Posição" value={filters.p_position} onChange={e=>setFilters(f=>({...f,p_position:e.target.value,p_page:0}))}><option value="">Todas</option>{POS_ORDER.map(p=><option key={p}>{p}</option>)}</select></label><label className="cw-field">Região<select aria-label="Região" value={filters.p_region} onChange={e=>setFilters(f=>({...f,p_region:e.target.value,p_page:0}))}><option value="">Mundo</option><option value="BRA">América do Sul</option><option value="ENG">Europa</option><option value="free">Sem contrato</option></select></label></div>
        <label className="cw-field">País do clube<select aria-label="País do clube" value={filters.p_country} onChange={e=>setFilters(f=>({...f,p_country:e.target.value,p_page:0}))}><option value="">Todos os países</option>{countries.map(c=><option key={c}>{c}</option>)}</select></label>
        <NumberField label="Valor máximo (vazio: todos)" value={filters.p_max_value??''} onChange={v=>setFilters(f=>({...f,p_max_value:v===''?null:+v,p_page:0}))}/>
        <small>{area==='contracts'?'Seu elenco e seus vínculos':'Mercado esportivo internacional'} · {w.club?.window_open?'Janela aberta':'Janela fechada; livres e pré-contratos disponíveis'}</small>
      </form>
      <div className="cw-player-grid">{rows.map(p=><button type="button" key={p.id} className="cw-player" onClick={()=>openPlayer(p)}><BasePlayerCard player={p} width={94}/><b>{p.short_name||p.name}</b><small>{clubName(p.club_id)}</small><span>{money(p.value)} moedas</span>{area==='contracts'&&<small>Moral {Math.round(p.morale)} · {roles[p.promised_role]}{p.transfer_requested?' · Pede para sair':''}</small>}</button>)}</div>
      {rows.length===0&&<p className="sn-hint">Nenhum atleta encontrado.</p>}
      <div className="cw-actions"><button className="gx-btn-ghost" disabled={filters.p_page===0} onClick={()=>setFilters(f=>({...f,p_page:f.p_page-1}))}>Anterior</button><span>Página {filters.p_page+1}</span><button className="gx-btn-ghost" disabled={rows.length<30} onClick={()=>setFilters(f=>({...f,p_page:f.p_page+1}))}>Próxima</button></div>
    </>}
    {area==='deals' && <div className="sn-stack">{rows.length===0&&<p className="sn-hint">Nenhuma negociação. Busque atletas no Mercado ou aguarde propostas de outros clubes.</p>}{rows.map(n=><article key={n.id} className="sn-sec"><small>{states[n.status]} · {['precontract','agreed','completed'].includes(n.status)?'Registro':'Prazo'} {dateLabel(['precontract','agreed','completed'].includes(n.status)?n.register_on:n.expires_on)}</small><h3>{n.player_name}</h3><p>{clubName(n.seller_club)} → {clubName(n.buyer_club)}</p><b>{money(n.fee)} moedas · {n.installments} parcela(s)</b><p>{n.response}</p><div className="cw-actions"><button className="gx-btn-ghost" onClick={()=>{setOffer(n);setClubFee(n.fee);setTerms(t=>({...t,salary:n.monthly_salary||Math.ceil(n.valuation*.0075),years:n.contract_years||3,signing:n.signing_bonus||0,role:n.role||'rotation',appearance:n.appearance_bonus||0,goal:n.goal_bonus||0}))}}>Ver negociação</button></div></article>)}</div>}
    {player && <Sheet title={player.short_name||player.name} kicker="Atleta e contrato" onClose={()=>setPlayer(null)} tall>
      <div className="cw-announcement"><BasePlayerCard player={player} width={132}/><ClubLine id={player.club_id}/></div>
      <div className="cw-grid"><span><small>Idade {player.age_estimated?'estimada':''}</small><b>{player.age} anos</b></span><span><small>Potencial estimado</small><b>{player.potential}</b></span><span><small>Valor</small><b>{money(player.value)}</b></span><span><small>Salário mensal</small><b>{money(player.monthly_salary)}</b></span><span><small>Contrato até</small><b>{dateLabel(player.expires_on)}</b></span><span><small>Minutos nas temporadas atuais</small><b>{player.minutes}</b></span><span><small>Satisfação</small><b>{Math.round(player.morale)}%</b></span><span><small>Promessa</small><b>{roles[player.promised_role]}</b></span></div>
      <button className="gx-btn-ghost" disabled={busy} onClick={()=>run(async()=>setDetail(await fetchPlayer(player.id)))}>Atributos e estatísticas</button>
      {player.club_id===own ? <div className="sn-stack"><h3>Gestão do contrato</h3><p>{player.transfer_requested?'O atleta quer sair. Procure melhorar seu papel e os pagamentos.':'Cumpra o papel prometido com oportunidades em campo.'}</p><label className="cw-field">Papel prometido<select aria-label="Papel prometido" value={player.promised_role} onChange={e=>{const role=e.target.value;run(async()=>{await worldRpc('career_player_role',{p_player:player.id,p_role:role});setPlayer(p=>({...p,promised_role:role}))})}}>{Object.entries(roles).map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></label><button className="gx-btn" disabled={busy} onClick={()=>run(async()=>{await invoke('career_contract_renew',{p_player:player.id});setPlayer(null);setArea('deals')})}>Negociar renovação</button></div> : <form onSubmit={buy} className="sn-stack"><h3>Proposta ao clube</h3><NumberField label="Taxa fixa" value={terms.fee} onChange={edit('fee')}/><NumberField label="Parcelas mensais" value={terms.installments} onChange={edit('installments')} min={1} max={24}/><NumberField label="Bônus após 10 partidas (até 1 ano)" value={terms.bonus} onChange={edit('bonus')} max={10000000}/><label className="cw-check"><input type="checkbox" checked={terms.precontract} onChange={e=>edit('precontract')(e.target.checked)}/> Pré-contrato sem taxa (últimos 6 meses)</label><p className="sn-hint">O acordo com o clube e o aceite do atleta são obrigatórios. A taxa total fica reservada mesmo em parcelas.</p><button className="gx-btn" disabled={busy||!own}>Enviar proposta</button></form>}
    </Sheet>}
    {offer && <Sheet title={offer.player_name} kicker={states[offer.status]} onClose={()=>setOffer(null)} tall><p>{offer.response}</p><p>{['precontract','agreed','completed'].includes(offer.status)?'Registro':'Validade'}: {dateLabel(['precontract','agreed','completed'].includes(offer.status)?offer.register_on:offer.expires_on)}</p><p>{clubName(offer.seller_club)} → {clubName(offer.buyer_club)}</p>
      {['seller_review','club_counter'].includes(offer.status) && <div className="sn-stack"><NumberField label="Valor da contraproposta" value={clubFee} onChange={setClubFee}/><div className="cw-actions"><button className="gx-btn" disabled={busy} onClick={()=>respond(offer,'accept')}>Aceitar {money(offer.fee)}</button><button className="gx-btn-ghost" disabled={busy} onClick={()=>respond(offer,'counter',clubFee)}>Contrapropor</button></div></div>}
      {offer.status==='player_counter'&&offer.buyer_club===own&&<form onSubmit={contract} className="sn-stack"><NumberField label="Salário mensal" min={1} value={terms.salary} onChange={edit('salary')} max={10000000}/><NumberField label="Anos de contrato" min={1} max={5} value={terms.years} onChange={edit('years')}/><NumberField label="Luvas" value={terms.signing} onChange={edit('signing')} max={10000000}/><NumberField label="Bônus por partida" value={terms.appearance} onChange={edit('appearance')} max={1000000}/><NumberField label="Bônus por gol" value={terms.goal} onChange={edit('goal')} max={1000000}/><label className="cw-field">Papel no elenco<select aria-label="Papel no elenco" value={terms.role} onChange={e=>edit('role')(e.target.value)}>{Object.entries(roles).map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></label><button className="gx-btn" disabled={busy}>Apresentar contrato</button></form>}
      {['seller_review','club_counter','player_counter','club_pending','player_pending'].includes(offer.status)&&<button className="gx-btn-ghost" disabled={busy} onClick={()=>respond(offer,'reject')}>Encerrar negociação</button>}
      <h3>Histórico</h3>{offer.history.map((h,i)=><div className="cw-ledger" key={i}><span><small>{dateLabel(h.date)} · {states[h.state]||h.state}</small><p>{h.explanation}</p><small>Taxa {money(h.terms?.fee)} · salário {money(h.terms?.monthly_salary)}</small></span></div>)}
    </Sheet>}
    {detail&&<PlayerSheet player={detail} onClose={()=>setDetail(null)} clubName={clubName(detail.club_id)}/>}
  </div>
}
