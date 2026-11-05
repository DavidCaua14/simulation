import ClubMoneyInput from './ClubMoneyInput'
import ClubInvestment, { FundingAdvice, RenewalNotice } from '../components/ClubInvestment'
import GameIcon from '../../../components/ui/GameIcon'
import { useCallback, useEffect, useRef, useState } from 'react'
import { CalendarDays, Globe2, Newspaper, Search, SlidersHorizontal } from 'lucide-react'
import { worldRpc, requestId, searchPlayers, negotiations, newsFeed, readNews, financeHistory, money, dateLabel } from '../services/careerWorldApi'
import { fetchPlayer } from '../services/managerApi'
import BasePlayerCard from '../../cards/components/BasePlayerCard'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { CLUB_CATALOG } from '../../club/data/clubCatalog'
import Sheet from '../ui/Sheet'
import PlayerSheet from '../components/PlayerSheet'
import { POS_ORDER } from '../utils/managerUtils'
import { isSessionError } from '../../../lib/sessionRecovery'
import { clubMoneyShort } from '../utils/clubMoney'
import './world.css'

const CLOSED = new Set(['completed', 'rejected', 'expired', 'cancelled', 'failed_funds'])
const AREA_TITLE = { news: 'Notícias', finance: 'Finanças', market: 'Mercado', deals: 'Negociações', contracts: 'Contratos' }
const clubName = id => getClubById(id)?.name || id || 'Livre no mercado'
const countries = [...new Set(Object.values(CLUB_CATALOG).map(c => c.country))].sort()
const roles = { key: 'Peça-chave', starter: 'Titular', rotation: 'Rotação', prospect: 'Promessa' }
const states = { seller_review: 'Sua decisão sobre a venda', club_pending: 'Clube analisando', club_counter: 'Contraproposta do clube', player_pending: 'Atleta analisando', player_counter: 'Negociar contrato do atleta', agreed: 'Aguardando janela', precontract: 'Pré-contrato assinado', completed: 'Concluída', rejected: 'Recusada', expired: 'Expirada', cancelled: 'Cancelada', failed_funds: 'Recursos insuficientes' }
function NumberField({ label, value, onChange, min = 0, max = 100000000, cash = false }) {
  return <label className="cw-field">{label}{cash ? <ClubMoneyInput min={min} max={max} value={value} onChange={onChange} /> : <input type="number" inputMode="numeric" min={min} max={max} step="1" required value={value} onChange={e => onChange(e.target.value)} />}</label>
}
function ClubLine({ id }) { return <span className="cw-club"><ClubCrest clubId={id} size={22} />{clubName(id)}</span> }

export default function WorldPanel({ hub, onRefresh, initialArea = 'news', worldStatus = 'idle', onHome, onTeam }) {
  const [area, updateArea] = useState(initialArea)
  const areaRef = useRef(initialArea)
  const [showFilters, setShowFilters] = useState(false)
  const [dealTab, setDealTab] = useState('open')
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
  useEffect(() => { const timer = setTimeout(() => { setRows([]); reload().catch(e => { if (!isSessionError(e) && mounted.current) setError(e.message) }) }, 250); return () => clearTimeout(timer) }, [reload, hub.world.today, hub.world.news_unread, hub.world.due_matches, hub.coach.club_id])
  async function run(fn) {
    if (busy) return
    setBusy(true); setError(''); setMessage('')
    try { await fn(); await onRefresh?.(); if (mounted.current) await reload() }
    catch (e) { if (!isSessionError(e) && mounted.current) setError(e.message) }
    finally { if (mounted.current) setBusy(false) }
  }
  const invoke = (fn, args) => worldRpc(fn, { ...args, p_request: requestId() })
  async function openPlayer(p) { setPlayer(p); setTerms(t => ({ ...t, fee: Math.round(p.value * 1.2), salary: p.salary_demand || Math.ceil((p.monthly_salary || p.value * .0065) * 1.15), signing: p.minimum_signing_bonus || 0 })) }
  const buy = e => { e.preventDefault(); run(async () => { await invoke('career_transfer_bid', { p_player: player.id, p_fee: +terms.fee, p_installments: +terms.installments, p_bonus: +terms.bonus, p_precontract: terms.precontract }); setPlayer(null); setArea('deals'); setMessage('Proposta enviada. Os clubes respondem com o passar dos dias.') }) }
  const freeContract = e => { e.preventDefault(); run(async () => { await invoke('career_free_agent_offer', { p_player: player.id, p_salary: +terms.salary, p_years: +terms.years, p_signing: +terms.signing, p_role: terms.role, p_appearance: +terms.appearance, p_goal: +terms.goal }); setPlayer(null); setArea('deals'); setMessage('Proposta enviada diretamente ao atleta. Aguarde a resposta nos próximos dias.') }) }
  const contract = e => { e.preventDefault(); run(async () => { await invoke('career_player_offer', { p_id: offer.id, p_salary: +terms.salary, p_years: +terms.years, p_signing: +terms.signing, p_role: terms.role, p_appearance: +terms.appearance, p_goal: +terms.goal }); setOffer(null); setMessage('Contrato enviado ao atleta. Aguarde a resposta nos próximos dias.') }) }
  const respond = (n, action, fee = n.fee) => run(async () => { await invoke('career_transfer_respond', { p_id: n.id, p_action: action, p_fee: +fee }); setOffer(null); setMessage('Resposta registrada.') })
  const contractTerms = { monthly_salary: +terms.salary, contract_years: +terms.years, signing_bonus: +terms.signing, role: terms.role, appearance_bonus: +terms.appearance, goal_bonus: +terms.goal }
  const funded = async () => { setMessage('Aporte concluído. Revise as condições e envie sua proposta quando desejar.'); await onRefresh?.() }
  const edit = field => value => setTerms(t => ({ ...t, [field]: value }))
  if (!w) return null
  return <div className="cw-panel">
    <h2 className="cm-screen-title">Mundo • {AREA_TITLE[area]}</h2>
    <section className="cw-hero">
      <div className="cw-hero-top">
        <span className="cw-hero-icon"><Globe2 size={22} /></span>
        <div className="cw-hero-txt"><small>Brasil e Europa</small><h2>Mundo do futebol</h2></div>
        <span className="cw-date"><CalendarDays size={14} /> {dateLabel(w.today)}</span>
      </div>
      {w.club && <div className="cw-hero-stats">
        <span title={money(w.club.cash)}><small>{w.club.wage_budget != null ? 'Verba' : 'Caixa'}</small><b>{clubMoneyShort(w.club.cash)}</b></span>
        <span title={money(w.club.available)}><small>Disponível</small><b>{clubMoneyShort(w.club.available)}</b></span>
        <span><small>Janela</small><b className={w.club.window_open ? 'cw-positive' : ''}>{w.club.window_open ? 'Aberta' : 'Fechada'}</b></span>
      </div>}
      <p role="status" className="cw-hero-note">{worldStatus === 'retrying' ? 'Aguardando conexão para continuar a simulação automaticamente…' : 'Competições, mercado e contratos avançam juntos a cada rodada, quando você toca em JOGAR.'}</p>
      {onHome && hub.season.status === 'finished' && <button type="button" className="sn-link" onClick={onHome}>Ver a próxima temporada no Início</button>}
      {onHome && !w.needs_sync && hub.next_event?.kind === 'mine' && !(hub.next_event.days_until > 0) && <button type="button" className="sn-link" onClick={onHome}>Ir para a partida no Início</button>}
    </section>
    {error && <p className="cw-alert" role="alert">{error}</p>}{message && <p className="cw-notice" role="status">{message}</p>}
    <div className="sn-seg cw-nav" role="tablist" aria-label="Gestão do clube">
      {[['news','Notícias'],['finance','Finanças'],['market','Mercado'],['deals','Negociações'],['contracts','Contratos']].map(([id,label]) => <button key={id} role="tab" aria-selected={area===id} className={area===id?'is-on':''} onClick={() => setArea(id)}>{label}{id==='news'&&w.news_unread>0&&<em aria-hidden="true">{w.news_unread}</em>}</button>)}
    </div>
    {area === 'news' && <div className="sn-stack">{rows.length===0 && <p className="sn-hint">Nenhuma notícia neste momento.</p>}{rows.map(n => <article key={n.id} className={`cw-card cw-news ${n.read?'':'is-new'}`}>
      <small><Newspaper size={13}/> {dateLabel(n.on_date)}</small><h3>{n.title}</h3>
      {n.metadata?.big_signing && <div className="cw-announcement"><b>NOVA CONTRATAÇÃO</b><button className="cw-card-button" onClick={() => run(async () => setDetail(await fetchPlayer(n.player_id)))}><BasePlayerCard player={n.player || { id:n.player_id,name:n.title.split(' assina')[0],club_id:n.club_id,overall:n.metadata.overall,position:n.metadata.position }} width={128}/></button><span>{clubName(n.metadata.from_club)} → {clubName(n.metadata.to_club)}</span><b>{money(n.metadata.fee)}</b></div>}
      <p>{n.body}</p>{!n.read && <button className="cw-read" disabled={busy} onClick={() => run(() => readNews([n.id]))}>Marcar como lida</button>}
    </article>)}{rows.some(n=>!n.read) && <button type="button" className="gx-btn-ghost cm-wide" disabled={busy} onClick={() => run(() => readNews(rows.filter(n=>!n.read).map(n=>n.id)))}>Marcar todas como lidas</button>}{rows.length>=40 && <button className="gx-btn-ghost" disabled={busy} onClick={async () => { try { const older = await newsFeed(Math.min(...rows.map(n=>n.id))); if (mounted.current) setRows(r=>[...r,...older]) } catch(e) { if (!isSessionError(e)) setError(e.message) } }}>Mais notícias</button>}</div>}
    {area==='finance' && <><section className="cw-card"><h3><GameIcon name="coins" size={17} /> Finanças do clube</h3>{w.club ? <><ClubLine id={own}/><div className="cw-grid">{(w.club.wage_budget != null
          ? [['Verba de transferências',w.club.cash],['Reservada em negociações',w.club.reserved],['Livre para negociar',w.club.available],['Teto salarial mensal',w.club.wage_budget],['Folha mensal atual',w.club.payroll],['Folga no teto',w.club.wage_budget-w.club.payroll],['Bilheteria por jogo em casa',w.club.stadium_income],['Prêmio por vitória na liga',w.club.victory_prize],['Fundo de infraestrutura',w.club.infrastructure]]
          : [['Caixa',w.club.cash],['Dívidas',w.club.debt],['Folha mensal prevista',w.club.payroll],['Reservas e parcelas',w.club.reserved],['Livre para negociar',w.club.available],['Patrimônio investido',w.club.infrastructure],['Receita comercial mensal',w.club.commercial_income],['Bilheteria por jogo em casa',w.club.stadium_income],['Prêmio por vitória na liga',w.club.victory_prize]]).map(([label,v])=><span key={label}><small>{label}</small><b>{money(v)}</b></span>)}</div>{w.club.wage_budget != null ? <><p>{w.club.window_open?'Janela aberta':`Janela fechada · próxima: ${dateLabel(w.club.next_window)}`}</p><p className="sn-hint">A diretoria define a verba e o teto salarial no início de cada temporada. Bilheteria, prêmios e vendas aumentam a verba; taxas, luvas, bônus e obras saem dela. Salários não saem da verba: eles só precisam caber no teto.</p></> : <><p>Risco financeiro: {Math.round(w.club.financial_risk)}% · {w.club.window_open?'Janela aberta':`Janela fechada · próxima: ${dateLabel(w.club.next_window)}`}</p><p className="sn-hint">O orçamento livre desconta compromissos, dívidas e dois meses da folha prevista, com estimativa dos bônus. As finanças do clube são em reais.</p></>}<ClubInvestment coins={hub.career.coins} board={w.investment?.board} disabled={busy} onInvested={async () => { setMessage('Investimento transferido ao clube.'); await onRefresh?.(); await reload() }} /></>:<p>Assuma um clube para administrar seu orçamento.</p>}</section>{w.club?.wage_budget > 0 && <section className="cw-card cw-wageuse"><h3>Uso do orçamento de salários <b>{Math.round(w.club.payroll / w.club.wage_budget * 100)}%</b></h3><i><em className={w.club.payroll > w.club.wage_budget ? 'is-over' : ''} style={{ width: `${Math.min(100, w.club.payroll / w.club.wage_budget * 100)}%` }}/></i><small>Folha: {money(w.club.payroll)} / Teto: {money(w.club.wage_budget)}</small></section>}<section className="cw-card"><h3>Últimas transações</h3>{rows.length===0&&<p className="sn-hint">Nenhuma movimentação registrada.</p>}{rows.length>0&&<table className="sn-table cw-ltable"><thead><tr><th>Data</th><th className="left">Descrição</th><th>Valor</th></tr></thead><tbody>{rows.map(r=><tr key={r.id}><td className="cw-ldate">{dateLabel(r.on_date)}</td><td className="left"><b>{r.description}</b><small>Saldo {clubMoneyShort(r.cash_after)}</small></td><td className={r.amount<0?'cw-negative':'cw-positive'}>{r.amount>0?'+':''}{clubMoneyShort(r.amount)}</td></tr>)}</tbody></table>}</section></>}
    {(area==='market'||area==='contracts') && <>
      <form className="cw-card cw-filters" onSubmit={e=>{e.preventDefault();reload().catch(e=>setError(e.message))}}>
        <div className="cw-searchrow"><label className="cw-field cw-search"><Search size={16} aria-hidden="true"/><input type="search" placeholder="Buscar jogador" aria-label="Buscar atleta" maxLength={60} value={filters.p_query} onChange={e=>setFilters(f=>({...f,p_query:e.target.value,p_page:0}))}/></label><button type="button" className="gx-btn-ghost" aria-expanded={showFilters} onClick={()=>setShowFilters(v=>!v)}><SlidersHorizontal size={15}/> Filtros</button></div>
        {showFilters && <><div className="cw-two"><label className="cw-field">Posição<select aria-label="Posição" value={filters.p_position} onChange={e=>setFilters(f=>({...f,p_position:e.target.value,p_page:0}))}><option value="">Todas</option>{POS_ORDER.map(p=><option key={p}>{p}</option>)}</select></label><label className="cw-field">Região<select aria-label="Região" value={filters.p_region} onChange={e=>setFilters(f=>({...f,p_region:e.target.value,p_page:0}))}><option value="">Mundo</option><option value="BRA">América do Sul</option><option value="ENG">Europa</option><option value="free">Sem contrato</option></select></label></div>
        <label className="cw-field">País do clube<select aria-label="País do clube" value={filters.p_country} onChange={e=>setFilters(f=>({...f,p_country:e.target.value,p_page:0}))}><option value="">Todos os países</option>{countries.map(c=><option key={c}>{c}</option>)}</select></label>
        <NumberField cash label="Valor máximo (vazio: todos) (R$)" value={filters.p_max_value??''} onChange={v=>setFilters(f=>({...f,p_max_value:v===''?null:+v,p_page:0}))}/></>}
        <small>{area==='contracts'?'Seu elenco e seus vínculos':'Mercado esportivo internacional'} · {w.club?.window_open?'Janela aberta':'Janela fechada; apenas renovações do seu elenco'}</small>
      </form>
      {w.club && area==='market' && <div className="cw-budget"><span><small>Orçamento de transferências</small><b>{clubMoneyShort(w.club.available)}</b></span><span><small>{w.club.wage_budget != null ? 'Teto salarial mensal' : 'Folha mensal'}</small><b>{clubMoneyShort(w.club.wage_budget ?? w.club.payroll)}</b></span></div>}
      {rows.length>0 && <table className="sn-table cw-mtable"><thead><tr><th className="left">Jogador</th><th>POS</th><th>GER</th><th>{area==='contracts'?'Salário':'Valor'}</th></tr></thead><tbody>{rows.map(p=><tr key={p.id} className="is-link" onClick={()=>openPlayer(p)}><td className="left"><span className="cw-mrow"><ClubCrest clubId={p.club_id} size={22}/><span><b>{p.short_name||p.name}</b><small>{area==='contracts'?`Moral ${Math.round(p.morale)} · ${roles[p.promised_role]||''}${p.transfer_requested?' · Pede para sair':''}`:`${clubName(p.club_id)}${p.age?` · ${p.age} anos`:''}`}</small></span></span></td><td><em className="cw-pos">{p.position}</em></td><td><b className="cw-ovr">{p.overall}</b></td><td className="cw-val">{clubMoneyShort(area==='contracts'?p.monthly_salary:p.value)}</td></tr>)}</tbody></table>}
      {rows.length===0&&<p className="sn-hint">Nenhum atleta encontrado.</p>}
      <div className="cw-actions"><button className="gx-btn-ghost" disabled={filters.p_page===0} onClick={()=>setFilters(f=>({...f,p_page:f.p_page-1}))}>Anterior</button><span>Página {filters.p_page+1}</span><button className="gx-btn-ghost" disabled={rows.length<30} onClick={()=>setFilters(f=>({...f,p_page:f.p_page+1}))}>Próxima</button></div>
    </>}
    {area==='deals' && <div className="sn-stack">{rows.length>0 && <div className="sn-seg cw-dealtabs">{[['open','Em andamento'],['done','Concluídas']].map(([id,label])=><button key={id} type="button" className={dealTab===id?'is-on':''} onClick={()=>setDealTab(id)}>{label} ({rows.filter(n=>CLOSED.has(n.status)===(id==='done')).length})</button>)}</div>}{rows.length===0&&<p className="sn-hint">Nenhuma negociação. Busque atletas no Mercado ou aguarde propostas de outros clubes.</p>}{rows.filter(n=>CLOSED.has(n.status)===(dealTab==='done')).map(n=><article key={n.id} className={`cw-card cw-deal s-${n.status}`}><div className="cw-deal-head"><ClubCrest clubId={n.seller_club===own?n.buyer_club:n.seller_club} size={34}/><span><h3>{n.player_name}</h3><small>{clubName(n.seller_club)} → {clubName(n.buyer_club)}</small></span><span className="cw-deal-fee"><b>{clubMoneyShort(n.fee)}</b><small>{dateLabel(['precontract','agreed','completed'].includes(n.status)?n.register_on:n.expires_on)}</small></span></div><em className="cw-deal-state">{states[n.status]}</em><small>{n.installments} parcela(s) · {['precontract','agreed','completed'].includes(n.status)?'Registro':'Prazo'} {dateLabel(['precontract','agreed','completed'].includes(n.status)?n.register_on:n.expires_on)}</small>{n.response && <p>{n.response}</p>}<div className="cw-actions"><button className="gx-btn-ghost" onClick={()=>{setOffer(n);setClubFee(n.fee);setTerms(t=>({...t,salary:Math.max(n.salary_demand||0,n.monthly_salary||Math.ceil(n.valuation*.0075)),years:n.contract_years||3,signing:Math.max(n.minimum_signing_bonus||0,n.signing_bonus||0),role:n.role||'rotation',appearance:n.appearance_bonus||0,goal:n.goal_bonus||0}))}}>Ver negociação</button></div></article>)}</div>}
    {player && <Sheet title={player.short_name||player.name} kicker="Atleta e contrato" onClose={()=>setPlayer(null)} tall>
      <div className="cw-announcement"><BasePlayerCard player={player} width={132}/><ClubLine id={player.club_id}/></div>
      <div className="cw-grid"><span><small>Idade {player.age_estimated?'estimada':''}</small><b>{player.age} anos</b></span><span><small>Potencial estimado</small><b>{player.potential}</b></span><span><small>Valor</small><b>{money(player.value)}</b></span><span><small>Salário mensal</small><b>{money(player.monthly_salary)}</b></span><span><small>Contrato até</small><b>{dateLabel(player.expires_on)}</b></span><span><small>Minutos nas temporadas atuais</small><b>{player.minutes}</b></span><span><small>Satisfação</small><b>{Math.round(player.morale)}%</b></span><span><small>Promessa</small><b>{roles[player.promised_role]}</b></span></div>
      {player.club_id!==own && <p className="sn-hint">Salário mensal pretendido: {money(player.salary_demand || player.monthly_salary)}.{player.minimum_signing_bonus>0 && ` Luvas mínimas: ${money(player.minimum_signing_bonus)}.`}</p>}
      {player.club_id!==own && !w.club?.window_open && <p className="cw-alert" role="status">Janela de transferências fechada. Novas contratações, inclusive atletas livres e pré-contratos, aguardam a próxima janela. Renovações do seu elenco continuam disponíveis.</p>}
      {player.club_id!==own && player.project_reason && <p className="cw-alert" role="status">{player.project_reason}</p>}
      <button className="gx-btn-ghost" disabled={busy} onClick={()=>run(async()=>setDetail(await fetchPlayer(player.id)))}>Atributos e estatísticas</button>
      {player.club_id===own && <RenewalNotice expiresOn={player.expires_on} today={w.today} demand={player.salary_demand} projectReason={player.project_reason} />}
      {player.club_id===own ? <div className="sn-stack"><h3>Gestão do contrato</h3><p>{player.transfer_requested?'O atleta quer sair. Procure melhorar seu papel e os pagamentos.':'Cumpra o papel prometido com oportunidades em campo.'}</p><label className="cw-field">Papel prometido<select aria-label="Papel prometido" value={player.promised_role} onChange={e=>{const role=e.target.value;run(async()=>{await worldRpc('career_player_role',{p_player:player.id,p_role:role});setPlayer(p=>({...p,promised_role:role}))})}}>{Object.entries(roles).map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></label><button className="gx-btn" disabled={busy} onClick={()=>run(async()=>{await invoke('career_contract_renew',{p_player:player.id});setPlayer(null);setArea('deals')})}>Negociar renovação</button></div> : player.club_id == null ? <form onSubmit={freeContract} className="sn-stack">
        <h3>Negociar com o atleta livre</h3>
        <p className="sn-hint">Sem taxa de transferência. O jogador decide conforme salário, luvas e projeto esportivo.</p>
        <NumberField cash label="Salário mensal (R$)" min={1} max={10000000} value={terms.salary} onChange={edit('salary')} />
        <NumberField label="Anos de contrato" min={1} max={5} value={terms.years} onChange={edit('years')} />
        <NumberField cash label="Luvas (R$)" max={10000000} value={terms.signing} onChange={edit('signing')} />
        <NumberField cash label="Bônus por partida (R$)" max={1000000} value={terms.appearance} onChange={edit('appearance')} />
        <NumberField cash label="Bônus por gol (R$)" max={1000000} value={terms.goal} onChange={edit('goal')} />
        <label className="cw-field">Papel no elenco<select aria-label="Papel no elenco" value={terms.role} onChange={e=>edit('role')(e.target.value)}>{Object.entries(roles).map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></label>
        <FundingAdvice playerId={player.id} terms={{ ...contractTerms, fee: 0 }} disabled={busy} onInvested={funded} />
        <button className="gx-btn" disabled={busy||!own||!w.club?.window_open||Boolean(player.project_reason)}>Apresentar proposta ao atleta</button>
      </form> : <form onSubmit={buy} className="sn-stack"><h3>Proposta ao clube</h3><NumberField cash label="Taxa fixa (R$)" value={terms.fee} onChange={edit('fee')}/><NumberField label="Parcelas mensais" value={terms.installments} onChange={edit('installments')} min={1} max={24}/><NumberField cash label="Bônus após 10 partidas (até 1 ano) (R$)" value={terms.bonus} onChange={edit('bonus')} max={10000000}/><label className="cw-check"><input type="checkbox" checked={terms.precontract} onChange={e=>edit('precontract')(e.target.checked)}/> Pré-contrato sem taxa (últimos 6 meses)</label><p className="sn-hint">O acordo com o clube e o aceite do atleta são obrigatórios. Taxas, luvas e seis meses do acréscimo da folha precisam caber no orçamento. Propostas não contam como contratações: o limite de seis vale para registros concluídos na janela.</p><FundingAdvice playerId={player.id} terms={{ fee: +terms.fee, performance_bonus: +terms.bonus, precontract: terms.precontract }} disabled={busy} onInvested={funded} /><button className="gx-btn" disabled={busy||!own||!w.club?.window_open||Boolean(player.project_reason)}>Enviar proposta</button></form>}
    </Sheet>}
    {offer && <Sheet title={offer.player_name} kicker={states[offer.status]} onClose={()=>setOffer(null)} tall><p>{offer.response}</p><p>{['precontract','agreed','completed'].includes(offer.status)?'Registro':'Validade'}: {dateLabel(['precontract','agreed','completed'].includes(offer.status)?offer.register_on:offer.expires_on)}</p><p>{clubName(offer.seller_club)} → {clubName(offer.buyer_club)}</p>
      {offer.arrival_status==='registered' && <div className="cw-notice"><p>Contrato registrado. O atleta já pertence ao elenco do seu clube.</p>{onTeam && <button type="button" className="gx-btn-ghost" onClick={() => onTeam(offer.player_id)}>Ver atleta no Time</button>}</div>}
      {['waiting_window','waiting_registration'].includes(offer.arrival_status) && <p className="cw-notice">O acordo está aprovado, mas o registro ainda aguarda {offer.arrival_status==='waiting_window'?'a abertura da janela':'a data de início do contrato'}: {dateLabel(offer.register_on)}. O atleta aparecerá no Time após o registro. O acordo continua salvo.</p>}
      {offer.arrival_status==='player_decision' && <p className="sn-hint">A contratação ainda depende do contrato e do aceite final do atleta. Uma proposta enviada não adiciona o jogador ao elenco.</p>}
      {offer.arrival_status==='club_agreement' && <p className="sn-hint">O acerto com o clube é uma etapa da negociação. Ainda será necessário negociar o contrato do atleta.</p>}
      {offer.arrival_status==='left' && <p className="sn-hint">Esta contratação consta no histórico, mas o atleta já não possui vínculo vigente com o clube.</p>}
      {['seller_review','club_counter'].includes(offer.status) && <div className="sn-stack"><NumberField cash label="Valor da contraproposta (R$)" value={clubFee} onChange={setClubFee}/><>{offer.buyer_club===own && <FundingAdvice playerId={offer.player_id} negotiationId={offer.id} terms={{ fee: +clubFee, monthly_salary: Math.max(offer.salary_demand || 1, offer.monthly_salary || 0) }} disabled={busy} onInvested={funded} />}</><div className="cw-actions"><button className="gx-btn" disabled={busy||(offer.buyer_club===own&&!w.club?.window_open)} onClick={()=>respond(offer,'accept')}>Aceitar {money(offer.fee)}</button><button className="gx-btn-ghost" disabled={busy||(offer.buyer_club===own&&!w.club?.window_open)} onClick={()=>respond(offer,'counter',clubFee)}>Contrapropor</button></div></div>}
      {offer.status==='player_counter'&&offer.buyer_club===own&&<form onSubmit={contract} className="sn-stack"><NumberField cash label="Salário mensal (R$)" min={1} value={terms.salary} onChange={edit('salary')} max={10000000}/><NumberField label="Anos de contrato" min={1} max={5} value={terms.years} onChange={edit('years')}/><NumberField cash label="Luvas (R$)" value={terms.signing} onChange={edit('signing')} max={10000000}/><NumberField cash label="Bônus por partida (R$)" value={terms.appearance} onChange={edit('appearance')} max={1000000}/><NumberField cash label="Bônus por gol (R$)" value={terms.goal} onChange={edit('goal')} max={1000000}/><label className="cw-field">Papel no elenco<select aria-label="Papel no elenco" value={terms.role} onChange={e=>edit('role')(e.target.value)}>{Object.entries(roles).map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></label><FundingAdvice playerId={offer.player_id} negotiationId={offer.id} terms={contractTerms} disabled={busy} onInvested={funded} /><button className="gx-btn" disabled={busy||(offer.initiator!=='renewal'&&!w.club?.window_open)}>Apresentar contrato</button></form>}
      {['seller_review','club_counter','player_counter','club_pending','player_pending'].includes(offer.status)&&<button className="gx-btn-ghost" disabled={busy} onClick={()=>respond(offer,'reject')}>Encerrar negociação</button>}
      <h3>Histórico</h3>{offer.history.map((h,i)=><div className="cw-ledger" key={i}><span><small>{dateLabel(h.date)} · {states[h.state]||h.state}</small><p>{h.explanation}</p><small>Taxa {money(h.terms?.fee)} · salário {money(h.terms?.monthly_salary)}</small></span></div>)}
    </Sheet>}
    {detail&&<PlayerSheet player={detail} onClose={()=>setDetail(null)} clubName={clubName(detail.club_id)}/>}
  </div>
}
