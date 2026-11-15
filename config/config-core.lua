return function(Config)
    -- Core framework and language settings.
    Config.FrameworkMode = 'auto' -- Framework resolver mode: auto/qb/esx/qbox
    Config.DebugLevel = 'off' -- Debug verbosity level: off/basic/verbose
    Config.Debug = nil -- Legacy debug override kept for backward compatibility
    Config.Locale = 'en' -- Locale used by the resource UI and notifications

    -- UI provider selection.
    Config.Notify = 'ox' -- Notification provider: qb/qbox/esx/ox
    Config.TextUI = 'ox' -- Text UI provider
    Config.Progress = 'ox' -- Progress bar provider
    Config.Dialog = 'ox' -- Dialog / alert provider
    Config.QBTextPosition = 'left' -- qb-core DrawText position
    Config.MenuOpen = 'qb-target' -- Interaction provider: qb-target/ox-target/qb-textui/ox-textui

    -- Automatic framework / dependency detection.
    Config.AutoDetection = {
        framework = {
            enabled = true, -- Try to resolve the active framework automatically
            priority = { 'qbox', 'qb', 'esx' }, -- Detection order when multiple frameworks exist
            resources = {
                qbox = 'qbx_core', -- Resource name used to detect Qbox
                qb = 'qb-core', -- Resource name used to detect QB-Core
                esx = 'es_extended' -- Resource name used to detect ESX
            }
        },
        dependencies = {
            enabled = true, -- Auto-detect optional support resources
            database = { 'oxmysql' }, -- Supported database resources
            fuel = { 'ox_fuel', 'LegacyFuel', 'cdn-fuel', 'ps-fuel' } -- Supported fuel resources
        }
    }

    -- Default keyboard controls.
    Config.Keys = {
        Interact = 38, -- Generic interaction key
        VehicleExitEnter = 23, -- Enter / exit vehicle key
        StopConfirm = 38, -- Station stop confirmation key
        TrainSpeedUp = 71, -- Train throttle increase key
        TrainSpeedDown = 72, -- Train throttle decrease / reverse key
        TrainEmergencyBrake = 73, -- Emergency brake key
        TrainBrake = 22 -- Service brake key
    }

    -- Job start NPC setup.
    Config.StartNPC = {
        enabled = true, -- Master toggle for the start NPC
        model = 's_m_m_lsmetro_01', -- Default ped model if no type override is used
        coords = vec4(2616.5315, 1689.0558, 27.5992, 86.9838), -- Default spawn location
        interactionDistance = 2.0, -- Distance required to interact with the NPC
        blip = {
            enabled = true, -- Show a blip for the NPC
            sprite = 280, -- Blip sprite id
            scale = 0.85, -- Blip scale
            color = 5, -- Blip color id
            shortRange = true, -- Only show nearby on minimap
            name = 'Train Job' -- Blip label
        },
        types = {
            -- Freight-specific start NPC override.
            freight = {
                model = 's_m_m_lsmetro_01',
                coords = vec4(2616.5315, 1689.0558, 27.5992, 86.9838),
                interactionDistance = 2.0,
                blip = {
                    enabled = true,
                    sprite = 280,
                    scale = 0.85,
                    color = 5,
                    shortRange = true,
                    name = 'Train Job'
                }
            },
            -- Metro-specific start NPC override.
            metro = {
                model = 's_m_m_dockwork_01',
                coords = vec4(-208.3183, -1019.4796, 30.1384, 335.2159),
                interactionDistance = 2.0,
                blip = {
                    enabled = true,
                    sprite = 280,
                    scale = 0.85,
                    color = 2,
                    shortRange = true,
                    name = 'Metro Job'
                }
            }
        }
    }

    -- Shared vehicle and train spawn behavior.
    Config.Vehicle = {
        model = 'freight', -- Default fallback vehicle model
        warpIntoVehicle = true, -- Warp the player into the train on spawn
        deleteOnFinish = true, -- Delete spawned job vehicles after route end
        reenterDistance = 14.0, -- Freight re-enter interaction distance
        reenterDistanceMetro = 28.0, -- Metro re-enter interaction distance
        reenterPopupDistance = 24.0, -- Distance where out-of-train warning can appear
        reenterEnterTimeoutMs = 6000, -- Time before re-enter attempt force-warps the player
        keepFuelFull = true, -- Keep fuel full for supported fuel systems
        fuelLevel = 100.0, -- Fuel level to maintain while route is active
        stopRadiusMultiplier = 6.0, -- Multiplier applied to stop detection radius
        maxStopSpeed = 1.5, -- Max speed allowed for valid stop interaction
        useMissionTrain = true, -- Spawn trains using mission-train native flow
        missionTrainVariation = 21, -- Default mission train variation
        missionTrainDirection = false, -- Default mission train direction
        types = {} -- Per-train-type overrides are populated in route config files
    }

    -- Manual train handling profile.
    Config.TrainControl = {
        enabled = true, -- Enable custom train controls
        brakeSqueal = {
            enabled = true, -- Play brake squeal / horn effect during braking
            holdMs = 1800, -- Brake hold time before the sound can trigger
            intervalMs = 1200, -- Cooldown between sound triggers
            useTrainHorn = false, -- Use actual horn native instead of fallback sound
            hornDurationMs = 280, -- Horn duration in ms
            hornMode = 'NORMAL', -- Native horn mode
            hornLoud = false, -- Loud horn toggle
            soundName = 'Train_Horn', -- Fallback sound name
            soundSet = 'DLC_HEIST_HACKING_SNAKE_SOUNDS' -- Fallback sound set
        },
        profiles = {
            -- Per-model acceleration / braking profiles.
            metrotrain = { accel = 0.26, decel = 5.0, brakeDecel = 5.0, maxSpeedKmh = 80.0 },
            freight = { accel = 0.20, decel = 0.45, brakeDecel = 5.0, maxSpeedKmh = 100.0 },
            default = { accel = 0.03, decel = 0.04, brakeDecel = 0.08, maxSpeedKmh = 80.0 }
        },
        trainApproach = {
            -- Automatic speed recommendation when approaching stops.
            freight = {
                enabled = true,
                approachDistFar = 180.0,
                approachDistNear = 70.0,
                maxSpeedFarKmh = 40.0,
                maxSpeedNearKmh = 24.0,
                allowThrottleOverride = true,
                throttleBrakeMultiplier = 0.45
            },
            metro = {
                enabled = true,
                approachDistFar = 140.0,
                approachDistNear = 45.0,
                maxSpeedFarKmh = 38.0,
                maxSpeedNearKmh = 18.0,
                allowThrottleOverride = true,
                throttleBrakeMultiplier = 0.45
            }
        }
    }

    -- Route blip / guidance settings.
    Config.RouteGuidance = {
        enabled = true, -- Show route guidance blips
        blipSprite = 280, -- Sprite used for route markers
        blipScale = 0.85, -- Marker scale
        blipShortRange = false, -- If true, only nearby route blips are visible
        blipAlphaUpcoming = 170, -- Transparency for upcoming stops
        blipAlphaDone = 120, -- Transparency for completed stops
        colors = {
            current = 5, -- Active current stop color
            upcoming = 3, -- Upcoming stop color
            done = 2, -- Completed stop color
            missed = 1 -- Missed stop color
        }
    }

    -- HUD editor settings.
    Config.UI = {
        hudEditor = {
            command = 'godhudedit', -- Command that opens HUD edit mode
            toggleCommand = 'godhud', -- Command that toggles HUD visibility
            copyCommand = 'godhudeditcopy', -- Command that copies current HUD layout config
            defaultLayout = {
                leftPct = 8.68541622161865, -- Default horizontal HUD position in percent
                topPct = 30.83333587646484, -- Default vertical HUD position in percent
                scale = 0.98000001907349 -- Default HUD scale
            },
            scale = {
                minPct = 75, -- Minimum HUD scale available in editor
                maxPct = 220, -- Maximum HUD scale available in editor
                stepPct = 1 -- Scale step used by the editor
            }
        }
    }

    Config.SpeedDisplay = {
        unit = 'kmh' -- Default speed unit shown in the HUD: kmh / mph
    }

    -- Common update intervals.
    Config.Performance = {
        idleWait = 1000, -- Main thread wait while idle
        activeWait = 100, -- Main thread wait while a route is active
        uiTickMs = 500, -- HUD update interval
        fuelTickMs = 1500 -- Fuel sync / refill interval
    }

    -- Internal runtime tuning for route systems.
    Config.Runtime = {
        metro = {
            clearReadyStageSpeed = 0.75, -- Speed threshold to clear metro "ready" stage
            derailGuard = {
                unstableForMs = 1200, -- Time above unsafe state before triggering derail guard
                notifyCooldownMs = 5000 -- Notification cooldown for derail warnings
            },
            offRouteRecoveryDelayMs = 2500, -- Delay before auto-recovering a metro back to route
            interiorPassengerModelTimeoutMs = 5000, -- Model request timeout for spawned metro passengers
            interiorPassengerCleanupDelayMs = 2500, -- Delay before cleaning interior passenger leftovers
            stationPassengerEnterMinTimeoutMs = 1500 -- Minimum enter timeout used for station passengers
        },
        hud = {
            cancelKeyLabel = '[G]' -- Label shown in the HUD for route cancel hold
        },
        notifications = {
            speedingWarningCooldownMs = 5000 -- Cooldown between overspeed warnings
        }
    }

    -- Teleport player to route vehicle when the route starts.
    Config.StartRouteTeleport = {
        train = {
            enabled = false -- Enable start teleport for freight routes
        },
        metro = {
            enabled = false -- Enable start teleport for metro routes
        }
    }

    -- Teleport player after early exit.
    Config.EarlyExitTeleport = {
        train = {
            mode = 'coords', -- Teleport mode: current / npc / coords
            coords = vec4(2615.0737, 1688.8826, 27.5996, 272.8787) -- Target teleport position
        },
        metro = {
            mode = 'coords', -- Teleport mode: current / npc / coords
            coords = vec4(-207.6975, -1017.9249, 30.1383, 158.4070) -- Target teleport position
        }
    }

    -- Progression persistence behavior.
    Config.Persistence = {
        sharedProgression = false, -- If true, metro and freight share one progression profile
        dbTableByType = {
            train = 'god_advanced_train_job_players_train', -- Database table for freight progression
            metro = 'god_advanced_train_job_players_metro' -- Database table for metro progression
        }
    }

    -- Basic anti-abuse limits.
    Config.Security = {
        eventCooldownMs = 900, -- Cooldown applied to sensitive client/server events
        maxStopDistance = 35.0, -- Max accepted stop validation distance
        maxRewardPerRoute = 25000 -- Hard cap for reward payout per route
    }
end
