import { createContext, useContext, useEffect, useRef, useState } from 'react'
import { supabase, isSupabaseConfigured } from '../lib/supabaseClient'
import { onSessionExpired, resetSessionRecovery } from '../lib/sessionRecovery'

const AuthContext = createContext(null)

// Quando o login falha, o Supabase volta para o site com ?error=...&error_code=... na URL.
// Aqui traduzimos isso para uma mensagem clara e limpamos a barra de endereço.
function readOAuthErrorFromUrl() {
  const query = new URLSearchParams(window.location.search)
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''))
  const get = (key) => query.get(key) || hash.get(key)
  const error = get('error')
  if (!error) return null

  const code = get('error_code')
  const description = (get('error_description') || '').replace(/\+/g, ' ')
  console.error('[auth] erro no retorno do login:', { error, code, description })

  window.history.replaceState(null, '', window.location.pathname)
  if (code === 'bad_oauth_state') {
    return 'O login expirou ou foi aberto em outra janela. Toque em entrar com Google e conclua tudo na mesma aba.'
  }
  return description || 'Não foi possível concluir o login. Tente novamente.'
}

export function AuthProvider({ children }) {
  // 'loading' -> checando se já existe uma sessão (ex: voltando do Google)
  // 'signed-out' -> mostra o login
  // 'signed-in' -> usuário autenticado
  const [status, setStatus] = useState(isSupabaseConfigured ? 'loading' : 'signed-out')
  const [user, setUser] = useState(null)
  const [authError, setAuthError] = useState('')
  const signingIn = useRef(false) // evita clique duplo: cada tentativa gera um "state" novo no Supabase

  useEffect(() => {
    if (!isSupabaseConfigured) return

    const urlError = readOAuthErrorFromUrl()
    if (urlError) setAuthError(urlError)

    let alive = true
    let revision = 0
    let expired = false
    const applySession = (session) => {
      if (!alive || (expired && session)) return
      setUser(session?.user ?? null)
      setStatus(session?.user ? 'signed-in' : 'signed-out')
      if (session) resetSessionRecovery()
    }
    const unsubscribeExpired = onSessionExpired(() => {
      expired = true
      revision++
      setUser(null)
      setStatus('signed-out')
      setAuthError('')
      signingIn.current = false
      // Fora de callbacks/locks do SDK. Não revoga sessões de outros aparelhos.
      queueMicrotask(() => { void supabase.auth.signOut({ scope: 'local' }).catch(() => {}) })
    })
    const { data: subscription } = supabase.auth.onAuthStateChange((event, session) => {
      revision++
      if (event === 'SIGNED_IN') expired = false
      if (event === 'SIGNED_OUT') signingIn.current = false
      applySession(session)
    })

    const initialRevision = revision
    supabase.auth.getSession().then(({ data, error }) => {
      if (!alive || revision !== initialRevision) return
      // Erros de autenticação não são exibidos como erros técnicos no login.
      applySession(error ? null : data.session)
      if (window.location.hash.includes('access_token')) {
        window.history.replaceState(null, '', window.location.pathname + window.location.search)
      }
    }).catch(() => {
      if (alive && revision === initialRevision) applySession(null)
    })

    return () => {
      alive = false
      unsubscribeExpired()
      subscription.subscription.unsubscribe()
    }
  }, [])

  async function signInWithGoogle() {
    if (!isSupabaseConfigured) {
      setAuthError('Supabase ainda não foi configurado neste projeto (veja o README).')
      return
    }
    if (signingIn.current) return
    signingIn.current = true
    setAuthError('')
    // Isso navega o navegador para o Google e volta — é assim que o OAuth
    // por redirecionamento funciona, não tem como evitar essa ida e volta.
    // "prompt: select_account" força o Google a sempre mostrar a lista de
    // contas, em vez de reaproveitar em silêncio a última conta logada —
    // sem isso, não dá pra trocar de conta de propósito.
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: {
        redirectTo: window.location.origin,
        queryParams: { prompt: 'select_account' },
      },
    })
    if (error) {
      signingIn.current = false
      setAuthError(error.message)
    }
  }

  async function signOut() {
    if (!isSupabaseConfigured) return
    return await supabase.auth.signOut()
  }

  return (
    <AuthContext.Provider value={{ status, user, authError, signInWithGoogle, signOut }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth deve ser usado dentro de <AuthProvider>')
  return ctx
}
