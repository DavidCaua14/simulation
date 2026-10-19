import { createContext, useContext, useEffect, useRef, useState } from 'react'
import { supabase, isSupabaseConfigured } from '../lib/supabaseClient'

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

    // Ao voltar do Google, o Supabase lê o token da própria URL e resolve a
    // sessão aqui — sem precisarmos fazer nada manual com a URL.
    // Os console.log ficam de propósito: se algo travar em produção, é o
    // primeiro lugar pra olhar (DevTools → Console).
    supabase.auth.getSession().then(({ data, error }) => {
      if (error) {
        console.error('[auth] erro ao checar sessão:', error.message)
        setAuthError(error.message)
      }
      console.log('[auth] sessão inicial:', data.session ? `logado como ${data.session.user.email}` : 'nenhuma sessão encontrada')
      setUser(data.session?.user ?? null)
      setStatus(data.session?.user ? 'signed-in' : 'signed-out')

      // Limpa o #access_token=... da barra de endereço depois de lido —
      // só estética/segurança, não é necessário pra sessão funcionar.
      if (window.location.hash.includes('access_token')) {
        window.history.replaceState(null, '', window.location.pathname + window.location.search)
      }
    })

    const { data: subscription } = supabase.auth.onAuthStateChange((event, session) => {
      console.log('[auth] evento:', event, session ? `usuário ${session.user.email}` : '(sem sessão)')
      setUser(session?.user ?? null)
      setStatus(session?.user ? 'signed-in' : 'signed-out')
    })

    return () => subscription.subscription.unsubscribe()
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
    await supabase.auth.signOut()
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
