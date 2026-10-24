import { AlertTriangle } from 'lucide-react'

// Estados padrão do modo: carregando (esqueleto), erro e vazio.
export function LoadingState() {
  return (
    <div className="st-loading" aria-busy="true" aria-label="Carregando sua temporada">
      <span className="st-sk hero" />
      <span className="st-sk line" />
      <span className="st-sk row" />
      <span className="st-sk row" />
      <span className="st-sk row" />
    </div>
  )
}

export function ErrorState({ message, onRetry }) {
  return (
    <div className="st-box is-error" role="alert">
      <AlertTriangle size={26} />
      <b>Não foi possível carregar</b>
      <p>{message}</p>
      {onRetry && (
        <button type="button" className="gx-btn-ghost" onClick={onRetry}>
          Tentar de novo
        </button>
      )}
    </div>
  )
}

export function EmptyState({ icon: Icon, title, text, children }) {
  return (
    <div className="st-box">
      {Icon && <Icon size={26} />}
      <b>{title}</b>
      {text && <p>{text}</p>}
      {children}
    </div>
  )
}
