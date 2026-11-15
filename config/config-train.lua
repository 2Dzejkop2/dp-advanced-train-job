return function(Config)
    -- Freight route / station registry.
    Config.Stations = Config.Stations or {} -- Shared compatibility map for all stations
    Config.StationsTrain = Config.StationsTrain or {} -- Freight-only station table
    Config.Routes = Config.Routes or {} -- Route registry
    Config.Vehicle = Config.Vehicle or {} -- Vehicle config root
    Config.Vehicle.types = Config.Vehicle.types or {} -- Vehicle profiles by route type
    Config.TrainStopZone = Config.TrainStopZone or {
        size = vec3(5.0, 25.0, 0.5), -- Default freight station stop box size
        markerType = 43, -- Default stop marker type
        debugAlwaysVisible = false, -- Show stop zones even without an active job
        toleranceZ = 20.0 -- Vertical tolerance for stop-box detection
    }

    -- Registers one freight station into both freight and shared station maps.
    local function addStation(id, data)
        if Config.TrainStopZone and data then
            data.stopBox = data.stopBox or Config.TrainStopZone.size
            data.zoneMarkerType = data.zoneMarkerType or Config.TrainStopZone.markerType
            data.stopBoxToleranceZ = data.stopBoxToleranceZ or Config.TrainStopZone.toleranceZ
        end
        Config.StationsTrain[id] = data
        Config.Stations[id] = data
    end

    -- Editable freight station definitions.
    local freightStops = {
        {
            id = 1,
            label = 'Iron Mines',
            coords = vec3(2612.4163, 2930.6208, 39.8856),
            heading = 324.1794,
            npc = { enabled = false }
        },
        {
            id = 2,
            label = 'Paleto Bay',
            coords = vec3(-139.8481, 6142.5410, 31.5772),
            heading = 135.0,
            npc = { enabled = false }
        },
        {
            id = 3,
            label = 'Iron Mines',
            coords = vec3(2607.4248, 2934.0396, 40.0196),
            heading = 144.0,
            npc = { enabled = false }
        },
        {
            id = 4,
            label = 'Mirror Park',
            coords = vec3(664.5507, -898.7147, 22.2379),
            heading = 0.0,
            npc = { enabled = false }
        },
        {
            id = 5,
            label = 'Industrial Zone',
            coords = vec3(217.4654, -2498.7051, 5.7798),
            heading = 180.0,
            npc = { enabled = false }
        },
        {
            id = 6,
            label = 'Freight Depot Return',
            coords = vec3(2611.0864, 1697.2126, 26.8106),
            heading = 359.0959,
            npc = { enabled = false }
        }
    }

    -- Builds route station order from the editable freight stop list.
    local function buildStationOrderFromStops(stops)
        local order = {}
        for _, stop in ipairs(stops or {}) do
            if stop and stop.id then
                order[#order + 1] = stop.id
            end
        end
        return order
    end

    for _, stop in ipairs(freightStops) do
        addStation(stop.id, {
            label = stop.label,
            coords = stop.coords,
            heading = stop.heading,
            stopRadius = 12.0,
            allowedTime = 45 + 600, -- Extended by 10 minutes for this stop
            stopBox = stop.stopBox or Config.TrainStopZone.size,
            zoneMarkerType = Config.TrainStopZone.markerType,
            stopBoxToleranceZ = Config.TrainStopZone.toleranceZ,
            isSkipping = stop.isSkipping == true,
            newMaxSpeed = stop.newMaxSpeed,
            npc = stop.npc
        })
    end

    -- Freight route definitions.
    Config.Routes[1] = {
        label = 'Freight Supply Line',
        trainType = 'freight',
        stationOrder = buildStationOrderFromStops(freightStops),
        spawn = vec4(2611.0864, 1697.2126, 26.8106, 195.7702),
        targetKm = 6.5,
        baseReward = 900
    }

    -- Vehicle profile used for freight routes.
    Config.Vehicle.types.freight = {
        model = 'freight', -- Spawned freight train model
        requiredModel = 'freight', -- Required lead vehicle model
        requiredCarriageModel = 'freightcar', -- Required carriage model
        useMissionTrain = true, -- Use mission train natives for spawning
        missionTrainDirection = false, -- Mission train direction flag
        missionVariations = { 5 }, -- Allowed train variations
        requiredMaxCarriages = 6, -- Max supported carriage count
        requiredMatchingCarriages = 5, -- Required count of matching carriages
        warpIntoVehicle = true -- Warp player into the train after spawn
    }
end
