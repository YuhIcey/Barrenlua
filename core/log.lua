local Log = {
    _VERSION = '1.0.0',
    _DESCRIPTION = 'Barren Engine Logging System'
}

-- Log levels
Log.Level = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    FATAL = 5
}

-- Level names for output
local LEVEL_NAMES = {
    [Log.Level.DEBUG] = "DEBUG",
    [Log.Level.INFO] = "INFO",
    [Log.Level.WARN] = "WARN",
    [Log.Level.ERROR] = "ERROR",
    [Log.Level.FATAL] = "FATAL"
}

-- ANSI color codes for different log levels
local COLORS = {
    [Log.Level.DEBUG] = "\27[36m", -- Cyan
    [Log.Level.INFO] = "\27[32m",  -- Green
    [Log.Level.WARN] = "\27[33m",  -- Yellow
    [Log.Level.ERROR] = "\27[31m", -- Red
    [Log.Level.FATAL] = "\27[35m", -- Magenta
    reset = "\27[0m"
}

-- Configuration
local config = {
    level = Log.Level.INFO,
    useColors = true,
    showTimestamp = true,
    showSource = true,
    outputs = {},
    format = nil
}

-- Default output to console
local function defaultOutput(level, message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local levelName = LEVEL_NAMES[level]
    local color = config.useColors and COLORS[level] or ""
    local reset = config.useColors and COLORS.reset or ""
    
    local parts = {}
    if config.showTimestamp then
        table.insert(parts, timestamp)
    end
    table.insert(parts, string.format("[%s%s%s]", color, levelName, reset))
    
    if config.showSource then
        local info = debug.getinfo(3, "Sl")
        if info then
            table.insert(parts, string.format("%s:%d", info.short_src, info.currentline))
        end
    end
    
    table.insert(parts, message)
    print(table.concat(parts, " "))
end

-- Add default console output
table.insert(config.outputs, defaultOutput)

-- Set configuration options
function Log.configure(options)
    for k, v in pairs(options) do
        config[k] = v
    end
end

-- Add a custom output
function Log.addOutput(callback)
    table.insert(config.outputs, callback)
end

-- Remove all outputs
function Log.clearOutputs()
    config.outputs = {}
end

-- Set minimum log level
function Log.setLevel(level)
    config.level = level
end

-- Internal logging function
local function log(level, message, ...)
    if level < config.level then return end
    
    -- Format message if arguments are provided
    if select('#', ...) > 0 then
        message = string.format(message, ...)
    end
    
    -- Apply custom format if provided
    if config.format then
        message = config.format(level, message)
    end
    
    -- Send to all outputs
    for _, output in ipairs(config.outputs) do
        output(level, message)
    end
end

-- Public logging functions
function Log.debug(message, ...)
    log(Log.Level.DEBUG, message, ...)
end

function Log.info(message, ...)
    log(Log.Level.INFO, message, ...)
end

function Log.warn(message, ...)
    log(Log.Level.WARN, message, ...)
end

function Log.error(message, ...)
    log(Log.Level.ERROR, message, ...)
end

function Log.fatal(message, ...)
    log(Log.Level.FATAL, message, ...)
end

-- Create a logger instance with a specific context
function Log.createLogger(context)
    local logger = {}
    
    local function contextLog(level, message, ...)
        if select('#', ...) > 0 then
            message = string.format(message, ...)
        end
        log(level, string.format("[%s] %s", context, message))
    end
    
    function logger.debug(message, ...)
        contextLog(Log.Level.DEBUG, message, ...)
    end
    
    function logger.info(message, ...)
        contextLog(Log.Level.INFO, message, ...)
    end
    
    function logger.warn(message, ...)
        contextLog(Log.Level.WARN, message, ...)
    end
    
    function logger.error(message, ...)
        contextLog(Log.Level.ERROR, message, ...)
    end
    
    function logger.fatal(message, ...)
        contextLog(Log.Level.FATAL, message, ...)
    end
    
    return logger
end

-- File output helper
function Log.addFileOutput(filename)
    local file = io.open(filename, "a")
    if not file then
        error(string.format("Could not open log file: %s", filename))
    end
    
    Log.addOutput(function(level, message)
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local levelName = LEVEL_NAMES[level]
        file:write(string.format("%s [%s] %s\n", timestamp, levelName, message))
        file:flush()
    end)
    
    return function()
        file:close()
    end
end

return Log 