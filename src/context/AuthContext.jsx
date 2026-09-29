import { createContext, useContext, useEffect, useState } from 'react'
import { supabase, isSupabaseConfigured } from '../lib/supabaseClient'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  // 'loading' -> checando se já existe uma sessão (ex: voltando do Google)
  // 'signed-out' -> mostra o login
  // 'signed-in' -> usuário autenticado
  const [status, setStatus] = useState(isSupabaseConfigured ? 'loading' : 'signed-out')
  const [user, setUser] = useState(null)
  const [authError, setAuthError] = useState('')

  useEffect(() => {
    if (!isSupabaseConfigured) return

    // Ao voltar do Google, o Supabase lê o token da própria URL e resolve a
    // sessão aqui — sem precisarmos fazer nada manual com a URL.
    supabase.auth.getSession().then(({ data, error }) => {
      if (error) setAuthError(error.message)
      setUser(data.session?.user ?? null)
      setStatus(data.session?.user ? 'signed-in' : 'signed-out')
    })

    const { data: subscription } = supabase.auth.onAuthStateChange((_event, session) => {
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
    setAuthError('')
    // Isso navega o navegador para o Google e volta — é assim que o OAuth
    // por redirecionamento funciona, não tem como evitar essa ida e volta.
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
    })
    if (error) setAuthError(error.message)
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
