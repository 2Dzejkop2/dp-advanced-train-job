return function(Config)
    -- Marker visuals for stop zones.
    Config.Marker = {
        alpha = 140, -- Marker transparency
        boxZOffset = 0.03, -- Vertical offset for box markers
        circleZOffset = -1.2, -- Vertical offset for circle markers
        hysteresis = 0.45, -- Buffer to prevent flickering in/out of zone state
        insideColor = { r = 0, g = 255, b = 120 }, -- Marker color while inside the stop zone
        outsideColor = { r = 255, g = 60, b = 60 } -- Marker color while outside the stop zone
    }

    -- Small input-related boarding settings.
    Config.Boarding = {
        inputCooldownMs = 900 -- Delay before the stop confirm key can be used again (increased to prevent spam)
    }

    -- Early finish / cancel route behavior.
    Config.EarlyFinish = {
        metro = {
            normalAllowedAfterCompletedStops = 4, -- Stops required before normal early finish is allowed
            allowNoRewardBeforeThreshold = true, -- Allow early finish before threshold with no reward
            noRewardConfirmWindowMs = 8000, -- Confirm-again window for no-reward exit
            holdToCancelMs = 5000, -- Hold duration needed to trigger cancel
            instantHoldFinish = false, -- Skip confirmation and finish immediately on hold
            forceNoRewardOnHold = true -- Force no-reward finish if canceled by hold
        },
        freight = {
            normalAllowedAfterCompletedStops = 0,
            allowNoRewardBeforeThreshold = false,
            noRewardConfirmWindowMs = 8000,
            holdToCancelMs = 5000,
            instantHoldFinish = false,
            forceNoRewardOnHold = true
        }
    }

    -- Snap train to station stop point after confirmation.
    Config.StopSnap = {
        enabled = true, -- Enable stop snapping
        maxSnapDistance = 30.0, -- Max allowed distance for a snap to occur
        metro = {
            enabled = true, -- Enable snap logic for metro
            snapOnConfirm = true, -- Apply stop confirmation handling for metro
            teleportOnConfirm = false -- Do not teleport the train on confirm; prevents camera flicker
        },
        freight = {
            enabled = true,
            snapOnConfirm = true,
            teleportOnConfirm = false -- Do not teleport the freight train on confirm; prevents camera flicker
        }
    }

    -- Generic NPC spawn settings used for stations and ambience.
    Config.NPC = {
        enabled = true, -- Master NPC system toggle
        spawnZOffset = -1.0, -- Vertical adjustment applied on spawn
        densityMode = 'medium', -- NPC density profile: low/medium/high
        densityByMode = { low = 2, medium = 5, high = 8 }, -- Default freight / generic density values
        metroDensityByMode = { low = 2, medium = 5, high = 8 }, -- Metro-specific density values
        spawnAttempts = 12, -- Random point attempts before giving up on a spawn
        boxPadding = 0.3, -- Safe padding inside station NPC box zones
        useGroundZ = true, -- Try to place NPCs on detected ground Z
        randomHeading = true, -- Give spawned NPCs random facing
        debug = {
            enabled = false, -- Draw debug visuals for station NPC zones
            onlyClosest = false, -- Only draw the nearest debug zone
            showCenter = false, -- Show zone center marker
            alpha = 110, -- Debug draw transparency
            nearColor = { r = 0, g = 200, b = 255 }, -- Color used for nearby debug zones
            farColor = { r = 255, g = 140, b = 60 }, -- Color used for distant debug zones
            drawDistance = 220.0 -- Max debug draw distance
        },
        models = {
            -- Ped models used for station passengers.
            'a_m_m_business_01',
            'a_f_y_business_01',
            'a_m_y_beach_01',
            'a_f_y_tourist_01'
        },
        behavior = 'idle', -- Default behavior for spawned station NPCs: idle/wander
        exitCleanup = {
            distance = 26.0, -- Delete exiting NPC after it moves far enough away
            stillTicks = 12, -- Delete exiting NPC if it stays almost still for too long
            maxLifetimeMs = 32000, -- Max life for exiting NPC after leaving the train
            stuckInVehicleMs = 14000 -- Delete exiting NPC if it remains inside a vehicle too long
        }
    }

    -- Metro passenger boarding / exit behavior.
    Config.PassengerBoarding = {
        enabled = true, -- Enable living metro passengers
        simpleSeatBoarding = true, -- Walk to the train, then warp onto assigned seats once inside
        autoStartMetroBoarding = false, -- Require a manual [E] stop confirm before metro boarding starts
        spawnNearMetro = true, -- Spawn waiting passengers along the platform side near real door lanes
        lockTrainWhileBoarding = true, -- Prevent departure while passengers are moving
        durationMs = 14500, -- Base stop dwell used for the boarding stage
        durationPerPassengerMs = 720, -- Extra dwell time added per active passenger movement
        maxDurationMs = 30000, -- Hard cap for one boarding stage
        cooldownMs = 1200, -- Cooldown before another stop service can begin
        minPassengers = 4, -- Minimum boarding demand at a stop
        maxPassengers = 12, -- Maximum boarding demand at a stop
        seatedCapacityPerCarriage = 4, -- Hard seated capacity used for each metro carriage
        boardingSideSign = -1.0, -- Keep boarding and exit on the platform-side doors only
        approachSpeed = 1.05, -- Walking speed for boarding / exiting passengers
        queueSpacing = 0.9, -- Spacing between queued NPCs on the same door lane
        queueDepth = 1.5, -- Depth of the queue from the train side
        stagingDepth = 3.2, -- Initial spawn / staging depth from the carriage side
        doorOffset = 1.45, -- Door lane offset from carriage center
        laneOffsets = { -5.8, 0.0, 5.8 }, -- Door lanes distributed along each carriage
        boardDistance = 1.2, -- Distance that counts as reaching the door
        boardFallbackEnterMs = 1700, -- Max time before a boarding ped is snapped just inside
        repathIntervalMs = 450, -- How often the door approach task is refreshed
        maxQueuePerDoor = 4, -- Max number of NPCs assigned to one door lane
        exitDwellMs = 1000, -- Small exit-first pause before new passengers start boarding
        doorSnapDistance = 1.2, -- Snap threshold for final door alignment
        doorPauseMs = 260, -- Short pause just inside the train before seat warp
        seatWarpDelayMinMs = 220, -- Minimum random delay before seat warp
        seatWarpDelayMaxMs = 650, -- Maximum random delay before seat warp
        targetOccupancyMin = 0.42, -- Lower occupancy band targeted between stations
        targetOccupancyMax = 0.78, -- Upper occupancy band targeted between stations
        minExitRatio = 0.06, -- Minimum share of onboard passengers that may exit
        maxExitRatio = 0.24, -- Maximum share of onboard passengers that may exit
        forceExitOccupancyThreshold = 0.82, -- Force at least one exit above this occupancy
        exitWalkOutMs = 2400, -- Time exiting NPCs keep walking away from the train
        exitDeleteDelayMs = 12000, -- Hard cleanup timeout for exited NPCs
        stuckNpcCleanupEnabled = true, -- Periodic cleanup for broken or stranded train NPCs
        stuckNpcCleanupIntervalMs = 3500, -- Cleanup cadence while the route is running
        stuckNpcCleanupDuringBoarding = false, -- Avoid aggressive cleanup while active boarding is in progress
        stuckNpcCleanupRadius = 85.0, -- Cleanup radius around the active train
        debug = {
            enabled = false, -- Verbose passenger boarding debug logs
            notify = false -- Optional on-screen debug notifications
        }
    }

    -- Rush hour multipliers.
    Config.RushHour = {
        enabled = true, -- Enable time-based passenger / fare multipliers
        morning = { startHour = 6, endHour = 9, passengerMultiplier = 1.8, fareMultiplier = 1.35 }, -- Morning rush profile
        evening = { startHour = 16, endHour = 19, passengerMultiplier = 1.7, fareMultiplier = 1.3 } -- Evening rush profile
    }

    -- Per-route-type penalties, speed rules and freight extras.
    Config.RouteRules = {
        freight = {
            latePenaltyPerMinute = 60, -- Penalty growth per late minute
            speedPenaltyPerSecond = 4, -- Penalty added per second of overspeeding
            hardBrakeDeltaKmh = 16, -- Speed drop threshold treated as hard braking
            hardBrakePenalty = 70, -- Penalty per hard brake event
            derailRiskPenalty = 220, -- Penalty per derail-risk event
            timeLimitMin = 30, -- Expected route completion time
            speedingToleranceKmh = 8, -- Legacy overspeed tolerance in km/h
            speedingTolerance = 8, -- Overspeed tolerance in display unit or explicit unit below
            speedingToleranceUnit = 'display', -- Unit used by speedingTolerance: display / kmh / mph
            stationArrivalSpeedLimit = 60, -- Required speed limit while entering a station
            stationArrivalSpeedUnit = 'kmh', -- Unit used by stationArrivalSpeedLimit
            stationArrivalSpeedPenalty = 120, -- Penalty if arrival speed exceeds station limit
            stationArrivalSpeedTriggerDistance = 28.0, -- Distance where arrival speed is checked
            stationApproachAutoBrakeDistance = 130.0, -- Distance where station approach limit becomes active
            stationApproachReleaseDistance = 170.0, -- Distance where station approach limit clears again
            citySpeedLimitKmh = 80, -- City-zone recommended speed limit
            cityMaxSpeedKmh = 100, -- Hard max speed shown / enforced by route logic
            cityZones = {
                -- Circular city speed zones.
                { center = vec3(215.0, -910.0, 30.0), radius = 1850.0 },
                { center = vec3(1843.6449, 3723.4150, 33.1471), radius = 500.0 },
                { center = vec3(-172.2540, 6363.0361, 31.5263), radius = 700.0 }
            },
            containerProps = {
                enabled = true, -- Show freight containers visually
                modelStation = 'prop_container_05a', -- Prop model used at station loading area
                model = 'prop_container_01a', -- Prop model attached to train
                maxVisible = 5, -- Max visible container props
                attachToCarriages = true, -- Attach container props to freight carriages
                carriageModel = 'freightcar', -- Carriage model that can receive containers
                carriageOffset = vec3(0.0, 1.0, -0.2), -- Base offset used when attaching props
                offsets = {
                    -- Attachment offsets for each visible container slot.
                    vec3(0.0, -8.5, 0.1),
                    vec3(0.0, -17.0, 0.1),
                    vec3(0.0, -25.5, 0.1),
                    vec3(0.0, -34.0, 0.1),
                    vec3(0.0, -42.5, 0.1)
                }
            }
        },
        metro = {
            latePenaltyPerMinute = 35, -- Penalty growth per late minute
            speedPenaltyPerSecond = 2, -- Penalty added per second of overspeeding
            hardBrakeDeltaKmh = 14, -- Speed drop threshold treated as hard braking
            hardBrakePenalty = 45, -- Penalty per hard brake event
            derailRiskPenalty = 160, -- Penalty per derail-risk event
            speedingToleranceKmh = 8, -- Legacy overspeed tolerance in km/h
            speedingTolerance = 8, -- Overspeed tolerance in display unit or explicit unit below
            speedingToleranceUnit = 'display', -- Unit used by speedingTolerance: display / kmh / mph
            stationArrivalSpeedLimit = 60, -- Required speed limit while entering a station
            stationArrivalSpeedUnit = 'kmh', -- Unit used by stationArrivalSpeedLimit
            stationArrivalSpeedPenalty = 85, -- Penalty if arrival speed exceeds station limit
            stationArrivalSpeedTriggerDistance = 28.0, -- Distance where arrival speed is checked
            stationApproachAutoBrakeDistance = 130.0, -- Distance where station approach limit becomes active
            stationApproachReleaseDistance = 170.0, -- Distance where station approach limit clears again
            citySpeedLimitKmh = 64, -- City-zone recommended speed limit
            cityZones = {
                --[[            
                { center = vec3(215.0, -910.0, 30.0), radius = 1850.0 },
                { center = vec3(1843.6449, 3723.4150, 33.1471), radius = 500.0 },
                 center = vec3(-172.2540, 6363.0361, 31.5263), radius = 700.0 }
                ]]
            },
            timeLimitMin = 25 -- Expected route completion time
        }
    }
end
