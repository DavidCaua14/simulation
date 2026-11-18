import { useEffect, useState } from 'react'
import { Info } from 'lucide-react'
import { fetchPlayerSheet } from '../services/onlineApi'
import ConditionArrow from './ConditionArrow'
import { ARROWS, FORM_LABEL } from '../conditions'
import './player-details.css'

const GROUPS = [['atk', 'Ataque'], ['tec', 'Técnica'], ['pas', 'Passe'], ['fis', 'Físico'], ['def', 'Defesa'], ['gk', 'Goleiro']]
// cor do número como no eFootball: verde-água alto, verde bom, amarelo médio, laranja e vermelho baixos
const tone = (v) => (v >= 90 ? 't-top' : v >= 80 ? 't-good' : v >= 70 ? 't-ok' : v >= 60 ? 't-mid' : 't-low')

// DETALHES DO JOGADOR (modo online): condição, estilos de jogo e a ficha completa (um valor por atributo).
export default function PlayerDetails({ playerId }) {
  const [sheet, setSheet] = useState(null)
  const [error, setError] = useState('')
  const [tab, setTab] = useState('styles')
  const [open, setOpen] = useState(null) // código do estilo com a explicação aberta
  useEffect(() => {
    let alive = true
    fetchPlayerSheet(playerId).then((s) => alive && setSheet(s)).catch((e) => alive && setError(e.message))
    return () => { alive = false }
  }, [playerId])
  if (error) return <p className="pd-err">{error}</p>
  if (!sheet) return <p className="pd-load">Carregando a ficha…</p>
  const a = ARROWS[sheet.arrow] || ARROWS[3]
  const styleRow = (s, kind) => s && (
    <li key={`${kind}-${s.code}`}>
      <button type="button" onClick={() => setOpen(open === s.code ? null : s.code)} aria-expanded={open === s.code}>
        <span><b>{s.name}</b></span><Info size={15} />
      </button>
      {open === s.code && <p>{s.descr}</p>}
    </li>
  )
  return (
    <div className="pd">
      <div className="pd-cond">
        <ConditionArrow arrow={sheet.arrow} size={30} />
        <span><b>Condição {a.label.toLowerCase()}</b><small>{a.effect} na próxima partida · muda ao fim de cada jogo</small></span>
        <em title={FORM_LABEL[sheet.form]}>{sheet.form}</em>
      </div>
      <p className="pd-form">Regularidade {sheet.form}: {FORM_LABEL[sheet.form]}</p>
      <nav className="pd-tabs" role="tablist">
        <button type="button" role="tab" aria-selected={tab === 'styles'} className={tab === 'styles' ? 'is-on' : ''} onClick={() => setTab('styles')}>Estilo de jogo</button>
        <button type="button" role="tab" aria-selected={tab === 'attrs'} className={tab === 'attrs' ? 'is-on' : ''} onClick={() => setTab('attrs')}>Qualidade</button>
      </nav>
      {tab === 'styles' ? (
        <div className="pd-styles">
          <h5>Com a bola</h5>
          <ul>{styleRow(sheet.styles.off, 'off') || <li className="pd-none">Sem estilo ofensivo</li>}</ul>
          <h5>Sem a bola</h5>
          <ul>{styleRow(sheet.styles.def, 'def') || <li className="pd-none">Sem estilo defensivo</li>}</ul>
          {sheet.traits?.length > 0 && (
            <>
              <h5>Especialidades</h5>
              <ul>{sheet.traits.map((t) => styleRow(t, 'tr'))}</ul>
            </>
          )}
          <h5>Estilos de jogo da IA</h5>
          <ul>{sheet.styles.ai.length ? sheet.styles.ai.map((s) => styleRow(s, 'ai')) : <li className="pd-none">Nenhum</li>}</ul>
        </div>
      ) : (
        <div className="pd-attrs">
          <div className="pd-row pd-overall">
            <span>Pontuação geral</span><b>{sheet.overall}</b>
          </div>
          {GROUPS.map(([g, label]) => {
            const rows = sheet.attrs.filter((x) => x.group === g)
            if (!rows.length) return null
            return (
              <section key={g}>
                <h5>{label}</h5>
                {rows.map((x) => (
                  <div key={x.k} className="pd-row">
                    <span>{x.label}</span>
                    <b className={tone(x.value)}>{x.value}</b>
                  </div>
                ))}
              </section>
            )
          })}
          <p className="pd-note">Valores de hoje, com o treino já feito. A condição (seta) muda o rendimento só na partida.</p>
        </div>
      )}
    </div>
  )
}
