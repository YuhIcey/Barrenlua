local Utils = {
    _VERSION = '1.0.0',
    _DESCRIPTION = 'Barren Engine Utility Library'
}

-- UUID generation
local function generateUUID()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = c == 'x' and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

Utils.generateUUID = generateUUID

-- Table utilities
Utils.table = {
    -- Deep copy a table
    deepCopy = function(t)
        if type(t) ~= 'table' then return t end
        local copy = {}
        for k, v in pairs(t) do
            copy[k] = type(v) == 'table' and Utils.table.deepCopy(v) or v
        end
        return copy
    end,
    
    -- Merge two tables
    merge = function(t1, t2)
        for k, v in pairs(t2) do
            if type(v) == 'table' and type(t1[k]) == 'table' then
                Utils.table.merge(t1[k], v)
            else
                t1[k] = v
            end
        end
        return t1
    end,
    
    -- Check if table is empty
    isEmpty = function(t)
        return next(t) == nil
    end,
    
    -- Get table length (including non-numeric keys)
    length = function(t)
        local count = 0
        for _ in pairs(t) do count = count + 1 end
        return count
    end,
    
    -- Find value in table
    find = function(t, value)
        for k, v in pairs(t) do
            if v == value then return k end
        end
        return nil
    end,
    
    -- Filter table
    filter = function(t, predicate)
        local result = {}
        for k, v in pairs(t) do
            if predicate(v, k, t) then
                result[k] = v
            end
        end
        return result
    end,
    
    -- Map table values
    map = function(t, fn)
        local result = {}
        for k, v in pairs(t) do
            result[k] = fn(v, k, t)
        end
        return result
    end,
    
    -- Reduce table
    reduce = function(t, fn, initial)
        local acc = initial
        for k, v in pairs(t) do
            if acc == nil and initial == nil then
                acc = v
            else
                acc = fn(acc, v, k, t)
            end
        end
        return acc
    end
}

-- String utilities
Utils.string = {
    -- Split string by delimiter
    split = function(str, delimiter)
        local result = {}
        local pattern = string.format("([^%s]+)", delimiter)
        for match in string.gmatch(str, pattern) do
            table.insert(result, match)
        end
        return result
    end,
    
    -- Trim whitespace
    trim = function(str)
        return string.match(str, "^%s*(.-)%s*$")
    end,
    
    -- Start with prefix
    startsWith = function(str, prefix)
        return string.sub(str, 1, #prefix) == prefix
    end,
    
    -- End with suffix
    endsWith = function(str, suffix)
        return suffix == "" or string.sub(str, -#suffix) == suffix
    end,
    
    -- Pad string
    pad = function(str, length, char)
        char = char or " "
        if #str >= length then return str end
        return str .. string.rep(char, length - #str)
    end,
    
    -- Convert to camelCase
    camelCase = function(str)
        return string.gsub(str, "_%l", string.upper):gsub("^%l", string.lower)
    end,
    
    -- Convert to snake_case
    snakeCase = function(str)
        str = str:gsub("([A-Z])", "_%1"):lower()
        if str:sub(1,1) == "_" then
            str = str:sub(2)
        end
        return str
    end
}

-- Path utilities
Utils.path = {
    -- Join path segments
    join = function(...)
        local segments = {...}
        local result = table.concat(segments, "/"):gsub("//+", "/")
        return result
    end,
    
    -- Get directory name
    dirname = function(path)
        return string.match(path, "(.*)/[^/]*$") or ""
    end,
    
    -- Get base name
    basename = function(path)
        return string.match(path, "[^/]*$")
    end,
    
    -- Get file extension
    extension = function(path)
        return string.match(path, "%.([^%.]+)$") or ""
    end
}

-- Object pool
local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool.new(factory, reset)
    local self = setmetatable({}, ObjectPool)
    self.factory = factory
    self.reset = reset
    self.objects = {}
    self.active = {}
    return self
end

function ObjectPool:acquire()
    local obj = table.remove(self.objects) or self.factory()
    self.active[obj] = true
    return obj
end

function ObjectPool:release(obj)
    if self.active[obj] then
        self.active[obj] = nil
        if self.reset then
            self.reset(obj)
        end
        table.insert(self.objects, obj)
    end
end

function ObjectPool:clear()
    self.objects = {}
    self.active = {}
end

Utils.ObjectPool = ObjectPool

-- Event emitter
local EventEmitter = {}
EventEmitter.__index = EventEmitter

function EventEmitter.new()
    local self = setmetatable({}, EventEmitter)
    self.handlers = {}
    return self
end

function EventEmitter:on(event, handler)
    self.handlers[event] = self.handlers[event] or {}
    table.insert(self.handlers[event], handler)
    return function()
        self:off(event, handler)
    end
end

function EventEmitter:off(event, handler)
    if not self.handlers[event] then return end
    for i, h in ipairs(self.handlers[event]) do
        if h == handler then
            table.remove(self.handlers[event], i)
            break
        end
    end
end

function EventEmitter:emit(event, ...)
    if not self.handlers[event] then return end
    for _, handler in ipairs(self.handlers[event]) do
        handler(...)
    end
end

Utils.EventEmitter = EventEmitter

-- Memoization
function Utils.memoize(fn)
    local cache = {}
    return function(...)
        local args = {...}
        local key = table.concat(args, "|")
        if cache[key] == nil then
            cache[key] = fn(...)
        end
        return cache[key]
    end
end

-- Debounce function
function Utils.debounce(fn, delay)
    local timer
    return function(...)
        local args = {...}
        if timer then timer:stop() end
        timer = require('core.timer').after(delay, function()
            fn(unpack(args))
        end)
    end
end

-- Throttle function
function Utils.throttle(fn, delay)
    local lastCall = 0
    return function(...)
        local now = require('core.timer').getTime()
        if now - lastCall >= delay then
            lastCall = now
            return fn(...)
        end
    end
end

return Utils 