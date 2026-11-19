// Narração da disputa de pênaltis lance a lance (fase 36). Usada no painel e no relato da partida.
// Detalhe de um lance da disputa (fase 36): "resultado|canto da batida|pulo do goleiro" — ex.: "fora|esquerdo|direito".
export function penDetail(e) {
  const [what, aim, dive] = String(e?.detail || '').split('|')
  return { what, aim, dive }
}
const canto = (d) => (d === 'meio' ? 'no meio do gol' : `no canto ${d}`)

// Narração de cada lance da disputa (também usada no relato da partida).
export function shootoutText(e) {
  const p = e.player_name || 'Jogador'
  const gk = e.player2_name || 'o goleiro'
  const { what, aim, dive } = penDetail(e)
  switch (e.kind) {
    case 'so_start': return 'Empate! A decisão vai para os pênaltis.'
    case 'so_ready': return `${p} ajeita a bola para a ${String(e.detail || '').split('|')[0] || ''}ª cobrança. ${gk} no gol.`
    case 'so_goal': return aim ? `GOL! ${p} bate ${canto(aim)}${dive && dive !== aim ? `, ${gk} foi para o ${dive === 'meio' ? 'meio' : `lado ${dive}`}` : ', sem chance para o goleiro'}.` : `GOL! ${p} converte.`
    case 'so_save': return `DEFENDEU! ${gk} pula ${canto(aim)} e pega a cobrança de ${p}.`
    case 'so_miss': return what === 'trave' ? `NA TRAVE! ${p} bate ${canto(aim)} e a bola explode no poste.`
      : what === 'por cima' ? `POR CIMA! ${p} isola a cobrança.` : `PARA FORA! ${p} tira demais ${canto(aim)} e erra o gol.`
    default: return ''
  }
}

