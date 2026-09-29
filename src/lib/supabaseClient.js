// Cliente real do Supabase (autenticação). Precisa de duas variáveis de
// ambiente — veja .env.example e o passo a passo no README-INTEGRACAO.md
// para pegar essas chaves no painel do Supabase.
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

if (!isSupabaseConfigured) {
  // Fica só no console — a tela de login trata isso com uma mensagem
  // amigável em vez de quebrar.
  console.warn(
    '[supabase] VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY não configuradas. ' +
      'Veja o README-INTEGRACAO.md para o passo a passo.'
  )
}

export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey)
  : null
