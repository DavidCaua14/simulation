// Camada de dados do jogador/carreira.
// Hoje tudo roda em localStorage, já namespaceado pelo usuário logado
// (userId do Supabase Auth). Quando o Supabase Database entrar (tabelas
// `careers`/`players`), essas funções trocam de "miolo" — quem chama (a
// tela) não muda: sempre passando o `userId` de quem está logado.
import { MIN_AGE, MAX_AGE, STARTING_LEVEL } from './data/gameConstants'

const CAREERS_KEY = 'simulation:careers' // lista global (todas as carreiras)
const activeCareerKey = (userId) => `simulation:activeCareerId:${userId}`

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
export function hasActiveCareer(userId) {
  return Boolean(localStorage.getItem(activeCareerKey(userId)))
}

export function isNicknameTaken(nickname) {
  // Único entre TODOS os usuários (não só o logado) — é isso que garante
  // que o nickname sirva de identificador nos duelos 1x1.
  const normalized = nickname.trim().toLowerCase()
  return readCareers().some((c) => c.player?.nickname?.toLowerCase() === normalized)
  // Em produção, trocar por uma consulta ao Supabase, ex:
  // const { data } = await supabase.from('players').select('id').ilike('nickname', normalized)
  // return data.length > 0
}

export async function createPlayer({ userId, nickname, photoId, country, age }) {
  await delay(700) // simula latência de rede, já preparado para chamada assíncrona real

  if (!userId) {
    throw new Error('Você precisa estar logado para criar um personagem.')
  }

  // As regras também valem aqui (e não só na tela), porque no Supabase
  // essa é a camada que não pode ser burlada pelo navegador.
  const ageNumber = Number(age)
  if (!Number.isInteger(ageNumber) || ageNumber < MIN_AGE || ageNumber > MAX_AGE) {
    throw new Error(`A idade deve ser entre ${MIN_AGE} e ${MAX_AGE} anos.`)
  }
  if (isNicknameTaken(nickname)) {
    throw new Error('Esse username já está em uso. Escolha outro.')
  }

  const career = {
    id: crypto.randomUUID(),
    userId, // dono da carreira — vem do Supabase Auth (user.id)
    createdAt: new Date().toISOString(),
    status: 'active',
    player: {
      nickname: nickname.trim(),
      photoId, // só o id da foto de perfil, nunca a imagem em si
      country, // vai definir as opções iniciais de times da carreira
      age: ageNumber,
      // Posição e número da camisa ainda não são definidos na criação.
      position: null,
      jerseyNumber: null,
      // Progressão RPG: o personagem evolui com tempo, tarefas e partidas.
      level: STARTING_LEVEL,
      xp: 0,
      skills: {
        finalizacao: 20,
        passe: 20,
        drible: 20,
        defesa: 20,
        fisico: 20,
        velocidade: 20,
      },
      accessories: [], // reservado para a futura loja
    },
  }

  const careers = readCareers()
  careers.push(career)
  writeCareers(careers)
  localStorage.setItem(activeCareerKey(userId), career.id)

  // Em produção, trocar por:
  // const { data, error } = await supabase.from('careers').insert(career).select().single()
  // if (error) throw error
  // return data

  return career
}
