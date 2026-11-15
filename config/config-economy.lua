return function(Config)
    -- Legacy or shared payout values.
    Config.Payout = {
        baseReward = 1000, -- Base route reward fallback
        missedStopPenalty = 50, -- Penalty applied for missed stops
        wrongStopPenalty = 80, -- Penalty applied for wrong stop confirmations
        currency = 'bank' -- Account used for payouts
    }

    -- Freight-specific container rewards.
    Config.FreightPayout = {
        containerReward = 200, -- Reward per delivered container
        completionBonus = 1000, -- Bonus paid at full route completion
        ranks = {
            -- Rank reward overrides.
            trainee = {
                containerReward = 200,
                completionBonus = 1000
            },
            junior = {
                containerReward = 230,
                completionBonus = 1200
            },
            senior = {
                containerReward = 260,
                completionBonus = 1400
            },
            chief = {
                containerReward = 300,
                completionBonus = 1700
            }
        }
    }

    -- Main economy values used by current route logic.
    Config.Economy = {
        stopReward = 140, -- Reward per valid service stop
        completionReward = 850, -- Bonus for full route completion
        partial = {
            enabled = true, -- Enable partial payout when route is not fully completed
            allowOnEarlyExit = true, -- Allow partial payout on early exit
            minCompletedStopsForPartial = 7, -- Minimum completed stops required for partial payment
            rewardPerCompletedStop = 120, -- Reward granted per completed stop in partial mode
            maxPayableStops = 30 -- Upper cap for payable completed stops
        },
        antiAbuse = {
            minSecondsBeforeAnyPayout = 60, -- Minimum time before any payout can be earned
            minSecondsPerStopCredit = 10 -- Minimum route time per credited stop
        }
    }

    -- Optional passenger tip system.
    Config.Tips = {
        enabled = true, -- Enable random tip rewards
        rollPerCompletedStop = true, -- Roll tip chance on each completed stop
        chanceByRank = {
            -- Chance in percent per completed stop.
            trainee = 10,
            junior = 15,
            senior = 20,
            chief = 25
        },
        amountByRank = {
            -- Tip value range per rank.
            trainee = { min = 8, max = 20 },
            junior = { min = 15, max = 35 },
            senior = { min = 25, max = 50 },
            chief = { min = 40, max = 80 }
        }
    }
end
