export type Difficulty = 'easy' | 'medium' | 'hard'

export interface UIConfig {
  primaryColor: string
  secondaryColor: string
  successColor: string
  errorColor: string
  glassOpacity: number
  blurAmount: string
  animationSpeed: number
  enableSounds: boolean
  soundVolume: number
}

export interface SafeCrackingConfig {
  numbers: number
  timeLimit: number
  tolerance: number
  vibrationRange: number
  rotationSpeed: number
}

export interface GameConfig {
  difficulty: Difficulty
  SafeCracking: Record<Difficulty, SafeCrackingConfig>
  UI: UIConfig
  combination?: string
}

export interface SafeCrackingProps {
  config: GameConfig
  onComplete: (success: boolean, combination?: number[]) => void
  onClose: () => void
}

export interface NUIMessage {
  action: string
  [key: string]: any
} 