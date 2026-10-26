import { useEffect, useRef } from 'react'
import { Check, CircleAlert, Info, X } from 'lucide-react'
import { tierOf } from '../../features/cards/data/tiers'

// ─────────────────────────────────────────────────────────────────────────────
// Peças visuais compartilhadas (estados vazios, carregamento, avisos, raridade e confirmação).
// Mesmo desenho em todas as telas — o estilo está em styles/game-ui.css (.gx-empty, .gx-skel, .gx-notice…).
// ─────────────────────────────────────────────────────────────────────────────

// Estado vazio: ícone num escudo, título, explicação curta e (opcional) uma ação.
export function EmptyState({ icon: Icon, title, text, action, onAction, compact = false }) {
  return (
    <div className={`gx-empty ${compact ? 'is-compact' : ''}`}>
      {Icon && <span className="gx-empty-shield" aria-hidden="true"><Icon size={compact ? 20 : 26} /></span>}
      {title && <strong>{title}</strong>}
      {text && <p>{text}</p>}
      {action && onAction && <button type="button" className="gx-btn-ghost gx-empty-action" onClick={onAction}>{action}</button>}
    </div>
  )
}

// Carregamento: blocos com brilho passando (no formato do conteúdo que vai aparecer).
export function Skeleton({ rows = 3, variant = 'row' }) {
  if (variant === 'grid') {
    return (
      <div className="gx-skel-grid" aria-busy="true" aria-label="Carregando">
        {Array.from({ length: rows }, (_, i) => <span key={i} className="gx-skel gx-skel-card" />)}
      </div>
    )
  }
  return (
    <div className="gx-skel-list" aria-busy="true" aria-label="Carregando">
      {Array.from({ length: rows }, (_, i) => (
        <span key={i} className={`gx-skel gx-skel-${variant}`} style={{ animationDelay: `${i * 0.08}s` }} />
      ))}
    </div>
  )
}

// Aviso de sucesso/erro/informação, com ícone. `onClose` mostra o X.
export function Notice({ kind = 'info', children, onClose }) {
  const Icon = kind === 'ok' ? Check : kind === 'error' ? CircleAlert : Info
  return (
    <div className={`gx-notice is-${kind}`} role={kind === 'error' ? 'alert' : 'status'}>
      <Icon size={15} />
      <div className="gx-notice-body">{children}</div>
      {onClose && <button type="button" className="gx-notice-x" onClick={onClose} aria-label="Fechar aviso"><X size={14} /></button>}
    </div>
  )
}

// Selo de raridade das cartas (Básica, Destaque, Lenda, Épica) com a cor oficial do tier.
export function RarityBadge({ tier, small = false }) {
  const t = tierOf(tier)
  return (
    <span className={`gx-rarity r-${t.id} ${small ? 'is-small' : ''}`} style={{ '--r': t.color }}>
      <i aria-hidden="true" />{t.label}
    </span>
  )
}

// Confirmação de operação importante (desfazer amizade, cancelar anúncio, cancelar evento…).
export function ConfirmSheet({ title, text, confirmLabel = 'Confirmar', cancelLabel = 'Voltar', danger = false, busy = false, onConfirm, onCancel, children }) {
  const ref = useRef(null)
  useEffect(() => {
    ref.current?.focus()
    const onKey = (e) => e.key === 'Escape' && !busy && onCancel?.()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [busy, onCancel])
  return (
    <div className="cx-sheet-wrap gx-confirm-wrap" role="dialog" aria-modal="true" aria-label={title} onClick={busy ? undefined : onCancel}>
      <div className="cx-sheet gx-confirm" onClick={(e) => e.stopPropagation()}>
        <h3>{title}</h3>
        {text && <p className="gx-confirm-text">{text}</p>}
        {children}
        <div className="gx-confirm-actions">
          <button type="button" className="gx-btn-ghost" onClick={onCancel} disabled={busy}>{cancelLabel}</button>
          <button type="button" ref={ref} className={`gx-btn ${danger ? 'is-danger' : ''}`} onClick={onConfirm} disabled={busy}>
            {busy ? '…' : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
