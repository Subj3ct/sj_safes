import React, { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { SafeCracking } from './components/SafeCracking'
import { GameRender } from './components/GameRender'
import type { GameConfig, NUIMessage } from './types'

function App() {
  const [isVisible, setIsVisible] = useState(false)
  const [gameConfig, setGameConfig] = useState<GameConfig | null>(null)
  
  useEffect(() => {
  }, [])
  useEffect(() => {
    const handleMessage = (event: MessageEvent<NUIMessage>) => {
      const { action, config } = event.data

      switch (action) {
        case 'test':
          break
        case 'openSafeCracking':
          setGameConfig(config)
          setIsVisible(true)
          break
        case 'closeSafeCracking':
          setIsVisible(false)
          setGameConfig(null)
          break
        default:
      }
    }

    window.addEventListener('message', handleMessage)
    return () => window.removeEventListener('message', handleMessage)
  }, [])

  // Handle escape key
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && isVisible) {
        handleClose()
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [isVisible])

  const handleComplete = (success: boolean, combination?: number[]) => {
    fetch('https://sj_safes/safeCrackingComplete', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        success,
        combination: combination || []
      }),
    }).catch(() => {
    })
    
    setIsVisible(false)
    setGameConfig(null)
  }

  const handleClose = () => {
    fetch('https://sj_safes/closeSafeCracking', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({}),
    }).catch(() => {
    })
    
    setIsVisible(false)
    setGameConfig(null)
  }

  return (
    <div className="app-wrapper">
      <AnimatePresence>
        {isVisible && gameConfig && (
          <>
            {/* Game render canvas - only when minigame is active */}
            <GameRender />
            
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.3 }}
              className="minigame-overlay"
              onClick={(e) => {
                if (e.target === e.currentTarget) {
                  handleClose()
                }
              }}
            >
              <motion.div
                initial={{ scale: 0.8, y: 50 }}
                animate={{ scale: 1, y: 0 }}
                exit={{ scale: 0.8, y: 50 }}
                transition={{ 
                  type: "spring", 
                  stiffness: 300, 
                  damping: 30 
                }}
                className="minigame-container"
              >
                <SafeCracking
                  config={gameConfig}
                  onComplete={handleComplete}
                  onClose={handleClose}
                />
              </motion.div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  )
}

export default App 