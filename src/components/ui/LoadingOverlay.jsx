import './LoadingOverlay.css'

export default function LoadingOverlay({ show, label = 'Carregando...' }) {
  if (!show) return null
  return (
    <div className="loading-overlay" role="status" aria-live="polite">
      <div className="loading-spinner" />
      <span className="loading-label">{label}</span>
    </div>
  )
}
