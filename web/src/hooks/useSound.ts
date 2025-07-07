import { useCallback } from 'react'

interface SoundHook {
  playTone: (frequency: number, volume: number, duration: number) => void
}

export const useSound = (): SoundHook => {
  const playTone = useCallback((frequency: number, volume: number, duration: number) => {
    try {
      const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)()
      const oscillator = audioContext.createOscillator()
      const gainNode = audioContext.createGain()
      
      oscillator.connect(gainNode)
      gainNode.connect(audioContext.destination)
      
      oscillator.frequency.value = frequency
      oscillator.type = 'sine'
      
      gainNode.gain.setValueAtTime(volume, audioContext.currentTime)
      gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + duration)
      
      oscillator.start(audioContext.currentTime)
      oscillator.stop(audioContext.currentTime + duration)
    } catch (error) {
    }
  }, [])

  return { playTone }
} 