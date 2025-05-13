local Event = {
    _VERSION = '1.0.0',
    _DESCRIPTION = 'Barren Engine Event System',
}

-- Event priority levels
Event.Priority = {
    LOWEST = 1,
    LOW = 2,
    NORMAL = 3,
    HIGH = 4,
    HIGHEST = 5,
    MONITOR = 6
}

-- Internal storage for event handlers
local handlers = {}
local handlerIds = {}
local nextHandlerId = 1

-- Create a new event handler ID
local function generateHandlerId()
    local id = nextHandlerId
    nextHandlerId = nextHandlerId + 1
    return id
end

-- Sort handlers by priority
local function sortHandlers(eventName)
    if handlers[eventName] then
        table.sort(handlers[eventName], function(a, b)
            return a.priority > b.priority
        end)
    end
end

-- Register an event handler
function Event.on(eventName, callback, priority)
    assert(type(eventName) == 'string', 'Event name must be a string')
    assert(type(callback) == 'function', 'Callback must be a function')
    
    priority = priority or Event.Priority.NORMAL
    
    if not handlers[eventName] then
        handlers[eventName] = {}
    end
    
    local id = generateHandlerId()
    local handler = {
        id = id,
        callback = callback,
        priority = priority
    }
    
    table.insert(handlers[eventName], handler)
    handlerIds[id] = {eventName = eventName, index = #handlers[eventName]}
    sortHandlers(eventName)
    
    return id
end

-- Register a one-time event handler
function Event.once(eventName, callback, priority)
    local id
    local wrappedCallback = function(...)
        Event.off(id)
        return callback(...)
    end
    id = Event.on(eventName, wrappedCallback, priority)
    return id
end

-- Unregister an event handler
function Event.off(handlerId)
    local info = handlerIds[handlerId]
    if not info then return false end
    
    local eventHandlers = handlers[info.eventName]
    if not eventHandlers then return false end
    
    for i = #eventHandlers, 1, -1 do
        if eventHandlers[i].id == handlerId then
            table.remove(eventHandlers, i)
            handlerIds[handlerId] = nil
            return true
        end
    end
    
    return false
end

-- Remove all handlers for an event
function Event.clear(eventName)
    if eventName then
        if handlers[eventName] then
            for _, handler in ipairs(handlers[eventName]) do
                handlerIds[handler.id] = nil
            end
            handlers[eventName] = nil
        end
    else
        handlers = {}
        handlerIds = {}
    end
end

-- Emit an event
function Event.emit(eventName, ...)
    if not handlers[eventName] then return true end
    
    local eventHandlers = handlers[eventName]
    for i = 1, #eventHandlers do
        local success, result = pcall(eventHandlers[i].callback, ...)
        if not success then
            print(string.format("Error in event handler for '%s': %s", eventName, result))
            return false
        end
        if result == false then
            return false
        end
    end
    
    return true
end

-- Get the number of handlers for an event
function Event.getHandlerCount(eventName)
    if not handlers[eventName] then return 0 end
    return #handlers[eventName]
end

-- Check if an event has handlers
function Event.hasHandlers(eventName)
    return handlers[eventName] and #handlers[eventName] > 0
end

-- Get all registered event names
function Event.getEventNames()
    local names = {}
    for name in pairs(handlers) do
        table.insert(names, name)
    end
    return names
end

return Event 