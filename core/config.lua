local Config = {
    _VERSION = '1.0.0',
    _DESCRIPTION = 'Barren Engine Configuration System'
}

local json = require('cjson')
local Event = require('core.event')

-- Internal storage
local config = {}
local defaults = {}
local validators = {}
local watchers = {}

-- Event names
local EVENTS = {
    CHANGED = 'config:changed',
    LOADED = 'config:loaded',
    ERROR = 'config:error'
}

-- Helper function to deep copy tables
local function deepCopy(t)
    if type(t) ~= 'table' then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = type(v) == 'table' and deepCopy(v) or v
    end
    return copy
end

-- Helper function to merge tables
local function merge(target, source)
    for k, v in pairs(source) do
        if type(v) == 'table' and type(target[k]) == 'table' then
            merge(target[k], v)
        else
            target[k] = deepCopy(v)
        end
    end
    return target
end

-- Helper function to get nested value
local function get(t, path)
    local current = t
    for key in string.gmatch(path, "[^%.]+") do
        if type(current) ~= 'table' then return nil end
        current = current[key]
    end
    return current
end

-- Helper function to set nested value
local function set(t, path, value)
    local current = t
    local keys = {}
    for key in string.gmatch(path, "[^%.]+") do
        table.insert(keys, key)
    end
    
    for i = 1, #keys - 1 do
        local key = keys[i]
        current[key] = current[key] or {}
        current = current[key]
    end
    
    current[keys[#keys]] = value
end

-- Set default values
function Config.setDefaults(defaults_)
    defaults = deepCopy(defaults_)
    config = deepCopy(defaults)
    Event.emit(EVENTS.CHANGED, config)
end

-- Register a validator for a config path
function Config.addValidator(path, validator)
    validators[path] = validator
end

-- Watch for changes on a specific path
function Config.watch(path, callback)
    watchers[path] = watchers[path] or {}
    table.insert(watchers[path], callback)
end

-- Load configuration from a JSON file
function Config.loadFile(filename)
    local file = io.open(filename, "r")
    if not file then
        Event.emit(EVENTS.ERROR, string.format("Could not open config file: %s", filename))
        return false
    end
    
    local content = file:read("*a")
    file:close()
    
    local success, data = pcall(json.decode, content)
    if not success then
        Event.emit(EVENTS.ERROR, string.format("Invalid JSON in config file: %s", filename))
        return false
    end
    
    merge(config, data)
    Event.emit(EVENTS.LOADED, filename)
    Event.emit(EVENTS.CHANGED, config)
    return true
end

-- Save configuration to a JSON file
function Config.saveFile(filename)
    local file = io.open(filename, "w")
    if not file then
        Event.emit(EVENTS.ERROR, string.format("Could not open config file for writing: %s", filename))
        return false
    end
    
    local success, content = pcall(json.encode, config)
    if not success then
        Event.emit(EVENTS.ERROR, "Failed to encode config as JSON")
        file:close()
        return false
    end
    
    file:write(content)
    file:close()
    return true
end

-- Load configuration from environment variables
function Config.loadEnv(prefix)
    prefix = prefix or "BARREN_"
    for name, value in pairs(os.environ()) do
        if string.sub(name, 1, #prefix) == prefix then
            local path = string.sub(name, #prefix + 1):lower():gsub("_", ".")
            Config.set(path, value)
        end
    end
end

-- Get a configuration value
function Config.get(path, default)
    local value = get(config, path)
    if value == nil then
        return default
    end
    return deepCopy(value)
end

-- Set a configuration value
function Config.set(path, value)
    -- Check validator if exists
    if validators[path] then
        local valid, err = validators[path](value)
        if not valid then
            Event.emit(EVENTS.ERROR, string.format("Invalid value for %s: %s", path, err))
            return false
        end
    end
    
    local oldValue = get(config, path)
    if oldValue ~= value then
        set(config, path, deepCopy(value))
        
        -- Notify watchers
        if watchers[path] then
            for _, callback in ipairs(watchers[path]) do
                callback(value, oldValue)
            end
        end
        
        Event.emit(EVENTS.CHANGED, config)
    end
    return true
end

-- Reset configuration to defaults
function Config.reset()
    config = deepCopy(defaults)
    Event.emit(EVENTS.CHANGED, config)
end

-- Get all configuration
function Config.getAll()
    return deepCopy(config)
end

-- Parse command line arguments
function Config.parseArgs(args)
    local i = 1
    while i <= #args do
        local arg = args[i]
        if string.sub(arg, 1, 2) == "--" then
            local path = string.sub(arg, 3):gsub("-", ".")
            
            if i < #args and string.sub(args[i + 1], 1, 1) ~= "-" then
                -- Handle --key value
                Config.set(path, args[i + 1])
                i = i + 2
            else
                -- Handle --flag
                Config.set(path, true)
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

return Config 