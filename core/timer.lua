local Timer = {
    _VERSION = '1.0.0',
    _DESCRIPTION = 'Barren Engine Timer System'
}

local Event = require('core.event')

-- Internal storage
local timers = {}
local nextTimerId = 1

-- Timer states
local TIMER_STATES = {
    IDLE = 'idle',
    RUNNING = 'running',
    PAUSED = 'paused',
    COMPLETED = 'completed'
}

-- Timer class
local TimerInstance = {}
TimerInstance.__index = TimerInstance

function TimerInstance.new(callback, delay, repeats, startTime)
    local self = setmetatable({}, TimerInstance)
    self.id = nextTimerId
    nextTimerId = nextTimerId + 1
    
    self.callback = callback
    self.delay = delay
    self.repeats = repeats or 1
    self.repeatCount = 0
    self.startTime = startTime or Timer.getTime()
    self.nextTrigger = self.startTime + delay
    self.state = TIMER_STATES.IDLE
    self.tags = {}
    
    return self
end

function TimerInstance:start()
    if self.state == TIMER_STATES.COMPLETED then
        return false
    end
    
    self.state = TIMER_STATES.RUNNING
    self.startTime = Timer.getTime()
    self.nextTrigger = self.startTime + self.delay
    return true
end

function TimerInstance:pause()
    if self.state ~= TIMER_STATES.RUNNING then
        return false
    end
    
    self.state = TIMER_STATES.PAUSED
    self.remainingTime = self.nextTrigger - Timer.getTime()
    return true
end

function TimerInstance:resume()
    if self.state ~= TIMER_STATES.PAUSED then
        return false
    end
    
    self.state = TIMER_STATES.RUNNING
    self.nextTrigger = Timer.getTime() + self.remainingTime
    return true
end

function TimerInstance:stop()
    self.state = TIMER_STATES.COMPLETED
    return true
end

function TimerInstance:reset()
    self.repeatCount = 0
    self.startTime = Timer.getTime()
    self.nextTrigger = self.startTime + self.delay
    self.state = TIMER_STATES.IDLE
    return true
end

function TimerInstance:addTag(tag)
    self.tags[tag] = true
end

function TimerInstance:removeTag(tag)
    self.tags[tag] = nil
end

function TimerInstance:hasTag(tag)
    return self.tags[tag] == true
end

-- Timer system functions

-- Get current time in seconds
function Timer.getTime()
    return os.clock()
end

-- Create a new timer
function Timer.after(delay, callback)
    local timer = TimerInstance.new(callback, delay)
    timers[timer.id] = timer
    timer:start()
    return timer
end

-- Create a repeating timer
function Timer.every(delay, callback, times)
    local timer = TimerInstance.new(callback, delay, times)
    timers[timer.id] = timer
    timer:start()
    return timer
end

-- Create a timer that runs once after the current frame
function Timer.nextTick(callback)
    return Timer.after(0, callback)
end

-- Update all timers
function Timer.update()
    local currentTime = Timer.getTime()
    
    for id, timer in pairs(timers) do
        if timer.state == TIMER_STATES.RUNNING and currentTime >= timer.nextTrigger then
            local success, err = pcall(timer.callback)
            if not success then
                Event.emit('timer:error', timer, err)
            end
            
            timer.repeatCount = timer.repeatCount + 1
            
            if timer.repeats > 0 and timer.repeatCount >= timer.repeats then
                timer.state = TIMER_STATES.COMPLETED
                timers[id] = nil
            else
                timer.nextTrigger = timer.nextTrigger + timer.delay
            end
        end
    end
end

-- Cancel a timer
function Timer.cancel(timer)
    if type(timer) == 'table' then
        timers[timer.id] = nil
        timer:stop()
    end
end

-- Cancel all timers
function Timer.cancelAll()
    for _, timer in pairs(timers) do
        timer:stop()
    end
    timers = {}
end

-- Cancel timers with a specific tag
function Timer.cancelTagged(tag)
    for id, timer in pairs(timers) do
        if timer:hasTag(tag) then
            timer:stop()
            timers[id] = nil
        end
    end
end

-- Pause all timers
function Timer.pauseAll()
    for _, timer in pairs(timers) do
        timer:pause()
    end
end

-- Resume all timers
function Timer.resumeAll()
    for _, timer in pairs(timers) do
        timer:resume()
    end
end

-- Get active timer count
function Timer.getActiveCount()
    local count = 0
    for _, timer in pairs(timers) do
        if timer.state == TIMER_STATES.RUNNING then
            count = count + 1
        end
    end
    return count
end

-- Get all timers
function Timer.getAll()
    local result = {}
    for _, timer in pairs(timers) do
        table.insert(result, timer)
    end
    return result
end

-- Tween function for smooth value interpolation
function Timer.tween(duration, subject, target, easing)
    easing = easing or function(t) return t end
    
    local initial = {}
    for k, v in pairs(target) do
        if type(v) == 'number' then
            initial[k] = subject[k]
        end
    end
    
    local timer = Timer.after(duration, function()
        for k, v in pairs(target) do
            if type(v) == 'number' then
                subject[k] = v
            end
        end
    end)
    
    local function update()
        local progress = math.min((Timer.getTime() - timer.startTime) / duration, 1)
        local easedProgress = easing(progress)
        
        for k, v in pairs(target) do
            if type(v) == 'number' then
                subject[k] = initial[k] + (v - initial[k]) * easedProgress
            end
        end
        
        if progress < 1 then
            Timer.nextTick(update)
        end
    end
    
    Timer.nextTick(update)
    return timer
end

return Timer 