return function(Config)
    -- Discord webhook integration.
    Config.Webhooks = Config.Webhooks or {
        enabled = false, -- Master webhook toggle
        all = '', -- Fallback webhook used when specific webhook is not set
        routeStart = '', -- Webhook for route start events
        routeFinish = '', -- Webhook for route finish events
        licenseBuy = '', -- Webhook for license / rank purchase events
        questClaim = '', -- Webhook for quest claim events
        username = 'God Train Job', -- Discord webhook sender name
        avatarUrl = '', -- Discord webhook avatar URL
        color = 5763719, -- Embed color
        footer = 'GOD TRAIN JOB' -- Embed footer text
    }
end
