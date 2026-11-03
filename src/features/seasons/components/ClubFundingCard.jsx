import { useState } from 'react'
import { HandCoins, X } from 'lucide-react'
import { dateLabel, money, worldRpc } from '../services/careerWorldApi'
import { personalCoins } from '../utils/clubMoney'
import { isSessionError } from '../../../lib/sessionRecovery'
import './clubInvestment.css'

export default function ClubFundingCard({ signal, actions, disabled }) {
  const [dismissed, setDismissed] = useState(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  if (!signal || dismissed === signal.key) return null
  async function dismiss() {
    if (busy) return
    setBusy(true); setError('')
    try { await worldRpc('career_funding_dismiss', { p_key: signal.key }); setDismissed(signal.key) }
    catch(e) { if (!isSessionError(e)) setError(e.message) }
    finally { setBusy(false) }
  }
  const renewal = signal.kind === 'renewal'
  const title = renewal ? 'Planeje a renovação do seu elenco' : signal.kind === 'negotiation' ? 'Seu reforço precisa de planejamento' : 'Revise o planejamento do clube'
  return <section className="ci-home" aria-label="Planejamento do clube">
    <button type="button" className="ci-dismiss" aria-label="Dispensar aviso de planejamento" disabled={busy || disabled} onClick={dismiss}><X size={18} /></button>
    <h2><HandCoins size={19} /> {title}</h2>
    {renewal ? <>
      <p><b>{signal.player_name}</b> tem contrato até {dateLabel(signal.expires_on)}. Pretensão mensal para renovar: <b>{money(signal.salary_demand)}</b>.</p>
      <p>{signal.project_reason || 'Conheça as exigências do atleta. Sem renovação aprovada, ele sai ao fim do vínculo.'}</p>
    </> : signal.kind === 'negotiation' ? <>
      <p>A negociação com <b>{signal.player_name}</b> precisa de mais {money(signal.gap)} para sustentar as condições atuais.</p>
      <p>Um aporte estimado de {personalCoins(signal.coins_needed)} moedas pode cobrir a diferença. Você também pode revisar a proposta.</p>
    </> : <>
      <p>A previsão conservadora dos próximos três meses apresenta uma diferença de {money(signal.gap)}.</p>
      <p>O cálculo considera receitas comerciais, folha, operação do clube, dívidas e parcelas. Bilheteria, premiações e vendas futuras podem melhorar esse resultado.</p>
    </>}
    <div className="ci-actions">
      <button type="button" className="gx-btn-ghost" disabled={disabled} onClick={() => actions.goTab('world', signal.action)}>{renewal ? 'Ver contratos' : signal.kind === 'negotiation' ? 'Ver negociações' : 'Ver finanças'}</button>
      {signal.kind === 'negotiation' && <button type="button" className="sn-link" disabled={disabled} onClick={() => actions.goTab('world','finance')}>Revisar caixa</button>}
    </div>
    {error && <p role="alert">{error}</p>}
  </section>
}
