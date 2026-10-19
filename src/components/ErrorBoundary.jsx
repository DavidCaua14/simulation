import { Component } from 'react'
import './ErrorBoundary.css'

// Se uma tela quebrar, mostra uma mensagem em vez de deixar a tela toda preta.
export default class ErrorBoundary extends Component {
  state = { error: null }

  static getDerivedStateFromError(error) {
    return { error }
  }

  componentDidCatch(error, info) {
    console.error('[app] erro de renderização:', error, info?.componentStack)
  }

  render() {
    const { error } = this.state
    if (!error) return this.props.children

    return (
      <div className="app-error" role="alert">
        <h2>Algo deu errado</h2>
        <p>A tela não pôde ser carregada. Seus dados estão seguros.</p>
        <code>{String(error?.message || error)}</code>
        <button type="button" className="btn-primary" onClick={() => window.location.reload()}>
          Recarregar
        </button>
      </div>
    )
  }
}
