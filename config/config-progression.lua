return function(Config)
    -- License / rank progression.
    Config.Licenses = {
        accountType = 'bank', -- Account used when buying licenses / rank unlocks
        defaultRank = 'trainee', -- Starting rank for new players
        ranks = {
            -- Rank unlock requirements and payout scaling.
            trainee = {
                label = 'Trainee',
                unlockPrice = 0,
                requirements = { minKm = 0, minRoutes = 0, minAccuracy = 0 },
                payoutMultiplier = 1.0
            },
            junior = {
                label = 'Junior',
                unlockPrice = 5000,
                requirements = { minKm = 25, minRoutes = 5, minAccuracy = 70, minLevel = 2 },
                payoutMultiplier = 1.15
            },
            senior = {
                label = 'Senior',
                unlockPrice = 10000,
                requirements = { minKm = 60, minRoutes = 15, minAccuracy = 80, minLevel = 4 },
                payoutMultiplier = 1.35
            },
            chief = {
                label = 'Chief',
                unlockPrice = 20000,
                requirements = { minKm = 120, minRoutes = 35, minAccuracy = 90, minLevel = 7 },
                payoutMultiplier = 1.65
            }
        }
    }

    -- XP gain and leveling.
    Config.XP = {
        perStop = 20, -- XP awarded per valid stop
        perRoute = 70, -- XP awarded per finished route
        perKm = 12, -- XP awarded per traveled kilometer
        levelStep = 500 -- XP required per level step
    }

    -- Ensure quest system root exists when progression loads.
    Config.Quests = Config.Quests or {}
    Config.Quests.enabled = true
    Config.Quests.definitions = Config.Quests.definitions or {}
end
