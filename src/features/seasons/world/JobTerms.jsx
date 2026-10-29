import { useState } from 'react'
import { worldRpc, requestId, money, dateLabel } from '../services/careerWorldApi'
import { isSessionError } from '../../../lib/sessionRecovery'
export default function JobTerms({ offer, coach, employed, onRefresh }) {
  const [editing, setEditing] = useState(false)
  const [salary, setSalary] = useState(offer?.salary || coach?.monthly_salary || 100)
  const [years, setYears] = useState(offer?.contract_years || 2)
  const [budget, setBudget] = useState(offer?.budget_guarantee || 0)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function save(e) {
    e.preventDefault();setBusy(true);setError('')
    try {
      await worldRpc(offer ? 'career_job_negotiate' : 'career_coach_renew', offer ? { p_offer:offer.id,p_salary:+salary,p_years:+years,p_budget:+budget,p_request:requestId() } : { p_salary:coach.monthly_salary,p_years:+years,p_request:requestId() })
      await onRefresh?.();setEditing(false)
    } catch(e) { if(!isSessionError(e)) setError(e.message) }
    finally { setBusy(false) }
  }
  return <div className="sn-sec">
    <div className="cw-grid"><span><small>Salário mensal</small><b>{money(offer?.salary||coach?.monthly_salary)}</b></span>{offer?<span><small>Orçamento prometido</small><b>{money(offer.budget_guarantee)}</b></span>:<span><small>Credibilidade</small><b>{Math.round(coach?.credibility||0)}/100</b></span>}<span><small>{offer?'Duração':'Contrato até'}</small><b>{offer?`${offer.contract_years} anos`:dateLabel(coach?.contract_until)}</b></span>{!offer && coach?.promised_budget > 0 && <span><small>Orçamento negociado na assinatura</small><b>{money(coach.promised_budget)}</b></span>}</div>
    {((offer && offer.negotiation_round < 2) || employed) && <button className="sn-link" onClick={()=>setEditing(x=>!x)}>{offer?'Negociar condições':'Renovar contrato do treinador'}</button>}
    {error&&<p role="alert" className="cw-alert">{error}</p>}
    {editing && <form onSubmit={save} className="sn-stack">
      {offer&&<label className="cw-field">Salário mensal<input type="number" inputMode="numeric" min="1" max="100000" required value={salary} onChange={e=>setSalary(e.target.value)}/></label>}
      <label className="cw-field">{offer?'Anos de contrato':'Anos adicionais'}<input type="number" inputMode="numeric" min="1" max={offer?5:3} required value={years} onChange={e=>setYears(e.target.value)}/></label>
      {offer&&<label className="cw-field">Orçamento para contratações<input type="number" inputMode="numeric" min="0" max="100000000" required value={budget} onChange={e=>setBudget(e.target.value)}/></label>}
      {!offer&&<p className="sn-hint">A renovação antecipada mantém o salário atual e depende da confiança da diretoria e das finanças.</p>}
      <button className="gx-btn" disabled={busy}>{busy?'Enviando…':'Apresentar condições'}</button>
    </form>}
  </div>
}
