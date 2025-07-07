Config = {}

-- Safe types configuration
Config.SafeTypes = {
    ['small_safe'] = {
        label = 'Small Safe',
        prop = 'prop_ld_int_safe_01',
        slots = 10,
        maxWeight = 50000, -- 50kg
        description = 'A small personal safe for storing valuable items'
    },
    ['large_safe'] = {
        label = 'Large Safe',
        prop = 'p_v_43_safe_s',
        slots = 30,
        maxWeight = 150000, -- 150kg
        description = 'A large safe for storing many valuable items'
    }
}

-- Safe cracking settings
Config.SafeCracking = {
    easy = {
        numbers = 3,
        timeLimit = 60,
        tolerance = 5,
        vibrationRange = 15,
        rotationSpeed = 2.0
    },
    medium = {
        numbers = 3,
        timeLimit = 45,
        tolerance = 3,
        vibrationRange = 10,
        rotationSpeed = 2.5
    },
    hard = {
        numbers = 3,
        timeLimit = 30,
        tolerance = 2,
        vibrationRange = 8,
        rotationSpeed = 3.0
    }
}

-- UI Configuration
Config.UI = {
    enableSounds = true
}

-- General settings
Config.General = {
    difficulty = 'medium', -- Default difficulty for safes
    deleteEmptyStashes = true, -- Delete stashes when safes are removed
    requireCombination = true, -- Require combination to access safe
    maxSafesPerPlayer = 5, -- Maximum safes a player can place (0 = unlimited)
} 