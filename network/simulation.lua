local socket = require("socket")

-- Network condition simulation
local NetworkCondition = {}
NetworkCondition.__index = NetworkCondition

function NetworkCondition.new(config)
    local self = setmetatable({}, NetworkCondition)
    config = config or {}
    
    -- Basic network conditions
    self.packetLoss = config.packetLoss or 0.0     -- 0.0 to 1.0
    self.latency = config.latency or 0             -- Base latency in ms
    self.jitter = config.jitter or 0               -- Random latency variation in ms
    self.bandwidth = config.bandwidth or 0         -- Bandwidth limit in bytes/sec
    self.corruption = config.corruption or 0.0     -- 0.0 to 1.0
    self.reorder = config.reorder or 0.0          -- 0.0 to 1.0
    self.mtu = config.mtu or 1500                 -- Maximum transmission unit
    
    -- Advanced settings
    self.duplicatePackets = config.duplicatePackets or 0.0  -- 0.0 to 1.0
    self.burstLoss = config.burstLoss or false             -- Enable burst loss
    self.burstLength = config.burstLength or 3             -- Packets per burst
    self.bandwidthVariation = config.bandwidthVariation or 0.0  -- 0.0 to 1.0
    
    -- Internal state
    self.lastUpdateTime = socket.gettime()
    self.bytesInWindow = 0
    self.packetQueue = {}
    self.inBurst = false
    self.burstCount = 0
    
    return self
end

-- Network simulator class
local NetworkSimulator = {}
NetworkSimulator.__index = NetworkSimulator

function NetworkSimulator.new()
    local self = setmetatable({}, NetworkSimulator)
    self.enabled = false
    self.condition = NetworkCondition.new()
    self.random = math.random
    math.randomseed(os.time())
    return self
end

function NetworkSimulator:setCondition(condition)
    self.condition = condition
end

function NetworkSimulator:enable()
    self.enabled = true
end

function NetworkSimulator:disable()
    self.enabled = false
end

function NetworkSimulator:isEnabled()
    return self.enabled
end

-- Simulate packet loss
function NetworkSimulator:shouldDropPacket()
    if not self.enabled then return false end
    
    if self.condition.burstLoss then
        if self.inBurst then
            self.burstCount = self.burstCount + 1
            if self.burstCount >= self.condition.burstLength then
                self.inBurst = false
                self.burstCount = 0
            end
            return true
        elseif self.random() < self.condition.packetLoss then
            self.inBurst = true
            self.burstCount = 1
            return true
        end
    else
        return self.random() < self.condition.packetLoss
    end
    
    return false
end

-- Simulate packet corruption
function NetworkSimulator:corruptPacket(data)
    if not self.enabled or self.random() >= self.condition.corruption then
        return data
    end
    
    local corrupted = {}
    for i = 1, #data do
        if self.random() < self.condition.corruption then
            corrupted[i] = string.char(self.random(0, 255))
        else
            corrupted[i] = data:sub(i, i)
        end
    end
    
    return table.concat(corrupted)
end

-- Simulate network latency
function NetworkSimulator:calculateDelay()
    if not self.enabled then return 0 end
    
    local delay = self.condition.latency
    if self.condition.jitter > 0 then
        delay = delay + (self.random() * 2 - 1) * self.condition.jitter
    end
    return math.max(0, delay / 1000) -- Convert to seconds
end

-- Simulate bandwidth limitation
function NetworkSimulator:checkBandwidth(size)
    if not self.enabled or self.condition.bandwidth <= 0 then
        return true
    end
    
    local now = socket.gettime()
    local elapsed = now - self.lastUpdateTime
    
    if elapsed >= 1 then
        self.bytesInWindow = 0
        self.lastUpdateTime = now
    end
    
    local effectiveBandwidth = self.condition.bandwidth
    if self.condition.bandwidthVariation > 0 then
        local variation = self.condition.bandwidthVariation * self.condition.bandwidth
        effectiveBandwidth = effectiveBandwidth + (self.random() * 2 - 1) * variation
    end
    
    if self.bytesInWindow + size > effectiveBandwidth then
        return false
    end
    
    self.bytesInWindow = self.bytesInWindow + size
    return true
end

-- Simulate packet reordering
function NetworkSimulator:shouldReorder()
    return self.enabled and self.random() < self.condition.reorder
end

-- Simulate packet duplication
function NetworkSimulator:shouldDuplicate()
    return self.enabled and self.random() < self.condition.duplicatePackets
end

-- Process a packet through all simulated conditions
function NetworkSimulator:processPacket(data)
    if not self.enabled then return data, 0 end
    
    -- Check MTU
    if #data > self.condition.mtu then
        return nil, 0
    end
    
    -- Check packet loss
    if self:shouldDropPacket() then
        return nil, 0
    end
    
    -- Apply corruption
    data = self:corruptPacket(data)
    
    -- Calculate delay
    local delay = self:calculateDelay()
    
    -- Check bandwidth
    if not self:checkBandwidth(#data) then
        return nil, 0
    end
    
    -- Handle duplication
    if self:shouldDuplicate() then
        -- In a real implementation, you'd queue the duplicate
        -- Here we just note that it should be duplicated
        data = data .. data
    end
    
    return data, delay
end

-- Predefined network conditions
local NetworkConditions = {
    PERFECT = NetworkCondition.new(),
    
    GOOD = NetworkCondition.new({
        packetLoss = 0.01,
        latency = 50,
        jitter = 10,
        bandwidth = 1024 * 1024 -- 1 MB/s
    }),
    
    AVERAGE = NetworkCondition.new({
        packetLoss = 0.05,
        latency = 100,
        jitter = 20,
        bandwidth = 512 * 1024, -- 512 KB/s
        corruption = 0.01
    }),
    
    POOR = NetworkCondition.new({
        packetLoss = 0.1,
        latency = 200,
        jitter = 50,
        bandwidth = 128 * 1024, -- 128 KB/s
        corruption = 0.05,
        reorder = 0.1
    }),
    
    TERRIBLE = NetworkCondition.new({
        packetLoss = 0.2,
        latency = 500,
        jitter = 100,
        bandwidth = 32 * 1024, -- 32 KB/s
        corruption = 0.1,
        reorder = 0.2,
        burstLoss = true
    }),
    
    MOBILE_3G = NetworkCondition.new({
        packetLoss = 0.02,
        latency = 150,
        jitter = 30,
        bandwidth = 384 * 1024, -- 384 KB/s
        bandwidthVariation = 0.3
    }),
    
    MOBILE_4G = NetworkCondition.new({
        packetLoss = 0.01,
        latency = 75,
        jitter = 15,
        bandwidth = 1024 * 1024, -- 1 MB/s
        bandwidthVariation = 0.2
    })
}

return {
    NetworkCondition = NetworkCondition,
    NetworkSimulator = NetworkSimulator,
    NetworkConditions = NetworkConditions
} 