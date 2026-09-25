// Integração com Supabase já deixada pronta para a fase de produção.
// Por enquanto o app funciona 100% local (veja src/features/player/playerService.js).
//
// Quando for ativar de verdade:
// 1. npm install @supabase/supabase-js
// 2. Criar um arquivo .env (baseado no .env.example) com:
//      VITE_SUPABASE_URL=...
//      VITE_SUPABASE_ANON_KEY=...
// 3. Descomentar o import e a criação do client abaixo

// import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

export const supabase = null
// export const supabase = isSupabaseConfigured
//   ? createClient(supabaseUrl, supabaseAnonKey)
//   : null
