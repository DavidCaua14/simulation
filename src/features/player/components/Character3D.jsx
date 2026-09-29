// Boneco 3D completo do jogador, com câmera giratória (arraste para
// controlar) e material de cada parte ligado direto ao estado de
// `appearance` — qualquer troca de cor/estilo aparece em tempo real.
//
// É um personagem estilizado (formas geométricas simples: esfera, cápsula,
// caixa), no espírito de criadores tipo Mii/Rocket League/Roblox — não um
// rosto realista escaneado como em PES/FIFA, que exige modelagem e
// texturização feitas por artistas 3D, fora do alcance de gerar por código.
import { Suspense } from 'react'
import { Canvas } from '@react-three/fiber'
import { OrbitControls, Environment, ContactShadows } from '@react-three/drei'

const JERSEY_COLOR = '#16a34a'
const SHORTS_COLOR = '#12151a'

function HairMesh({ style, color }) {
  if (style === 'bald') return null
  if (style === 'buzz') {
    return (
      <mesh position={[0, 1.78, 0]} castShadow>
        <sphereGeometry args={[0.315, 24, 16, 0, Math.PI * 2, 0, Math.PI * 0.55]} />
        <meshStandardMaterial color={color} roughness={0.7} />
      </mesh>
    )
  }
  if (style === 'curly') {
    const offsets = [
      [0, 1.85, 0.1],
      [0.22, 1.78, 0.08],
      [-0.22, 1.78, 0.08],
      [0.14, 1.8, -0.18],
      [-0.14, 1.8, -0.18],
    ]
    return (
      <group>
        {offsets.map((pos, i) => (
          <mesh key={i} position={pos} castShadow>
            <sphereGeometry args={[0.14, 12, 10]} />
            <meshStandardMaterial color={color} roughness={0.9} />
          </mesh>
        ))}
      </group>
    )
  }
  if (style === 'wavy') {
    return (
      <group>
        <mesh position={[0, 1.8, 0.02]} castShadow>
          <sphereGeometry args={[0.33, 24, 16, 0, Math.PI * 2, 0, Math.PI * 0.6]} />
          <meshStandardMaterial color={color} roughness={0.7} />
        </mesh>
        <mesh position={[0, 1.62, -0.22]} rotation={[0.4, 0, 0]} castShadow>
          <capsuleGeometry args={[0.1, 0.22, 4, 8]} />
          <meshStandardMaterial color={color} roughness={0.7} />
        </mesh>
      </group>
    )
  }
  // short (padrão)
  return (
    <mesh position={[0, 1.79, 0]} castShadow>
      <sphereGeometry args={[0.325, 24, 16, 0, Math.PI * 2, 0, Math.PI * 0.58]} />
      <meshStandardMaterial color={color} roughness={0.7} />
    </mesh>
  )
}

function BeardMesh({ color }) {
  return (
    <mesh position={[0, 1.42, 0.2]} castShadow>
      <sphereGeometry args={[0.22, 16, 12, 0, Math.PI * 2, Math.PI * 0.4, Math.PI * 0.5]} />
      <meshStandardMaterial color={color} roughness={0.9} />
    </mesh>
  )
}

function Limb({ position, rotation = [0, 0, 0], length, radius, color }) {
  return (
    <mesh position={position} rotation={rotation} castShadow>
      <capsuleGeometry args={[radius, length, 4, 12]} />
      <meshStandardMaterial color={color} roughness={0.55} />
    </mesh>
  )
}

function Character({ skin, hair, hairColor, eyeColor, beard }) {
  return (
    <group position={[0, -1, 0]}>
      {/* cabeça */}
      <mesh position={[0, 1.6, 0]} castShadow>
        <sphereGeometry args={[0.34, 32, 24]} />
        <meshStandardMaterial color={skin} roughness={0.6} />
      </mesh>
      {/* olhos */}
      <mesh position={[0.12, 1.63, 0.29]}>
        <sphereGeometry args={[0.035, 12, 12]} />
        <meshStandardMaterial color={eyeColor} roughness={0.3} />
      </mesh>
      <mesh position={[-0.12, 1.63, 0.29]}>
        <sphereGeometry args={[0.035, 12, 12]} />
        <meshStandardMaterial color={eyeColor} roughness={0.3} />
      </mesh>
      {beard && <BeardMesh color={hairColor} />}
      <HairMesh style={hair} color={hairColor} />

      {/* pescoço */}
      <mesh position={[0, 1.32, 0]}>
        <cylinderGeometry args={[0.11, 0.13, 0.16, 16]} />
        <meshStandardMaterial color={skin} roughness={0.6} />
      </mesh>

      {/* tronco (camisa) */}
      <mesh position={[0, 0.95, 0]} castShadow>
        <capsuleGeometry args={[0.32, 0.55, 4, 16]} />
        <meshStandardMaterial color={JERSEY_COLOR} roughness={0.55} />
      </mesh>

      {/* braços */}
      <Limb position={[0.46, 0.98, 0]} rotation={[0, 0, -0.18]} length={0.55} radius={0.11} color={JERSEY_COLOR} />
      <Limb position={[-0.46, 0.98, 0]} rotation={[0, 0, 0.18]} length={0.55} radius={0.11} color={JERSEY_COLOR} />
      {/* mãos */}
      <mesh position={[0.58, 0.52, 0]}>
        <sphereGeometry args={[0.1, 14, 12]} />
        <meshStandardMaterial color={skin} roughness={0.6} />
      </mesh>
      <mesh position={[-0.58, 0.52, 0]}>
        <sphereGeometry args={[0.1, 14, 12]} />
        <meshStandardMaterial color={skin} roughness={0.6} />
      </mesh>

      {/* calção */}
      <mesh position={[0, 0.42, 0]} castShadow>
        <capsuleGeometry args={[0.28, 0.2, 4, 16]} />
        <meshStandardMaterial color={SHORTS_COLOR} roughness={0.6} />
      </mesh>

      {/* pernas */}
      <Limb position={[0.16, -0.05, 0]} length={0.62} radius={0.13} color={skin} />
      <Limb position={[-0.16, -0.05, 0]} length={0.62} radius={0.13} color={skin} />
      {/* chuteiras */}
      <mesh position={[0.16, -0.62, 0.06]}>
        <boxGeometry args={[0.16, 0.12, 0.28]} />
        <meshStandardMaterial color="#111318" roughness={0.4} />
      </mesh>
      <mesh position={[-0.16, -0.62, 0.06]}>
        <boxGeometry args={[0.16, 0.12, 0.28]} />
        <meshStandardMaterial color="#111318" roughness={0.4} />
      </mesh>
    </group>
  )
}

export default function Character3D({ appearance }) {
  return (
    <Canvas shadows camera={{ position: [0, 0.3, 2.6], fov: 32 }} dpr={[1, 1.5]}>
      <ambientLight intensity={0.55} />
      <directionalLight position={[2, 3, 2]} intensity={1.1} castShadow />
      <Suspense fallback={null}>
        <Character {...appearance} />
        <ContactShadows position={[0, -1.65, 0]} opacity={0.35} scale={3} blur={2.4} far={2} />
        <Environment preset="city" />
      </Suspense>
      <OrbitControls
        enablePan={false}
        enableZoom={false}
        minPolarAngle={Math.PI / 2.6}
        maxPolarAngle={Math.PI / 1.9}
        autoRotate
        autoRotateSpeed={2.2}
      />
    </Canvas>
  )
}
