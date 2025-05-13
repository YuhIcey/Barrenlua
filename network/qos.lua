-- Quality of Service module

-- Packet reliability levels
local PacketReliability = {
    UNRELIABLE = 0,              -- No delivery guarantee
    UNRELIABLE_SEQUENCED = 1,    -- No guarantee, but ordered
    RELIABLE = 2,                -- Guaranteed delivery
    RELIABLE_ORDERED = 3,        -- Guaranteed and ordered delivery
    RELIABLE_SEQUENCED = 4       -- Guaranteed, ordered, and sequenced
}

-- Packet priority levels
local PacketPriority = {
    LOWEST = 0,
    LOW = 1,
    NORMAL = 2,
    MEDIUM = 3,
    HIGH = 4,
    HIGHEST = 5,
    SYSTEM = 6    -- Reserved for system messages
}

-- QoS Profile class
local QoSProfile = {}
QoSProfile.__index = QoSProfile

function QoSProfile.new(config)
    local self = setmetatable({}, QoSProfile)
    config = config or {}
    
    -- Basic settings
    self.reliability = config.reliability or PacketReliability.RELIABLE
    self.priority = config.priority or PacketPriority.NORMAL
    
    -- Retry settings
    self.maxRetries = config.maxRetries or 3
    self.retryDelay = config.retryDelay or 100  -- milliseconds
    self.timeout = config.timeout or 5000        -- milliseconds
    
    -- Optimization settings
    self.compression = config.compression ~= false  -- default true
    self.encryption = config.encryption or false
    
    -- Advanced settings
    self.fragmentSize = config.fragmentSize or 1024
    self.orderingChannel = config.orderingChannel or 0
    self.sequencingChannel = config.sequencingChannel or 0
    
    return self
end

-- Predefined QoS profiles
local QoSProfiles = {
    -- Default profile for most messages
    DEFAULT = QoSProfile.new({
        reliability = PacketReliability.RELIABLE,
        priority = PacketPriority.NORMAL,
        compression = true,
        encryption = false
    }),
    
    -- Profile for time-sensitive data (e.g., position updates)
    REALTIME = QoSProfile.new({
        reliability = PacketReliability.UNRELIABLE_SEQUENCED,
        priority = PacketPriority.HIGH,
        compression = false,
        encryption = false,
        maxRetries = 0
    }),
    
    -- Profile for critical system messages
    SYSTEM = QoSProfile.new({
        reliability = PacketReliability.RELIABLE_ORDERED,
        priority = PacketPriority.SYSTEM,
        compression = true,
        encryption = true,
        maxRetries = 5,
        timeout = 10000
    }),
    
    -- Profile for large file transfers
    BULK = QoSProfile.new({
        reliability = PacketReliability.RELIABLE,
        priority = PacketPriority.LOW,
        compression = true,
        encryption = false,
        fragmentSize = 8192,
        maxRetries = 10,
        timeout = 30000
    }),
    
    -- Profile for chat messages
    CHAT = QoSProfile.new({
        reliability = PacketReliability.RELIABLE_ORDERED,
        priority = PacketPriority.NORMAL,
        compression = true,
        encryption = true
    })
}

-- QoS Manager class
local QoSManager = {}
QoSManager.__index = QoSManager

function QoSManager.new()
    local self = setmetatable({}, QoSManager)
    self.profiles = {}
    
    -- Add default profiles
    for name, profile in pairs(QoSProfiles) do
        self.profiles[name] = profile
    end
    
    return self
end

function QoSManager:addProfile(name, profile)
    self.profiles[name] = profile
end

function QoSManager:getProfile(name)
    return self.profiles[name] or QoSProfiles.DEFAULT
end

function QoSManager:removeProfile(name)
    if name ~= "DEFAULT" and name ~= "SYSTEM" then
        self.profiles[name] = nil
    end
end

-- Helper functions for QoS management
local function shouldRetry(profile, attempts)
    return attempts < profile.maxRetries
end

local function getRetryDelay(profile, attempts)
    -- Exponential backoff
    return profile.retryDelay * (2 ^ attempts)
end

local function shouldFragment(profile, dataSize)
    return dataSize > profile.fragmentSize
end

local function getFragmentCount(profile, dataSize)
    return math.ceil(dataSize / profile.fragmentSize)
end

return {
    PacketReliability = PacketReliability,
    PacketPriority = PacketPriority,
    QoSProfile = QoSProfile,
    QoSProfiles = QoSProfiles,
    QoSManager = QoSManager,
    shouldRetry = shouldRetry,
    getRetryDelay = getRetryDelay,
    shouldFragment = shouldFragment,
    getFragmentCount = getFragmentCount
} 