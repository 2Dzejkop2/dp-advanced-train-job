return function(Config)
    -- Metro route / station registry.
    Config.Stations = Config.Stations or {} -- Shared compatibility map for all stations
    Config.StationsMetro = Config.StationsMetro or {} -- Metro-only station table
    Config.Routes = Config.Routes or {} -- Route registry
    Config.Vehicle = Config.Vehicle or {} -- Vehicle config root
    Config.Vehicle.types = Config.Vehicle.types or {} -- Vehicle profiles by route type
    Config.MetroStopZone = Config.MetroStopZone or {
        size = vec3(3.0, 55.0, 0.5), -- Default metro station stop box size
        markerType = 43, -- Default stop marker type
        debugAlwaysVisible = false, -- Show stop zones even without an active job
        toleranceZ = 20.0 -- Vertical tolerance for stop-box detection
    }

    -- Registers one metro station into both metro and shared station maps.
    local function addStation(id, data)
        Config.StationsMetro[id] = data
        Config.Stations[id] = data
    end

    -- Editable metro station definitions.
    local metroStops = {
        {
            id = 1,
            label = 'Little Seoul',
            coords = vec3(-492.3230, -680.6787, 10.2729),
            heading = 90.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-502.5980, -676.8342, 12.8090, 92.5079), -- Raised Z slightly to improve spawn placement
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 90.2 } -- Enlarged NPC box for better spawn coverage
            }
        },
        {
            id = 2,
            label = 'Del Perro',
            coords = vec3(-1358.7217, -468.2133, 13.5039),
            heading = 30.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-1355.6060, -465.3873, 16.0453, 28.7941),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 30.2 }
            }
        },
        {
            id = 3,
            label = 'Portola Drive',
            coords = vec3(-820.8860, -132.1421, 18.4123),
            heading = 300.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-816.4774, -133.9969, 20.9503, 300.0),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 300.2 }
            }
        },
        {
            id = 4,
            label = 'Trains Southbound',
            coords = vec3(-287.0001, -328.6383, 8.5243),
            heading = 180.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-290.9195, -331.7801, 11.0631, 184.0459),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 180.2 }
            }
        },

        {
            id = 5,
            label = 'Strawberry',
            coords = vec3(258.7029, -1210.0177, 38.0746),
            heading = 270.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(278.0801, -1205.5264, 39.8929, 87.2100),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 87.2100 }
            }
        },
        
        {
            id = 6,
            label = 'Puerto del Sol',
            coords = vec3(-536.2538, -1283.8483, 25.2489),
            heading = 155.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-539.4630, -1283.3956, 27.9016, 153.6230),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 155.2 },
                count = 4 -- Higher passenger count for testing and realism
            }
        },
        {
            id = 7,
            label = 'LSIA Parking',
            coords = vec3(-879.5950, -2330.6938, -13.2650),
            heading = 160.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-878.7119, -2316.9966, -10.7328, 159.9484),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 160.2 },
                count = 5 -- Higher passenger count for realism
            }
        },
        {
            id = 8,
            label = 'LSIA Terminal 4',
            coords = vec3(-1077.3441, -2720.4697, -8.9490),
            heading = 140.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-1082.8639, -2720.9353, -6.4101, 138.6654),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 140.2 }
            }
        },
        {
            id = 9,
            label = 'LSIA Terminal 4',
            coords = vec3(-1088.1038, -2709.4800, -8.9487),
            heading = 320.0,
            stopRadius = 18.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-1088.7336, -2716.3752, -6.4101, 321.3890),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 320.2 }
            }
        },
        {
            id = 10,
            label = 'LSIA Parking',
            coords = vec3(-890.0097, -2316.0789, -13.2700),
            heading = 340.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-885.6947, -2314.6577, -10.7328, 339.9399),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 340.2 },
                count = 4 -- Higher passenger count for realism and interaction testing
            }
        },
        {
            id = 11,
            label = 'Puerto del Sol',
            coords = vec3(-546.5624, -1284.3673, 25.2542),
            heading = 335.4910,
            npc = {
                enabled = true,
                spawnCoords = vec4(-541.9984, -1282.1934, 27.9016, 153.3840),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 155.2 },
                count = 4 -- Higher passenger count for realism and interaction testing
            }
        },
        {
            id = 12,
            label = 'Strawberry',
            coords = vec3(281.0489, -1198.4497, 37.4246),
            heading = 270.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(278.0106, -1203.0776, 39.8928, 87.5426),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 90.2 }
            }
        },
        {
            id = 13,
            label = 'Burton',
            coords = vec3(-302.1180, -327.7780, 8.5246),
            heading = 0.0520,
            npc = {
                enabled = true,
                spawnCoords = vec4(-298.3206, -332.1340, 11.0631, 357.0806),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 360.2 }
            }
        },
        {
            id = 14,
            label = 'Portola Drive',
            coords = vec3(-815.8372, -146.4498, 18.4133),
            heading = 120.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-812.5333, -140.3324, 20.9503, 117.8039),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 298.8089 }
            }
        },
        {
            id = 15,
            label = 'Del Perro',
            coords = vec3(-1343.9822, -462.9101, 13.5060),
            heading = 210.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-1349.2661, -461.4722, 16.0453, 211.4823),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 210.4823 }
            }
        },
        {
            id = 16,
            label = 'Little Seoul',
            coords = vec3(-501.6283, -665.5609, 10.2676),
            heading = 270.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-502.8584, -669.4097, 12.8090, 270.4114),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 270.4114 }
            }
        },
        {
            id = 17,
            label = 'Pillbox South',
            coords = vec3(-209.0652, -1035.3545, 28.6697),
            heading = 160.0,
            npc = {
                enabled = true,
                spawnCoords = vec4(-210.2463, -1027.3575, 31.1389, 155.7847),
                boxZone = { size = vec3(6.0, 30.0, 6.0), heading = 160.7847 }
            }
        },
    }

    -- Builds route station order from the editable metro stop list.
    local function buildStationOrderFromStops(stops)
        local order = {}
        for _, stop in ipairs(stops or {}) do
            if stop and stop.id then
                order[#order + 1] = stop.id
            end
        end
        return order
    end

    for _, stop in ipairs(metroStops) do
        addStation(stop.id, {
            label = stop.label,
            coords = stop.coords,
            heading = stop.heading,
            stopRadius = tonumber(stop.stopRadius) or 12.0,
            allowedTime = 45,
            stopBox = Config.MetroStopZone.size,
            zoneMarkerType = Config.MetroStopZone.markerType,
            npc = stop.npc
        })
    end

    -- Metro route definitions.
    Config.Routes[2] = {
        label = 'Metro Loop A',
        trainType = 'metro',
        stationOrder = buildStationOrderFromStops(metroStops),
        spawn = vec4(-203.9725, -993.5885, 29.0388, 337.3227),
        targetKm = 8.2,
        baseReward = 1350
    }

    -- Vehicle profile used for metro routes.
    Config.Vehicle.types.metro = {
        model = 'metrotrain', -- Spawned metro train model
        requiredModel = 'metrotrain', -- Required lead vehicle model
        requiredCarriageModel = nil, -- Optional required carriage model
        requiredMinCarriages = 0, -- Minimum required carriage count
        allowShortConsist = true, -- Allow route to continue with fewer carriages
        saltySpawnStyle = false, -- Reserved compatibility flag for SaltyTrain style spawning
        useMissionTrain = true, -- Use mission train natives for spawning
        missionTrainDirection = false, -- Mission train direction flag
        missionVariations = { 28, 26, 24, 23, 4, 21 }, -- Allowed train variations
        rearAttachedModel = nil, -- Optional rear attached carriage model
        forceRearAttached = false, -- Force spawning an attached rear vehicle
        rearAttachOffset = {
            x = 0.0, -- Rear attachment X offset
            y = -11.2, -- Rear attachment Y offset
            z = 0.0, -- Rear attachment Z offset
            pitch = 0.0, -- Rear attachment pitch offset
            roll = 0.0, -- Rear attachment roll offset
            yaw = 180.0 -- Rear attachment yaw offset
        },
        warpIntoVehicle = true -- Warp player into the metro after spawn

        }

Config.ForceRightSideBoarding = true -- Force station boarding logic to prefer the right side of the train

end
