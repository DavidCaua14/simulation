// Camada de dados do jogador/carreira.
// Hoje tudo roda em localStorage. Quando o Supabase entrar em produção,
// só o "miolo" destas funções muda — quem usa (a tela) não muda nada.

const CAREERS_KEY = 'simulation:careers'
const ACTIVE_CAREER_KEY = 'simulation:activeCareerId'

function readCareers() {
  try {
    return JSON.parse(localStorage.getItem(CAREERS_KEY)) || []
  } catch {
    return []
  }
}

function writeCareers(careers) {
  localStorage.setItem(CAREERS_KEY, JSON.stringify(careers))
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

// Regra de negócio: 1 carreira ativa por vez por usuário.
export function hasActiveCareer() {
  return Boolean(localStorage.getItem(ACTIVE_CAREER_KEY))
}

export function isNicknameTaken(nickname) {
  const normalized = nickname.trim().toLowerCase()
  return readCareers().some((c) => c.player.nickname.toLowerCase() === normalized)
  // Em produção, trocar por uma consulta ao Supabase, ex:
  // const { data } = await supabase.from('players').select('id').ilike('nickname', normalized)
  // return data.length > 0
}

export async function createPlayer({ nickname, avatarId, avatarPhoto, position, jerseyNumber }) {
  await delay(700) // simula latência de rede, já preparado para chamada assíncrona real

  if (isNicknameTaken(nickname)) {
    throw new Error('Esse nickname já está em uso. Escolha outro.')
  }

  const career = {
    id: crypto.randomUUID(),
    createdAt: new Date().toISOString(),
    status: 'active',
    player: {
      nickname: nickname.trim(),
      avatarId: avatarPhoto ? null : avatarId,
      // Hoje a foto vai em base64 direto no localStorage. Em produção,
      // trocar por upload no Supabase Storage e guardar aqui só a URL:
      // avatarPhotoUrl: await uploadToSupabaseStorage(avatarPhoto)
      avatarPhoto: avatarPhoto || null,
      position,
      jerseyNumber: Number(jerseyNumber),
      age: 16,
      level: 1,
      xp: 0,
      skills: {
        finalizacao: 20,
        passe: 20,
        drible: 20,
        defesa: 20,
        fisico: 20,
        velocidade: 20,
      },
    },
  }

  const careers = readCareers()
  careers.push(career)
  writeCareers(careers)
  localStorage.setItem(ACTIVE_CAREER_KEY, career.id)

  // Em produção, trocar por:
  // const { data, error } = await supabase.from('careers').insert(career).select().single()
  // if (error) throw error
  // return data

  return career
}
