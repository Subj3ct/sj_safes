import React, { useState, useEffect, useRef } from 'react'
import { motion } from 'framer-motion'
import { ArrowLeft, ArrowRight, X, HelpCircle } from 'lucide-react'
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome'
import { faLock, faUnlock } from '@fortawesome/free-solid-svg-icons'
import { useSound } from '../hooks/useSound'
import type { SafeCrackingProps } from '../types'

export const SafeCracking: React.FC<SafeCrackingProps> = ({ config, onComplete, onClose }) => {
  const { playTone } = useSound()
  
  // Get difficulty settings from config
  const settings = config.SafeCracking[config.difficulty]

  // Basic game state
  const [rotation, setRotation] = useState(0)
  const [combination] = useState(() => {
    // Use the actual safe combination if provided, otherwise generate random numbers
    console.log('[SafeCracking] Config combination:', config.combination)
    if (config.combination) {
      const combinationArray = config.combination.split('-').map(num => parseInt(num, 10))
      console.log('[SafeCracking] Using real combination:', combinationArray)
      return combinationArray
    }
    const randomCombination = Array.from({ length: settings.numbers }, () => Math.floor(Math.random() * 101))
    console.log('[SafeCracking] Using random combination:', randomCombination)
    return randomCombination
  })
  const [currentTarget, setCurrentTarget] = useState(0)
  const [timeLeft, setTimeLeft] = useState(settings.timeLimit)
  const [gameStarted, setGameStarted] = useState(false)
  const [isMoving, setIsMoving] = useState(false)
  const [vibration, setVibration] = useState(0)
  const [lastDirection, setLastDirection] = useState<'left' | 'right'>('right')
  const [requiredDirection, setRequiredDirection] = useState<'left' | 'right'>('right')
  const [hasCompletedRotation, setHasCompletedRotation] = useState(false)
  const [totalRotationDistance, setTotalRotationDistance] = useState(0)
  const [lastRotation, setLastRotation] = useState(0)
  const [hasPassedTarget, setHasPassedTarget] = useState(false)
  const [showRotationMessage, setShowRotationMessage] = useState(false)
  const [showTutorial, setShowTutorial] = useState(false)
  
  const keysPressed = useRef<Set<string>>(new Set())
  const animationFrame = useRef<number>()

  // Simple timer
  useEffect(() => {
    if (!gameStarted) return
    
    const timer = setInterval(() => {
      setTimeLeft(prev => {
        if (prev <= 1) {
          onComplete(false)
          return 0
        }
        return prev - 1
      })
    }, 1000)

    return () => clearInterval(timer)
  }, [gameStarted, onComplete])

  useEffect(() => {
    if (currentTarget > 0) {
      setShowRotationMessage(true)
    }
  }, [currentTarget])

  useEffect(() => {
    setShowRotationMessage(true)
  }, [])

  // Get current dial number (invert rotation for correct display)
  const dialNumber = Math.floor(((360 - rotation) % 360) / 3.6)

  // Calculate distance to target
  const target = combination[currentTarget] || 0
  const distance = Math.min(
    Math.abs(dialNumber - target),
    100 - Math.abs(dialNumber - target)
  )

  // Track if user passed the target
  useEffect(() => {
    if (distance > settings.tolerance * 3) {
      // User moved significantly away from target, mark as passed
      if (!hasPassedTarget) {
        // First time passing - reset rotation tracking from this point
        setHasPassedTarget(true)
        setHasCompletedRotation(false)
        setTotalRotationDistance(0) // Reset rotation tracking from this point
        setLastRotation(rotation) // Set new starting point
      }
    }
    // Don't clear hasPassedTarget just by getting close - only clear after full rotation
  }, [distance, settings.tolerance, hasPassedTarget, rotation])

  // Track total rotation distance for full rotation requirement
  useEffect(() => {
    if (!isMoving) return
    
    // Calculate rotation distance from last position
    let rotationDiff = Math.abs(rotation - lastRotation)
    if (rotationDiff > 180) {
      rotationDiff = 360 - rotationDiff
    }
    
    // Add to total distance
    const newTotal = totalRotationDistance + rotationDiff
    setTotalRotationDistance(newTotal)
    setLastRotation(rotation)
    
    // Check if completed full rotation (360+ degrees)
    if (newTotal >= 360 && hasPassedTarget) {
      setHasCompletedRotation(true)
      setHasPassedTarget(false) // Clear passed flag ONLY after full rotation
    }
  }, [rotation, isMoving, totalRotationDistance, lastRotation, hasPassedTarget])

  // Vibration and sound logic
  useEffect(() => {
    if (isMoving && distance <= settings.vibrationRange) {
      const intensity = 1 - (distance / settings.vibrationRange)
      setVibration(intensity)
    } else {
      setVibration(0)
    }
    
    // Always play sound when moving, pitch based on distance
    if (isMoving && config.UI.enableSounds) {
      const baseTone = 200
      const maxTone = 600
      
      if (distance <= settings.vibrationRange) {
        const intensity = 1 - (distance / settings.vibrationRange)
        playTone(baseTone + (intensity * (maxTone - baseTone)), 0.02, 0.03)
      } else {
        playTone(baseTone, 0.01, 0.02)
      }
    }
  }, [dialNumber, isMoving, distance, config.UI.enableSounds, playTone, settings.vibrationRange])

  // Animation loop
  useEffect(() => {
    const animate = () => {
      const leftPressed = keysPressed.current.has('ArrowLeft')
      const rightPressed = keysPressed.current.has('ArrowRight')
      const ctrlPressed = keysPressed.current.has('Control')
      
      if (leftPressed || rightPressed) {
        setIsMoving(true)
        setGameStarted(true)
        
        // Slow rotation speed when Control is held
        const currentSpeed = ctrlPressed ? settings.rotationSpeed * 0.3 : settings.rotationSpeed
        
        if (leftPressed) {
          setRotation(prev => (prev - currentSpeed + 360) % 360)
          setLastDirection('left')
        }
        if (rightPressed) {
          setRotation(prev => (prev + currentSpeed) % 360)
          setLastDirection('right')
        }
      } else {
        setIsMoving(false)
      }
      
      animationFrame.current = requestAnimationFrame(animate)
    }
    
    animationFrame.current = requestAnimationFrame(animate)
    return () => {
      if (animationFrame.current) {
        cancelAnimationFrame(animationFrame.current)
      }
    }
  }, [settings.rotationSpeed])

  // Try to crack
  const tryCrack = () => {
    if (isMoving) return
    if (distance > settings.tolerance) return // Use difficulty-based tolerance
    if (lastDirection !== requiredDirection) {
      // Wrong direction - reset to beginning
      if (config.UI.enableSounds) {
        playTone(150, 0.3, 0.2) // Low error sound
      }
      setCurrentTarget(0)
      setRequiredDirection('right')
      setHasCompletedRotation(false)
      setTotalRotationDistance(0)
      setLastRotation(rotation)
      setHasPassedTarget(false)
      return
    }
    
    // Check if they need to complete a full rotation first (after first number OR after passing target)
    if ((currentTarget > 0 || hasPassedTarget) && !hasCompletedRotation) {
      if (config.UI.enableSounds) {
        playTone(250, 0.2, 0.1) // Medium warning sound
      }
      return // Can't crack until they've completed rotation
    }
    
    if (config.UI.enableSounds) {
      playTone(700, 0.2, 0.1) // Success sound
    }
    
    if (currentTarget >= combination.length - 1) {
      // Won! Return the combination
      onComplete(true, combination)
    } else {
      // Next number - play unlocking sound
      if (config.UI.enableSounds) {
        playTone(600, 0.15, 0.1) // Nice unlocking sound for partial success
      }
      
      setCurrentTarget(prev => prev + 1)
      setRequiredDirection(lastDirection === 'right' ? 'left' : 'right')
      setHasCompletedRotation(false) // Reset for next number
      setTotalRotationDistance(0) // Reset rotation tracking
      setLastRotation(rotation)
      setHasPassedTarget(false) // Reset passed target flag
    }
  }

  // Keyboard controls
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight' || e.key === 'Control') {
        keysPressed.current.add(e.key)
      }
      if (e.key === ' ' || e.key === 'Enter') {
        e.preventDefault()
        tryCrack()
      }
      if (e.key === 'Escape') {
        onClose()
      }
    }

    const handleKeyUp = (e: KeyboardEvent) => {
      keysPressed.current.delete(e.key)
    }

    window.addEventListener('keydown', handleKeyDown)
    window.addEventListener('keyup', handleKeyUp)
    
    return () => {
      window.removeEventListener('keydown', handleKeyDown)
      window.removeEventListener('keyup', handleKeyUp)
    }
  })

  // Status message
  let statusMessage = `Turn ${requiredDirection} to find number ${currentTarget + 1}`
  
  if (isMoving) {
    statusMessage = `Turning ${lastDirection}...`
    // Hide rotation message once they start moving
    if (showRotationMessage) {
      setShowRotationMessage(false)
    }
  } else if (distance <= settings.tolerance && lastDirection !== requiredDirection) {
    statusMessage = `Wrong direction! Need ${requiredDirection} (resets progress)`
  } else if (showRotationMessage && ((currentTarget > 0 || hasPassedTarget) && !hasCompletedRotation)) {
    statusMessage = `Complete full rotation first!`
  }

  // Calculate glow color based on distance - always visible
  const getGlowColor = () => {
    if (distance <= 3) return 'rgba(34, 197, 94, 0.7)' // Green - very close
    if (distance <= 8) return 'rgba(251, 146, 60, 0.6)' // Orange - close  
    return 'rgba(239, 68, 68, 0.5)' // Red - default/far
  }

  return (
    <div className="minigame-dialog">
      {/* Tutorial popup */}
      <motion.div
        initial={{ 
          opacity: 0, 
          scale: 0.7, 
          x: -180, 
          y: 60 
        }}
        animate={{ 
          opacity: showTutorial ? 1 : 0, 
          scale: showTutorial ? 1 : 0.7,
          x: showTutorial ? 0 : -180,
          y: showTutorial ? 0 : 60
        }}
        transition={{ 
          duration: 0.4, 
          ease: "easeOut",
          type: "spring",
          stiffness: 250,
          damping: 30
        }}
        style={{
          position: 'absolute',
          top: '200px',
          left: '24px',
          right: '24px',
          background: 'linear-gradient(135deg, rgba(31, 41, 55, 0.85) 0%, rgba(55, 65, 81, 0.9) 100%)',
          backdropFilter: 'blur(20px) saturate(120%)',
          border: '1px solid rgba(156, 163, 175, 0.25)',
          borderRadius: '16px',
          padding: '24px',
          fontSize: '14px',
          color: 'rgba(249, 250, 251, 0.95)',
          zIndex: 1000,
          pointerEvents: showTutorial ? 'auto' : 'none',
          boxShadow: '0 20px 50px rgba(0, 0, 0, 0.4), 0 0 0 1px rgba(255, 255, 255, 0.08)'
        }}
      >
        <div style={{ marginBottom: '8px', fontWeight: 'bold', fontSize: '14px' }}>How to Play:</div>
        <p style={{ marginBottom: '8px' }}>Turn slowly and watch the glow + listen to the pitch changes.</p>
        <p style={{ marginBottom: '8px' }}>If you pass the next number in the sequence, you must do a full rotation.</p>
        <p style={{ color: 'rgba(251, 146, 60, 0.8)' }}>Hold CTRL to slow rotation</p>
      </motion.div>

      {/* Tutorial button */}
      <motion.button
        onClick={() => setShowTutorial(!showTutorial)}
        whileHover={{ 
          scale: 1.05,
          backgroundColor: 'rgba(255, 255, 255, 0.15)',
          borderColor: 'rgba(255, 255, 255, 0.5)',
          boxShadow: '0 4px 16px rgba(255, 255, 255, 0.1)'
        }}
        whileTap={{ scale: 0.95 }}
        transition={{ duration: 0.2 }}
        style={{
          position: 'absolute',
          top: '16px',
          left: '24px',
          background: 'rgba(255, 255, 255, 0.1)',
          border: '1px solid rgba(255, 255, 255, 0.3)',
          borderRadius: '6px',
          padding: '0',
          color: 'white',
          cursor: 'pointer',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          width: '36px',
          height: '36px',
          zIndex: 999
        }}
      >
        <motion.div
          animate={{ rotate: showTutorial ? 15 : 0 }}
          transition={{ duration: 0.2 }}
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: '100%',
            height: '100%'
          }}
        >
          <HelpCircle size={18} />
        </motion.div>
      </motion.button>

      {/* Close button */}
      <button
        onClick={onClose}
        className="close-button"
      >
        <X size={24} />
      </button>

      {/* Header */}
      <div className="text-center mb-6">
        <h2 style={{ fontSize: '24px', fontWeight: 'bold', color: 'white', marginBottom: '8px' }}>Safe Cracking</h2>
        <div className="flex justify-center items-center text-white-70 gap-4">
          <span>Numbers: {currentTarget + 1}/{combination.length}</span>
          <span>Time: {timeLeft}s</span>
        </div>
      </div>

      {/* Progress indicators - lock icons */}
      <div className="flex justify-center gap-4 mb-6" style={{ gap: '16px', marginBottom: '24px' }}>
        {combination.map((_, index) => {
          const isCompleted = index < currentTarget
          const isCurrent = index === currentTarget
          
          return (
            <div
              key={index}
              style={{
                color: isCompleted ? '#10b981' : isCurrent ? '#f59e0b' : 'rgba(255, 255, 255, 0.5)',
                animation: isCurrent ? 'pulse 2s infinite' : 'none'
              }}
            >
              {isCompleted ? (
                <FontAwesomeIcon icon={faUnlock} size="lg" />
              ) : (
                <FontAwesomeIcon icon={faLock} size="lg" />
              )}
            </div>
          )
        })}
      </div>

      {/* Safe Dial */}
      <div className="relative flex flex-col items-center">
        {/* Dial Arrow */}
        <div 
          style={{
            fontSize: '24px',
            color: '#ef4444',
            filter: 'drop-shadow(0 2px 4px rgba(0, 0, 0, 0.5))',
            marginBottom: '-24px',
            zIndex: 10
          }}
        >
          ▼
        </div>
        
        {/* Background safe image */}
        <div 
          style={{ 
            width: '256px', 
            height: '256px', 
            backgroundImage: 'url(/safe.png)',
            backgroundSize: 'cover',
            backgroundPosition: 'center',
            marginBottom: '16px',
            position: 'relative'
          }}
        >
          {/* Dial overlay */}
          <div className="absolute inset-0 flex items-center justify-center">
            {/* Glow effect */}
            <div 
              style={{
                position: 'absolute',
                width: '192px',
                height: '192px',
                borderRadius: '50%',
                transition: 'all 0.3s ease',
                boxShadow: `0 0 15px 4px ${getGlowColor()}`
              }}
            />
            
            <motion.div
              style={{
                width: '192px',
                height: '192px',
                border: '4px solid rgba(255, 255, 255, 0.3)',
                borderRadius: '50%',
                background: 'linear-gradient(135deg, #4b5563 0%, #374151 100%)',
                position: 'relative',
                boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.25)',
                rotate: `${rotation}deg`
              }}
              animate={{
                x: vibration > 0.3 ? [0, (Math.random() - 0.5) * 6, 0] : 0,
                y: vibration > 0.3 ? [0, (Math.random() - 0.5) * 6, 0] : 0
              }}
              transition={{
                x: { duration: 0.08, repeat: vibration > 0.3 ? Infinity : 0 },
                y: { duration: 0.08, repeat: vibration > 0.3 ? Infinity : 0 }
              }}
            >
            {/* Small tick marks every 3.6 degrees (100 total marks) */}
            {Array.from({ length: 100 }, (_, i) => {
              const angle = i * 3.6 // Every 3.6 degrees for 100 marks total
              const number = i // 0-99
              
              // Check if this is a major position (every 10: 0, 10, 20, 30, 40, 50, 60, 70, 80, 90)
              const isMajor = number % 10 === 0
              
              if (isMajor) return null // Skip small marks at major positions
              
              const radians = (angle * Math.PI) / 180
              const outerRadius = 88 // Start from outer edge
              const outerX = Math.sin(radians) * outerRadius
              const outerY = -Math.cos(radians) * outerRadius
              
              return (
                <div
                  key={`small-${i}`}
                  style={{
                    position: 'absolute',
                    left: '50%',
                    top: '50%',
                    width: '1px',
                    height: '10px',
                    backgroundColor: 'rgba(255, 255, 255, 0.8)',
                    transformOrigin: '50% 0%',
                    transform: `translate(${outerX - 0.5}px, ${outerY}px) rotate(${angle}deg)`,
                  }}
                />
              )
            })}

            {/* Large tick marks every 10 numbers (0, 10, 20, 30, 40, 50, 60, 70, 80, 90) */}
            {[0, 10, 20, 30, 40, 50, 60, 70, 80, 90].map((number) => {
              const angle = number * 3.6 // Convert to angle
              const radians = (angle * Math.PI) / 180
              const outerRadius = 88
              const outerX = Math.sin(radians) * outerRadius
              const outerY = -Math.cos(radians) * outerRadius
              
              return (
                <div
                  key={`large-${number}`}
                  style={{
                    position: 'absolute',
                    left: '50%',
                    top: '50%',
                    width: '2px',
                    height: '15px',
                    backgroundColor: 'rgba(255, 255, 255, 1)',
                    transformOrigin: '50% 0%',
                    transform: `translate(${outerX - 1}px, ${outerY}px) rotate(${angle}deg)`,
                  }}
                />
              )
            })}

            {/* Numbers at each large tick facing inward toward center */}
            {[0, 10, 20, 30, 40, 50, 60, 70, 80, 90].map((number) => {
              const angle = number * 3.6 // Convert to angle
              const radians = (angle * Math.PI) / 180
              const radius = 65 // Position closer to center
              const x = Math.sin(radians) * radius
              const y = -Math.cos(radians) * radius
              
              // Calculate rotation to face inward toward center, then rotate 180 more
              let rotation = angle + 360 // Base rotation + 180 degrees more
              if (angle === 0) rotation = 180 // Top number rotated 180
              
              return (
                <div
                  key={`number-${number}`}
                  style={{
                    position: 'absolute',
                    left: '50%',
                    top: '50%',
                    fontSize: '14px',
                    color: 'white',
                    fontWeight: 'bold',
                    transform: `translate(${x}px, ${y}px) translate(-50%, -50%) rotate(${rotation}deg)`,
                  }}
                >
                  {number}
                </div>
              )
            })}
            
            {/* Center dot */}
            <div className="absolute inset-0 flex items-center justify-center">
              <div style={{ width: '16px', height: '16px', backgroundColor: 'white', borderRadius: '50%', boxShadow: '0 4px 6px -1px rgba(0, 0, 0, 0.1)' }} />
            </div>
          </motion.div>
          </div>
        </div>

        {/* Controls */}
        <div className="flex items-center gap-6 mb-4" style={{ gap: '24px', marginBottom: '16px' }}>
          <div className="flex items-center gap-2 text-white-70" style={{ gap: '8px' }}>
            <ArrowLeft size={20} />
            <span style={{ fontSize: '14px' }}>Left Arrow</span>
          </div>
          <div className="text-center">
            <div style={{ 
              fontSize: '32px', 
              fontFamily: 'monospace', 
              color: 'white', 
              background: 'rgba(0, 0, 0, 0.3)', 
              padding: '8px 16px', 
              borderRadius: '4px' 
            }}>
              {dialNumber.toString().padStart(2, '0')}
            </div>
            <div style={{ fontSize: '12px', color: 'rgba(255, 255, 255, 0.7)', marginTop: '4px' }}>Current Number</div>
          </div>
          <div className="flex items-center gap-2 text-white-70" style={{ gap: '8px' }}>
            <span style={{ fontSize: '14px' }}>Right Arrow</span>
            <ArrowRight size={20} />
          </div>
        </div>

        {/* Status */}
        <div className="text-center text-white-70" style={{ fontSize: '14px' }}>
          {statusMessage}
        </div>
      </div>
    </div>
  )
} 