Locales = {}

local currentLocale = nil

local function applyLocale(locale)
    local localeData = Locales[locale] or {}
    local enData = Locales.en or {}
    setmetatable(localeData, {
        __index = function(_, k)
            local enValue = enData[k]
            if enValue ~= nil then
                return enValue
            end
            return ('missing_locale:%s'):format(k)
        end
    })
    Locales.current = localeData
    currentLocale = locale
end

function _L(key, ...)
    local locale = Config.Locale or 'en'
    if currentLocale ~= locale or not Locales.current then
        applyLocale(locale)
    end

    local text = Locales.current[key] or key
    local args = { ... }
    if #args > 0 then
        return text:format(table.unpack(args))
    end
    return text
end
