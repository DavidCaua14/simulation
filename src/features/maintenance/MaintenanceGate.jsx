import { useEffect, useState } from 'react'
import { useAuth } from '../../context/AuthContext'
import AppLoadingScreen from '../../components/layout/AppLoadingScreen'
import { DEFAULT_MESSAGE, isMaintenanceAdmin, parseMaintenance } from './policy'
import './maintenance.css'

// Estado inicial fechado: não monta telas do jogo nem dispara consultas de carreira.
// Falhas de rede preservam a manutenção; nunca liberam acesso por engano.
export default function MaintenanceGate({ children }) {
  const { status, user, signOut } = useAuth()
  const [maintenance, setMaintenance] = useState({ enabled: true, message: DEFAULT_MESSAGE })

  const [signingOut, setSigningOut] = useState(false)
  const [logoutError, setLogoutError] = useState('')

  async function handleSignOut() {
    if (signingOut) return
    setSigningOut(true)
    setLogoutError('')
    try {
      const result = await signOut()
      if (result?.error) throw result.error
    } catch {
      setLogoutError('Não foi possível sair. Tente novamente.')
    } finally {
      setSigningOut(false)
    }
  }

  useEffect(() => {
    let disposed = false
    let pending = false
    let controller
    async function check() {
      if (pending) return
      pending = true
      controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 8000)
      try {
        const response = await fetch(`${import.meta.env.BASE_URL}maintenance.json?t=${Date.now()}`, {
          cache: 'no-store', signal: controller.signal,
        })
        if (!response.ok) throw new Error('Manutenção indisponível')
        const next = parseMaintenance(await response.json())
        if (!disposed) setMaintenance(next)
      } catch {
        if (!disposed) setMaintenance((previous) => ({ ...previous, enabled: true }))
      } finally {
        clearTimeout(timeout)
        pending = false
      }
    }
    const onVisible = () => { if (!document.hidden) check() }
    check()
    const interval = setInterval(check, 10000)
    window.addEventListener('focus', check)
    window.addEventListener('online', check)
    document.addEventListener('visibilitychange', onVisible)
    return () => {
      disposed = true
      controller?.abort()
      clearInterval(interval)
      window.removeEventListener('focus', check)
      window.removeEventListener('online', check)
      document.removeEventListener('visibilitychange', onVisible)
    }
  }, [])

  if (status === 'loading') return <AppLoadingScreen label="Verificando acesso..." />
  if (status !== 'signed-in' || isMaintenanceAdmin(user) || !maintenance.enabled) return children

  return (
    <main className="maintenance-page">
      <section className="maintenance-card" aria-labelledby="maintenance-title">
        <span className="maintenance-badge">SEU JOGADOR · SUA JORNADA</span>
        <span className="maintenance-symbol" aria-hidden="true">⚽</span>
        <h1 id="maintenance-title">Estamos em manutenção</h1>
        <p role="status">{maintenance.message}</p>
        <p className="maintenance-note">Você não precisa sair da sua conta. Esta tela verifica automaticamente quando o jogo estiver disponível novamente.</p>
        <button className="maintenance-logout" type="button" onClick={handleSignOut} disabled={signingOut}>
          {signingOut ? 'Saindo...' : 'Sair'}
        </button>
        {logoutError && <p role="alert">{logoutError}</p>}
      </section>
    </main>
  )
}
