return function(Config)
    -- Quest system root tables.
    Config.Quests = Config.Quests or {}
    Config.Quests.definitions = Config.Quests.definitions or {}

    -- Quest definitions.
    -- Fields:
    -- id = unique identifier
    -- enabled = master toggle for the quest
    -- period = reset period (daily / weekly)
    -- type = tracked metric (distance / stops / routes / accuracy)
    -- target = required value to complete the quest
    -- reward = money reward on claim
    -- routeType = all / train / metro
    -- label = short UI title
    -- description = detailed UI description
    Config.Quests.definitions = {
        { id = 'daily_distance_6', enabled = true, period = 'daily', type = 'distance', target = 6, reward = 350, routeType = 'all', label = 'Daily: Drive 6 km', description = 'Drive at least 6 km today.' },
        { id = 'daily_stops_12', enabled = true, period = 'daily', type = 'stops', target = 12, reward = 500, routeType = 'all', label = 'Daily: 12 valid stops', description = 'Complete at least 12 correct station stops today.' },
        { id = 'daily_routes_2', enabled = true, period = 'daily', type = 'routes', target = 2, reward = 650, routeType = 'all', label = 'Daily: Finish 2 routes', description = 'Complete 2 full routes in one day.' },
        { id = 'daily_distance_12', enabled = true, period = 'daily', type = 'distance', target = 12, reward = 900, routeType = 'all', label = 'Daily: Drive 12 km', description = 'Drive at least 12 km today.' },
        { id = 'daily_stops_20', enabled = true, period = 'daily', type = 'stops', target = 20, reward = 1050, routeType = 'all', label = 'Daily: 20 valid stops', description = 'Complete at least 20 correct station stops today.' },
        { id = 'daily_routes_3', enabled = true, period = 'daily', type = 'routes', target = 3, reward = 980, routeType = 'all', label = 'Daily: Finish 3 routes', description = 'Complete 3 full routes today.' },
        { id = 'daily_distance_18', enabled = true, period = 'daily', type = 'distance', target = 18, reward = 1350, routeType = 'all', label = 'Daily: Drive 18 km', description = 'Drive at least 18 km today.' },
        { id = 'daily_stops_28', enabled = true, period = 'daily', type = 'stops', target = 28, reward = 1450, routeType = 'all', label = 'Daily: 28 valid stops', description = 'Complete at least 28 correct station stops today.' },
        { id = 'daily_accuracy_90', enabled = true, period = 'daily', type = 'accuracy', target = 90, reward = 1200, routeType = 'all', label = 'Daily: 90% accuracy', description = 'Maintain at least 90% stop accuracy today.' },

        -- Daily (train)
        { id = 'daily_train_km_10', enabled = true, period = 'daily', type = 'distance', target = 10, reward = 800, routeType = 'train', label = 'Daily Train: 10 km', description = 'Drive train routes for at least 10 km today.' },
        { id = 'daily_train_stops_15', enabled = true, period = 'daily', type = 'stops', target = 15, reward = 900, routeType = 'train', label = 'Daily Train: 15 stops', description = 'Complete 15 valid train stops today.' },
        { id = 'daily_train_route_1', enabled = true, period = 'daily', type = 'routes', target = 1, reward = 550, routeType = 'train', label = 'Daily Train: 1 route', description = 'Finish at least 1 full train route today.' },
        { id = 'daily_train_km_16', enabled = true, period = 'daily', type = 'distance', target = 16, reward = 1250, routeType = 'train', label = 'Daily Train: 16 km', description = 'Drive train routes for at least 16 km today.' },
        { id = 'daily_train_stops_24', enabled = true, period = 'daily', type = 'stops', target = 24, reward = 1400, routeType = 'train', label = 'Daily Train: 24 stops', description = 'Complete 24 valid train stops today.' },
        { id = 'daily_train_routes_2', enabled = true, period = 'daily', type = 'routes', target = 2, reward = 1200, routeType = 'train', label = 'Daily Train: 2 routes', description = 'Complete 2 full train routes today.' },
        { id = 'daily_train_accuracy_92', enabled = true, period = 'daily', type = 'accuracy', target = 92, reward = 1350, routeType = 'train', label = 'Daily Train: 92% accuracy', description = 'Maintain at least 92% train stop accuracy today.' },

        -- Daily (metro)
        { id = 'daily_metro_km_9', enabled = true, period = 'daily', type = 'distance', target = 9, reward = 780, routeType = 'metro', label = 'Daily Metro: 9 km', description = 'Drive metro routes for at least 9 km today.' },
        { id = 'daily_metro_stops_16', enabled = true, period = 'daily', type = 'stops', target = 16, reward = 950, routeType = 'metro', label = 'Daily Metro: 16 stops', description = 'Complete 16 valid metro stops today.' },
        { id = 'daily_metro_route_1', enabled = true, period = 'daily', type = 'routes', target = 1, reward = 550, routeType = 'metro', label = 'Daily Metro: 1 route', description = 'Finish at least 1 full metro route today.' },
        { id = 'daily_metro_km_14', enabled = true, period = 'daily', type = 'distance', target = 14, reward = 1180, routeType = 'metro', label = 'Daily Metro: 14 km', description = 'Drive metro routes for at least 14 km today.' },
        { id = 'daily_metro_stops_26', enabled = true, period = 'daily', type = 'stops', target = 26, reward = 1380, routeType = 'metro', label = 'Daily Metro: 26 stops', description = 'Complete 26 valid metro stops today.' },
        { id = 'daily_metro_routes_2', enabled = true, period = 'daily', type = 'routes', target = 2, reward = 1220, routeType = 'metro', label = 'Daily Metro: 2 routes', description = 'Complete 2 full metro routes today.' },
        { id = 'daily_metro_accuracy_92', enabled = true, period = 'daily', type = 'accuracy', target = 92, reward = 1320, routeType = 'metro', label = 'Daily Metro: 92% accuracy', description = 'Maintain at least 92% metro stop accuracy today.' },

        -- Weekly (all)
        { id = 'weekly_routes_10', enabled = true, period = 'weekly', type = 'routes', target = 10, reward = 2500, routeType = 'all', label = 'Weekly: 10 routes', description = 'Finish 10 full routes this week.' },
        { id = 'weekly_accuracy_85', enabled = true, period = 'weekly', type = 'accuracy', target = 85, reward = 1800, routeType = 'all', label = 'Weekly: 85% accuracy', description = 'Reach or maintain at least 85% stop accuracy this week.' },
        { id = 'weekly_distance_50', enabled = true, period = 'weekly', type = 'distance', target = 50, reward = 3200, routeType = 'all', label = 'Weekly: 50 km total', description = 'Drive at least 50 km during the week.' },
        { id = 'weekly_stops_70', enabled = true, period = 'weekly', type = 'stops', target = 70, reward = 3600, routeType = 'all', label = 'Weekly: 70 valid stops', description = 'Complete 70 correct station stops this week.' },
        { id = 'weekly_distance_90', enabled = true, period = 'weekly', type = 'distance', target = 90, reward = 4700, routeType = 'all', label = 'Weekly: 90 km total', description = 'Drive at least 90 km during the week.' },
        { id = 'weekly_routes_15', enabled = true, period = 'weekly', type = 'routes', target = 15, reward = 5200, routeType = 'all', label = 'Weekly: 15 routes', description = 'Finish 15 full routes this week.' },
        { id = 'weekly_stops_120', enabled = true, period = 'weekly', type = 'stops', target = 120, reward = 5600, routeType = 'all', label = 'Weekly: 120 valid stops', description = 'Complete 120 correct station stops this week.' },
        { id = 'weekly_accuracy_92', enabled = true, period = 'weekly', type = 'accuracy', target = 92, reward = 4800, routeType = 'all', label = 'Weekly: 92% accuracy', description = 'Maintain at least 92% stop accuracy this week.' },
        { id = 'weekly_distance_130', enabled = true, period = 'weekly', type = 'distance', target = 130, reward = 6800, routeType = 'all', label = 'Weekly: 130 km total', description = 'Drive at least 130 km during the week.' },

        -- Weekly (train)
        { id = 'weekly_train_routes_6', enabled = true, period = 'weekly', type = 'routes', target = 6, reward = 2600, routeType = 'train', label = 'Weekly Train: 6 routes', description = 'Complete 6 full train routes this week.' },
        { id = 'weekly_train_distance_30', enabled = true, period = 'weekly', type = 'distance', target = 30, reward = 2400, routeType = 'train', label = 'Weekly Train: 30 km', description = 'Drive 30 km on train routes this week.' },
        { id = 'weekly_train_stops_80', enabled = true, period = 'weekly', type = 'stops', target = 80, reward = 4300, routeType = 'train', label = 'Weekly Train: 80 stops', description = 'Complete 80 valid train stops this week.' },
        { id = 'weekly_train_routes_10', enabled = true, period = 'weekly', type = 'routes', target = 10, reward = 5200, routeType = 'train', label = 'Weekly Train: 10 routes', description = 'Complete 10 full train routes this week.' },
        { id = 'weekly_train_distance_65', enabled = true, period = 'weekly', type = 'distance', target = 65, reward = 5000, routeType = 'train', label = 'Weekly Train: 65 km', description = 'Drive 65 km on train routes this week.' },
        { id = 'weekly_train_accuracy_93', enabled = true, period = 'weekly', type = 'accuracy', target = 93, reward = 5400, routeType = 'train', label = 'Weekly Train: 93% accuracy', description = 'Maintain at least 93% train stop accuracy this week.' },

        -- Weekly (metro)
        { id = 'weekly_metro_routes_6', enabled = true, period = 'weekly', type = 'routes', target = 6, reward = 2600, routeType = 'metro', label = 'Weekly Metro: 6 routes', description = 'Complete 6 full metro routes this week.' },
        { id = 'weekly_metro_stops_40', enabled = true, period = 'weekly', type = 'stops', target = 40, reward = 2300, routeType = 'metro', label = 'Weekly Metro: 40 stops', description = 'Complete 40 valid metro stops this week.' },
        { id = 'weekly_metro_stops_85', enabled = true, period = 'weekly', type = 'stops', target = 85, reward = 4400, routeType = 'metro', label = 'Weekly Metro: 85 stops', description = 'Complete 85 valid metro stops this week.' },
        { id = 'weekly_metro_routes_10', enabled = true, period = 'weekly', type = 'routes', target = 10, reward = 5200, routeType = 'metro', label = 'Weekly Metro: 10 routes', description = 'Complete 10 full metro routes this week.' },
        { id = 'weekly_metro_distance_60', enabled = true, period = 'weekly', type = 'distance', target = 60, reward = 4950, routeType = 'metro', label = 'Weekly Metro: 60 km', description = 'Drive 60 km on metro routes this week.' },
        { id = 'weekly_metro_accuracy_93', enabled = true, period = 'weekly', type = 'accuracy', target = 93, reward = 5350, routeType = 'metro', label = 'Weekly Metro: 93% accuracy', description = 'Maintain at least 93% metro stop accuracy this week.' }
    }
end
