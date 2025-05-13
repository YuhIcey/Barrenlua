local socket = require("socket")
local packet = require("network.packet")
local qos = require("network.qos")

local Connection = {}
Connection.__index = Connection

-- Connection states
local ConnectionState = {
    DISCONNECTED = 0,
    CONNECTING = 1,
    CONNECTED = 2,
    DISCONNECTING = 3
}

-- Create a new Connection instance
function Connection.new(ip, port, config)
    local self = setmetatable({}, Connection)
    
    -- Connection info
    self.ip = ip
    self.port = port
    self.clientId = ip .. ":" .. port
    self.state = ConnectionState.DISCONNECTED
    
    -- Configuration
    self.config = config or {}
    self.maxPacketSize = self.config.maxPacketSize or 1024
    self.fragmentSize = self.config.fragmentSize or 512
    self.fragmentTimeout = self.config.fragmentTimeout or 5000
    self.connectionTimeout = self.config.connectionTimeout or 30000
    self.keepAliveInterval = self.config.keepAliveInterval or 1000
    
    -- Statistics
    self.latency = 0
    self.lastPingTime = 0
    self.lastPongTime = 0
    self.bytesSent = 0
    self.bytesReceived = 0
    self.packetsLost = 0
    self.totalPackets = 0
    self.lastRtt = 0
    self.averageRtt = 0
    self.packetLossRate = 0
    
    -- Reliability
    self.reliableQueue = {}
    self.reliableAcks = {}
    self.nextSequence = 0
    self.lastReceivedSequence = -1
    self.outOfOrderPackets = {}
    
    -- Fragmentation
    self.fragmentMap = {}
    self.lastFragmentTime = {}
    
    -- Keep-alive
    self.lastKeepAliveTime = 0
    self.lastReceivedTime = 0
    
    -- QoS
    self.qosManager = qos.QoSManager.new()
    
    return self
end

-- Connect to remote endpoint
function Connection:connect()
    if self.state ~= ConnectionState.DISCONNECTED then
        return false, "Connection already active"
    end
    
    self.state = ConnectionState.CONNECTING
    
    -- Send connection request with system QoS profile
    local connectPkt = packet.Packet.new("CONNECT")
    connectPkt.header.reliability = qos.PacketReliability.RELIABLE
    connectPkt.header.priority = qos.PacketPriority.SYSTEM
    
    self:sendPacket(connectPkt, self.qosManager:getProfile("SYSTEM"))
    
    return true
end

-- Handle connection established
function Connection:handleConnected()
    self.state = ConnectionState.CONNECTED
    self.lastKeepAliveTime = socket.gettime() * 1000
    self.lastReceivedTime = self.lastKeepAliveTime
end

-- Send data through the connection
function Connection:send(data, profile)
    if self.state ~= ConnectionState.CONNECTED then
        return false, "Connection not established"
    end
    
    profile = profile or self.qosManager:getProfile("DEFAULT")
    
    -- Create packet
    local pkt = packet.Packet.new(data)
    pkt.header.sequence = self:getNextSequence()
    pkt.header.reliability = profile.reliability
    pkt.header.priority = profile.priority
    
    -- Check if fragmentation is needed
    if #data > profile.fragmentSize then
        return self:sendFragmented(pkt, profile)
    end
    
    return self:sendPacket(pkt, profile)
end

-- Send a packet
function Connection:sendPacket(pkt, profile)
    -- Add to reliable queue if needed
    if profile.reliability >= qos.PacketReliability.RELIABLE then
        self:queueReliablePacket(pkt, profile)
    end
    
    -- Serialize and send
    local data = pkt:serialize()
    self.bytesSent = self.bytesSent + #data
    self.totalPackets = self.totalPackets + 1
    
    return true, #data
end

-- Queue reliable packet
function Connection:queueReliablePacket(pkt, profile)
    local entry = {
        packet = pkt,
        profile = profile,
        attempts = 0,
        timestamp = socket.gettime() * 1000,
        nextAttempt = 0
    }
    
    table.insert(self.reliableQueue, entry)
end

-- Send fragmented packet
function Connection:sendFragmented(pkt, profile)
    local data = pkt.data
    local totalSize = #data
    local fragmentSize = profile.fragmentSize
    local fragmentCount = math.ceil(totalSize / fragmentSize)
    local totalSent = 0
    
    for i = 1, fragmentCount do
        local fragmentData = data:sub((i-1) * fragmentSize + 1, i * fragmentSize)
        local fragmentPkt = packet.Packet.new(fragmentData)
        fragmentPkt.header.sequence = pkt.header.sequence | i
        fragmentPkt.header.reliability = profile.reliability
        fragmentPkt.header.priority = profile.priority
        fragmentPkt.header:setFlag(packet.PacketFlags.IS_FRAGMENT)
        
        if i == fragmentCount then
            fragmentPkt.header:setFlag(packet.PacketFlags.LAST_FRAGMENT)
        end
        
        local success, sent = self:sendPacket(fragmentPkt, profile)
        if not success then
            return false, "Failed to send fragment"
        end
        totalSent = totalSent + sent
    end
    
    return true, totalSent
end

-- Handle received packet
function Connection:handlePacket(pkt)
    if self.state ~= ConnectionState.CONNECTED and not pkt.header:hasFlag(packet.PacketFlags.HAS_ACKS) then
        return false, "Connection not established"
    end
    
    self.lastReceivedTime = socket.gettime() * 1000
    self.bytesReceived = self.bytesReceived + #pkt.data
    self.totalPackets = self.totalPackets + 1
    
    -- Handle fragments
    if pkt.header:hasFlag(packet.PacketFlags.IS_FRAGMENT) then
        return self:handleFragment(pkt)
    end
    
    -- Handle acknowledgments
    if pkt.header:hasFlag(packet.PacketFlags.HAS_ACKS) then
        self:handleAcknowledgment(pkt.header.ackSequence)
    end
    
    -- Process based on reliability
    local profile = self.qosManager:getProfile(pkt.header.reliability)
    if profile.reliability >= qos.PacketReliability.RELIABLE then
        self:handleReliablePacket(pkt, profile)
    else
        self:handleUnreliablePacket(pkt, profile)
    end
    
    return true
end

-- Handle reliable packet
function Connection:handleReliablePacket(pkt, profile)
    -- Send acknowledgment
    local ackPkt = packet.Packet.new("")
    ackPkt.header.sequence = self:getNextSequence()
    ackPkt.header.ackSequence = pkt.header.sequence
    ackPkt.header:setFlag(packet.PacketFlags.HAS_ACKS)
    
    self:sendPacket(ackPkt, self.qosManager:getProfile("SYSTEM"))
    
    -- Process ordered packets
    if profile.reliability == qos.PacketReliability.RELIABLE_ORDERED then
        self:handleOrderedPacket(pkt)
    else
        self:deliverPacket(pkt)
    end
end

-- Handle ordered packet
function Connection:handleOrderedPacket(pkt)
    local sequence = pkt.header.sequence
    
    if sequence <= self.lastReceivedSequence then
        -- Duplicate or old packet, ignore
        return
    end
    
    if sequence == self.lastReceivedSequence + 1 then
        -- Next in sequence, deliver
        self:deliverPacket(pkt)
        self.lastReceivedSequence = sequence
        
        -- Check for buffered packets
        while self.outOfOrderPackets[self.lastReceivedSequence + 1] do
            local nextPkt = self.outOfOrderPackets[self.lastReceivedSequence + 1]
            self.outOfOrderPackets[self.lastReceivedSequence + 1] = nil
            self:deliverPacket(nextPkt)
            self.lastReceivedSequence = self.lastReceivedSequence + 1
        end
    else
        -- Out of order, buffer for later
        self.outOfOrderPackets[sequence] = pkt
    end
end

-- Handle unreliable packet
function Connection:handleUnreliablePacket(pkt, profile)
    if profile.reliability == qos.PacketReliability.UNRELIABLE_SEQUENCED then
        -- Only deliver if newer than last received
        if pkt.header.sequence > self.lastReceivedSequence then
            self:deliverPacket(pkt)
            self.lastReceivedSequence = pkt.header.sequence
        end
    else
        -- Just deliver
        self:deliverPacket(pkt)
    end
end

-- Handle fragment
function Connection:handleFragment(pkt)
    local fragmentId = pkt.header.sequence & 0xFFFF0000
    local fragmentIndex = pkt.header.sequence & 0x0000FFFF
    
    if not self.fragmentMap[fragmentId] then
        self.fragmentMap[fragmentId] = {
            fragments = {},
            timestamp = socket.gettime() * 1000
        }
    end
    
    local assembly = self.fragmentMap[fragmentId]
    assembly.fragments[fragmentIndex] = pkt.data
    
    if pkt.header:hasFlag(packet.PacketFlags.LAST_FRAGMENT) then
        assembly.lastFragment = fragmentIndex
    end
    
    -- Check if we have all fragments
    if assembly.lastFragment and #assembly.fragments == assembly.lastFragment then
        local assembledData = table.concat(assembly.fragments)
        self.fragmentMap[fragmentId] = nil
        
        -- Process assembled packet
        local assembledPkt = packet.Packet.new(assembledData)
        return self:handlePacket(assembledPkt)
    end
    
    return true
end

-- Handle acknowledgment
function Connection:handleAcknowledgment(sequence)
    -- Remove acknowledged packet from reliable queue
    for i = #self.reliableQueue, 1, -1 do
        local entry = self.reliableQueue[i]
        if entry.packet.header.sequence == sequence then
            -- Update RTT statistics
            local rtt = socket.gettime() * 1000 - entry.timestamp
            self:updateRttStats(rtt)
            
            table.remove(self.reliableQueue, i)
            break
        end
    end
end

-- Update RTT statistics
function Connection:updateRttStats(rtt)
    self.lastRtt = rtt
    self.averageRtt = self.averageRtt * 0.875 + rtt * 0.125
end

-- Update connection state
function Connection:update()
    if self.state == ConnectionState.CONNECTED then
        local currentTime = socket.gettime() * 1000
        
        -- Update keep-alive
        if currentTime - self.lastKeepAliveTime > self.keepAliveInterval then
            self:sendKeepAlive()
            self.lastKeepAliveTime = currentTime
        end
        
        -- Check connection timeout
        if currentTime - self.lastReceivedTime > self.connectionTimeout then
            self:disconnect("Connection timeout")
            return
        end
        
        -- Process reliable queue
        self:processReliableQueue(currentTime)
        
        -- Clean up fragments
        self:cleanupFragments(currentTime)
    end
end

-- Process reliable queue
function Connection:processReliableQueue(currentTime)
    for i = #self.reliableQueue, 1, -1 do
        local entry = self.reliableQueue[i]
        
        if currentTime >= entry.nextAttempt then
            entry.attempts = entry.attempts + 1
            
            if entry.attempts > entry.profile.maxRetries then
                -- Max retries reached
                table.remove(self.reliableQueue, i)
                self.packetsLost = self.packetsLost + 1
                self.packetLossRate = self.packetsLost / self.totalPackets
            else
                -- Resend packet
                local delay = qos.getRetryDelay(entry.profile, entry.attempts)
                entry.nextAttempt = currentTime + delay
                self:sendPacket(entry.packet, entry.profile)
            end
        end
    end
end

-- Clean up fragments
function Connection:cleanupFragments(currentTime)
    for fragmentId, assembly in pairs(self.fragmentMap) do
        if currentTime - assembly.timestamp > self.fragmentTimeout then
            self.fragmentMap[fragmentId] = nil
        end
    end
end

-- Send keep-alive
function Connection:sendKeepAlive()
    local keepAlivePkt = packet.Packet.new("KEEPALIVE")
    keepAlivePkt.header.reliability = qos.PacketReliability.UNRELIABLE
    keepAlivePkt.header.priority = qos.PacketPriority.LOWEST
    
    self:sendPacket(keepAlivePkt, self.qosManager:getProfile("DEFAULT"))
end

-- Get next sequence number
function Connection:getNextSequence()
    self.nextSequence = (self.nextSequence + 1) & 0xFFFFFFFF
    return self.nextSequence
end

-- Deliver packet to application
function Connection:deliverPacket(pkt)
    -- Override this method in the application to handle received packets
end

-- Disconnect
function Connection:disconnect(reason)
    if self.state == ConnectionState.DISCONNECTED then
        return false, "Already disconnected"
    end
    
    self.state = ConnectionState.DISCONNECTING
    
    -- Send disconnect notification with system priority
    local disconnectPkt = packet.Packet.new(reason or "Client disconnected")
    disconnectPkt.header.reliability = qos.PacketReliability.RELIABLE
    disconnectPkt.header.priority = qos.PacketPriority.SYSTEM
    
    self:sendPacket(disconnectPkt, self.qosManager:getProfile("SYSTEM"))
    
    -- Clean up
    self.state = ConnectionState.DISCONNECTED
    self.reliableQueue = {}
    self.fragmentMap = {}
    self.outOfOrderPackets = {}
    
    return true
end

-- Get connection statistics
function Connection:getStatistics()
    return {
        state = self.state,
        bytesSent = self.bytesSent,
        bytesReceived = self.bytesReceived,
        totalPackets = self.totalPackets,
        packetsLost = self.packetsLost,
        packetLossRate = self.packetLossRate,
        lastRtt = self.lastRtt,
        averageRtt = self.averageRtt,
        reliableQueueSize = #self.reliableQueue,
        fragmentMapSize = #self.fragmentMap
    }
end

return Connection 