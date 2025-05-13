local Math = {
    _VERSION = '1.0.0',
    _DESCRIPTION = 'Barren Engine Math Library'
}

-- Constants
Math.PI = math.pi
Math.TWO_PI = math.pi * 2
Math.HALF_PI = math.pi / 2
Math.QUARTER_PI = math.pi / 4
Math.DEG_TO_RAD = math.pi / 180
Math.RAD_TO_DEG = 180 / math.pi
Math.EPSILON = 1e-10

-- Vector2 class
local Vector2 = {}
Vector2.__index = Vector2

function Vector2.new(x, y)
    return setmetatable({x = x or 0, y = y or 0}, Vector2)
end

function Vector2:clone()
    return Vector2.new(self.x, self.y)
end

function Vector2:set(x, y)
    self.x = x
    self.y = y
    return self
end

function Vector2:add(v)
    self.x = self.x + v.x
    self.y = self.y + v.y
    return self
end

function Vector2:sub(v)
    self.x = self.x - v.x
    self.y = self.y - v.y
    return self
end

function Vector2:mul(s)
    self.x = self.x * s
    self.y = self.y * s
    return self
end

function Vector2:div(s)
    if s ~= 0 then
        self.x = self.x / s
        self.y = self.y / s
    end
    return self
end

function Vector2:dot(v)
    return self.x * v.x + self.y * v.y
end

function Vector2:cross(v)
    return self.x * v.y - self.y * v.x
end

function Vector2:length()
    return math.sqrt(self.x * self.x + self.y * self.y)
end

function Vector2:lengthSqr()
    return self.x * self.x + self.y * self.y
end

function Vector2:normalize()
    local len = self:length()
    if len > 0 then
        self.x = self.x / len
        self.y = self.y / len
    end
    return self
end

function Vector2:angle()
    return math.atan2(self.y, self.x)
end

function Vector2:rotate(angle)
    local c = math.cos(angle)
    local s = math.sin(angle)
    local x = self.x * c - self.y * s
    local y = self.x * s + self.y * c
    self.x = x
    self.y = y
    return self
end

Math.Vector2 = Vector2

-- Rectangle class
local Rectangle = {}
Rectangle.__index = Rectangle

function Rectangle.new(x, y, width, height)
    return setmetatable({
        x = x or 0,
        y = y or 0,
        width = width or 0,
        height = height or 0
    }, Rectangle)
end

function Rectangle:contains(x, y)
    return x >= self.x and x <= self.x + self.width and
           y >= self.y and y <= self.y + self.height
end

function Rectangle:intersects(rect)
    return self.x < rect.x + rect.width and
           self.x + self.width > rect.x and
           self.y < rect.y + rect.height and
           self.y + self.height > rect.y
end

Math.Rectangle = Rectangle

-- Utility functions

-- Clamp a value between min and max
function Math.clamp(value, min, max)
    return math.min(math.max(value, min), max)
end

-- Linear interpolation
function Math.lerp(a, b, t)
    return a + (b - a) * t
end

-- Smooth step interpolation
function Math.smoothStep(a, b, t)
    t = Math.clamp(t, 0, 1)
    t = t * t * (3 - 2 * t)
    return a + (b - a) * t
end

-- Random float between min and max
function Math.random(min, max)
    if not min then return math.random() end
    if not max then return math.random() * min end
    return min + math.random() * (max - min)
end

-- Random integer between min and max (inclusive)
function Math.randomInt(min, max)
    return math.floor(Math.random(min, max + 1))
end

-- Check if two values are approximately equal
function Math.approximately(a, b, tolerance)
    tolerance = tolerance or Math.EPSILON
    return math.abs(a - b) <= tolerance
end

-- Convert degrees to radians
function Math.toRadians(degrees)
    return degrees * Math.DEG_TO_RAD
end

-- Convert radians to degrees
function Math.toDegrees(radians)
    return radians * Math.RAD_TO_DEG
end

-- Map a value from one range to another
function Math.map(value, fromMin, fromMax, toMin, toMax)
    return toMin + (value - fromMin) * (toMax - toMin) / (fromMax - fromMin)
end

-- Round to nearest decimal place
function Math.round(value, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    return math.floor(value * mult + 0.5) / mult
end

-- Get the sign of a number (-1, 0, or 1)
function Math.sign(value)
    return value > 0 and 1 or value < 0 and -1 or 0
end

-- Wrap a value around min and max
function Math.wrap(value, min, max)
    local range = max - min
    return min + ((value - min) % range)
end

-- Check if a value is a power of two
function Math.isPowerOfTwo(value)
    return value > 0 and (value & (value - 1)) == 0
end

-- Get next power of two
function Math.nextPowerOfTwo(value)
    value = value - 1
    value = value | (value >> 1)
    value = value | (value >> 2)
    value = value | (value >> 4)
    value = value | (value >> 8)
    value = value | (value >> 16)
    return value + 1
end

-- Bezier curve interpolation
function Math.bezier(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    local mt = 1 - t
    local mt2 = mt * mt
    local mt3 = mt2 * mt
    return p0 * mt3 + p1 * (3 * mt2 * t) + p2 * (3 * mt * t2) + p3 * t3
end

-- Easing functions
Math.Easing = {
    linear = function(t) return t end,
    
    quadIn = function(t) return t * t end,
    quadOut = function(t) return t * (2 - t) end,
    quadInOut = function(t)
        t = t * 2
        if t < 1 then return 0.5 * t * t end
        t = t - 1
        return -0.5 * (t * (t - 2) - 1)
    end,
    
    cubicIn = function(t) return t * t * t end,
    cubicOut = function(t) return (t - 1) * (t - 1) * (t - 1) + 1 end,
    cubicInOut = function(t)
        t = t * 2
        if t < 1 then return 0.5 * t * t * t end
        t = t - 2
        return 0.5 * (t * t * t + 2)
    end,
    
    sineIn = function(t) return 1 - math.cos(t * Math.HALF_PI) end,
    sineOut = function(t) return math.sin(t * Math.HALF_PI) end,
    sineInOut = function(t) return -0.5 * (math.cos(Math.PI * t) - 1) end
}

return Math 