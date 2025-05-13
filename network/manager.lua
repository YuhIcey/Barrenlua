local socket = require("socket")
local Connection = require("network.connection")
local packet = require("network.packet")
local qos = require("network.qos")
local simulation = require("network.simulation")
local AntiCheat = require("security.anticheat")
local Integrity = require("security.integrity")
local HWID = require("security/hwid")

local NetworkManager = {}
NetworkManager.__index = NetworkManager

-- NetworkManager configuration defaults
local DEFAULT_CONFIG = {
    protocol = "udp",
    port = 12345,
    maxConnections = 32,
    bufferSize = 1024,
    enableCompression = true,
    compressionAlgorithm = 2, -- ZSTD
    enableEncryption = false,
    encryptionMode = 0, -- NONE
    encryptionKey = nil,
    maxPacketSize = 1024,
    fragmentSize = 512,
    fragmentTimeout = 5000,
    connectionTimeout = 30000,
    keepAliveInterval = 1000,
    enablePacketValidation = true,
    enablePacketLogging = true,
    simulateNetworkConditions = false,
    networkCondition = "PERFECT",
    enableIntegrityCheck = true,
    integrityCheckInterval = 30, -- seconds
    maxIntegrityFailures = 3,
    maxPacketsPerSecond = 1000,    -- Rate limiting
    connectionCooldown = 5,         -- Seconds between connection attempts
    maxConnectionsPerIP = 3,        -- Maximum connections from same IP
    packetFloodThreshold = 100,     -- Packets per second threshold
    banDuration = 3600,            -- Ban duration in seconds
    enableRateLimit = true,
    maxPacketQueueSize = 1000,      -- Maximum queued packets per connection
    connectionBurstLimit = 10,       -- Maximum connections per second
    connectionBurstWindow = 5,       -- Connection burst window in seconds
    packetBurstLimit = 100,         -- Maximum packets per burst
    packetBurstWindow = 1,          -- Packet burst window in seconds
    maxPacketProcessingTime = 0.1,  -- Maximum time to process a packet (seconds)
    enableHWIDBan = true,           -- Enable HWID banning
    hwidBanDuration = 7776000,      -- HWID ban duration (90 days)
    allowVirtualMachine = false,    -- Allow connections from virtual machines
}

-- Create a new NetworkManager instance
function NetworkManager.new()
    local self = setmetatable({}, NetworkManager)
    
    self.running = false
    self.socket = nil
    self.connections = {}
    self.messageCallback = nil
    self.messageQueue = {}
    self.config = nil
    
    -- Statistics
    self.bytesSent = 0
    self.bytesReceived = 0
    self.averageLatency = 0
    self.packetLoss = 0
    
    -- Fragment management
    self.fragmentMap = {}
    self.nextMessageId = 0
    
    -- Keep-alive
    self.lastKeepAlive = 0
    self.lastActivity = {}
    
    -- QoS management
    self.qosManager = qos.QoSManager.new()
    
    -- Network simulation
    self.simulator = simulation.NetworkSimulator.new()
    
    -- Anti-cheat
    self.antiCheat = AntiCheat.new()
    
    -- Integrity checking
    self.integrityChecks = {}
    self.pendingChallenges = {}
    self.lastIntegrityCheck = {}
    self.integrityFailures = {}
    
    -- Rate limiting
    self.packetCounts = {}
    self.connectionAttempts = {}
    self.ipConnections = {}
    self.lastCleanup = os.time()
    
    -- Connection burst tracking
    self.connectionBurst = {}
    
    return self
end

-- Initialize the NetworkManager with configuration
function NetworkManager:initialize(config)
    self.config = setmetatable(config or {}, {__index = DEFAULT_CONFIG})
    
    -- Create socket
    local success, err = self:setupSocket()
    if not success then
        return false, err
    end
    
    -- Initialize logging if enabled
    if self.config.enablePacketLogging then
        self:initializeLogging()
    end
    
    -- Set up network simulation if enabled
    if self.config.simulateNetworkConditions then
        self.simulator:setCondition(simulation.NetworkConditions[self.config.networkCondition])
        self.simulator:enable()
    end
    
    self.running = true
    return true
end

-- Set up the network socket
function NetworkManager:setupSocket()
    local socketType = self.config.protocol
    self.socket = socket.bind("*", self.config.port)
    
    if not self.socket then
        return false, "Failed to create socket"
    end
    
    -- Set socket options
    self.socket:settimeout(0) -- Non-blocking
    return true
end

-- Start the server
function NetworkManager:startServer()
    if not self.running or not self.socket then
        return false, "NetworkManager not initialized"
    end
    
    return true
end

-- Update network state
function NetworkManager:update()
    if not self.running then return end
    
    -- Process incoming data
    self:processIncomingData()
    
    -- Update statistics
    self:updateStatistics()
    
    -- Handle keep-alive
    self:handleKeepAlive()
    
    -- Check connection timeouts
    self:checkConnectionTimeouts()
    
    -- Run anti-cheat scans
    local threats = self.antiCheat:scan()
    if threats and #threats > 0 then
        self.antiCheat:handleThreats(threats)
        
        -- Handle severe threats
        for _, threat in ipairs(threats) do
            if threat.level >= self.antiCheat.ThreatLevel.HIGH then
                -- Disconnect affected connections
                for addr, conn in pairs(self.connections) do
                    if conn.lastThreat and conn.lastThreat.type == threat.type then
                        conn:disconnect("Security violation detected")
                        self.connections[addr] = nil
                    end
                end
            end
        end
    end
    
    -- Perform integrity checks
    if self.config.enableIntegrityCheck then
        local now = os.time()
        for clientId, connection in pairs(self.connections) do
            local lastCheck = self.lastIntegrityCheck[clientId] or 0
            if now - lastCheck > self.config.integrityCheckInterval then
                self:handleConnectionRequest("", clientId:match("([^:]+):(%d+)"))
            end
        end
    end
end

-- Process incoming network data
function NetworkManager:processIncomingData()
    while self.running do
        local data, ip, port = self.socket:receivefrom()
        if not data then break end
        
        -- Handle received data
        self:handleReceivedData(data, ip, port)
        self.bytesReceived = self.bytesReceived + #data
    end
end

-- Handle received network data
function NetworkManager:handleReceivedData(data, ip, port)
    local clientId = ip .. ":" .. port
    local startTime = os.clock()
    
    -- Check processing time
    local function checkProcessingTime()
        if os.clock() - startTime > self.config.maxPacketProcessingTime then
            error("Packet processing timeout")
        end
    end
    
    -- Basic validations
    if #data > self.config.maxPacketSize then
        self:banAddress(ip, "Oversized packet")
        return
    end
    
    -- Check connection burst
    if not self.connections[clientId] and not self:checkConnectionBurst(ip) then
        self:banAddress(ip, "Connection burst limit exceeded")
        return
    end
    
    -- Check packet queue size
    local connection = self.connections[clientId]
    if connection and #connection.packetQueue >= self.config.maxPacketQueueSize then
        self:banAddress(ip, "Packet queue overflow")
        return
    end
    
    checkProcessingTime()
    
    -- Parse and validate packet
    local pkt = packet.Packet.new()
    local success, err = pkt:deserialize(data)
    if not success then
        print("Failed to parse packet:", err)
        return
    end
    
    checkProcessingTime()
    
    -- Validate packet with connection context
    if not pkt:validate(clientId) then
        self:banAddress(ip, "Invalid packet")
        return
    end
    
    checkProcessingTime()
    
    -- Handle integrity challenge response
    if pkt.header:hasFlag(packet.PacketFlags.INTEGRITY_RESPONSE) then
        local success, err = self:handleIntegrityResponse(pkt.data, ip, port)
        if not success then
            self:banAddress(ip, "Integrity check failed: " .. err)
        end
        return
    end
    
    -- Check if connection needs integrity verification
    if self.config.enableIntegrityCheck then
        if not self.connections[clientId] then
            return self:handleConnectionRequest(data, ip, port)
        end
        
        local lastCheck = self.lastIntegrityCheck[clientId] or 0
        if os.time() - lastCheck > self.config.integrityCheckInterval then
            self:handleConnectionRequest(data, ip, port)
            return
        end
    end
    
    checkProcessingTime()
    
    -- Apply network simulation
    if self.simulator:isEnabled() then
        local simulatedData, delay = self.simulator:processPacket(data)
        if not simulatedData then
            -- Packet was "lost" in simulation
            return
        end
        data = simulatedData
        
        -- In a real implementation, we'd queue the packet with the delay
        -- For now, we just process it immediately
    end
    
    -- Handle fragments
    if pkt.header:hasFlag(packet.PacketFlags.IS_FRAGMENT) then
        self:handleFragment(pkt, clientId)
        return
    end
    
    -- Handle acknowledgments
    if pkt.header:hasFlag(packet.PacketFlags.HAS_ACKS) then
        self:handleAcknowledgment(pkt, clientId)
    end
    
    -- Process packet based on QoS profile
    local profile = self.qosManager:getProfile(pkt.header.reliability)
    if profile.reliability >= qos.PacketReliability.RELIABLE then
        self:sendAcknowledgment(pkt, ip, port)
    end
    
    -- Anti-cheat verification
    local isValid, flag, reason = self.antiCheat:verifyPacket(pkt)
    if not isValid then
        -- Log the threat
        print(string.format("Anti-cheat violation detected from %s: %s", clientId, reason))
        
        -- Handle based on severity
        if flag == self.antiCheat.Flags.PACKET_MANIPULATION then
            -- Severe violation - disconnect immediately
            local connection = self.connections[clientId]
            if connection then
                connection:disconnect("Anti-cheat violation")
            end
            return
        elseif flag == self.antiCheat.Flags.SPEED_HACK then
            -- Add to monitoring list
            self.antiCheat.scan_interval = 0.5 -- Increase scan frequency
        end
    end
    
    -- Deliver packet to application
    if self.messageCallback then
        self.messageCallback({
            data = pkt.data,
            ip = ip,
            port = port,
            clientId = clientId,
            header = pkt.header
        })
    end
end

-- Send a message
function NetworkManager:send(message, ip, port, profile)
    if not self.running then
        return -1, "NetworkManager not running"
    end
    
    profile = profile or self.qosManager:getProfile("DEFAULT")
    
    -- Create packet
    local pkt = packet.Packet.new(message.data)
    pkt.header.sequence = self:getNextSequence()
    pkt.header.reliability = profile.reliability
    pkt.header.priority = profile.priority
    
    -- Apply compression if enabled
    if profile.compression and self.config.enableCompression then
        pkt.data = self:compressData(pkt.data)
        pkt.header:setFlag(packet.PacketFlags.COMPRESSED)
    end
    
    -- Apply encryption if enabled
    if profile.encryption and self.config.enableEncryption then
        pkt.data = self:encryptData(pkt.data)
        pkt.header:setFlag(packet.PacketFlags.ENCRYPTED)
    end
    
    -- Fragment large packets
    if #pkt.data > profile.fragmentSize then
        return self:sendFragmented(pkt, ip, port, profile)
    end
    
    -- Serialize packet
    local data = pkt:serialize()
    
    -- Apply network simulation
    if self.simulator:isEnabled() then
        local simulatedData, delay = self.simulator:processPacket(data)
        if not simulatedData then
            -- Packet was "lost" in simulation
            return #data
        end
        data = simulatedData
    end
    
    -- Send the data
    local success, err = self.socket:sendto(data, ip, port)
    if success then
        self.bytesSent = self.bytesSent + #data
        return #data
    else
        return -1, err
    end
end

-- Send fragmented packet
function NetworkManager:sendFragmented(pkt, ip, port, profile)
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
        
        local sent, err = self:send({data = fragmentPkt:serialize()}, ip, port)
        if sent < 0 then
            return -1, err
        end
        totalSent = totalSent + sent
    end
    
    return totalSent
end

-- Handle incoming fragment
function NetworkManager:handleFragment(pkt, clientId)
    local fragmentId = pkt.header.sequence & 0xFFFF0000
    local fragmentIndex = pkt.header.sequence & 0x0000FFFF
    
    if not self.fragmentMap[clientId] then
        self.fragmentMap[clientId] = {}
    end
    
    if not self.fragmentMap[clientId][fragmentId] then
        self.fragmentMap[clientId][fragmentId] = {
            fragments = {},
            timestamp = socket.gettime()
        }
    end
    
    local assembly = self.fragmentMap[clientId][fragmentId]
    assembly.fragments[fragmentIndex] = pkt.data
    
    if pkt.header:hasFlag(packet.PacketFlags.LAST_FRAGMENT) then
        assembly.lastFragment = fragmentIndex
    end
    
    -- Check if we have all fragments
    if assembly.lastFragment and #assembly.fragments == assembly.lastFragment then
        local assembledData = table.concat(assembly.fragments)
        self.fragmentMap[clientId][fragmentId] = nil
        
        -- Process assembled packet
        local assembledPkt = packet.Packet.new(assembledData)
        self:handleReceivedData(assembledPkt:serialize(), clientId:match("([^:]+):(%d+)"))
    end
end

-- Handle acknowledgment
function NetworkManager:handleAcknowledgment(pkt, clientId)
    local connection = self.connections[clientId]
    if connection then
        connection:handleAcknowledgment(pkt.header.ackSequence)
    end
end

-- Send acknowledgment
function NetworkManager:sendAcknowledgment(pkt, ip, port)
    local ackPkt = packet.Packet.new("")
    ackPkt.header.sequence = self:getNextSequence()
    ackPkt.header.ackSequence = pkt.header.sequence
    ackPkt.header:setFlag(packet.PacketFlags.HAS_ACKS)
    
    local data = ackPkt:serialize()
    self.socket:sendto(data, ip, port)
end

-- Get next sequence number
function NetworkManager:getNextSequence()
    self.nextMessageId = (self.nextMessageId + 1) & 0xFFFFFFFF
    return self.nextMessageId
end

-- Clean up old fragments
function NetworkManager:cleanupFragments()
    local now = socket.gettime()
    for clientId, fragments in pairs(self.fragmentMap) do
        for fragmentId, assembly in pairs(fragments) do
            if now - assembly.timestamp > self.config.fragmentTimeout / 1000 then
                fragments[fragmentId] = nil
            end
        end
        if not next(fragments) then
            self.fragmentMap[clientId] = nil
        end
    end
end

-- Broadcast a message to all connected clients
function NetworkManager:broadcast(message)
    local sent = 0
    for clientId, connection in pairs(self.connections) do
        local ip, port = clientId:match("([^:]+):(%d+)")
        local bytes, err = self:send(message, ip, tonumber(port))
        if bytes > 0 then
            sent = sent + bytes
        end
    end
    return sent
end

-- Set message callback
function NetworkManager:setMessageCallback(callback)
    self.messageCallback = callback
end

-- Get connected clients
function NetworkManager:getConnectedClients()
    local clients = {}
    for clientId, _ in pairs(self.connections) do
        table.insert(clients, clientId)
    end
    return clients
end

-- Check if a client is connected
function NetworkManager:isClientConnected(clientId)
    return self.connections[clientId] ~= nil
end

-- Disconnect a client
function NetworkManager:disconnectClient(clientId)
    if self.connections[clientId] then
        self.connections[clientId] = nil
        return true
    end
    return false
end

-- Get statistics
function NetworkManager:getStatistics()
    return {
        bytesSent = self.bytesSent,
        bytesReceived = self.bytesReceived,
        averageLatency = self.averageLatency,
        packetLoss = self.packetLoss,
        connectedClients = #self:getConnectedClients()
    }
end

-- Shutdown the NetworkManager
function NetworkManager:shutdown()
    self.running = false
    if self.socket then
        self.socket:close()
        self.socket = nil
    end
    self.connections = {}
end

-- Helper functions
function NetworkManager:validatePacket(pkt)
    if not pkt or not pkt.header then
        return false
    end
    
    -- Check sequence number
    if pkt.header.sequence == 0 then
        return false
    end
    
    -- Check data length
    if pkt.header.dataLength ~= #pkt.data then
        return false
    end
    
    -- Check flags
    if pkt.header.flags & 0xFF00 ~= 0 then -- Reserved flags should be 0
        return false
    end
    
    -- Validate checksum
    local calculatedChecksum = pkt.header:calculateChecksum()
    if calculatedChecksum ~= pkt.header.checksum then
        return false
    end
    
    return true
end

function NetworkManager:compressData(data)
    -- Implement compression logic
    return data
end

function NetworkManager:encryptData(data)
    -- Implement encryption logic
    return data
end

function NetworkManager:updateStatistics()
    -- Update network statistics
end

function NetworkManager:handleKeepAlive()
    -- Handle keep-alive messages
end

function NetworkManager:checkConnectionTimeouts()
    -- Check for connection timeouts
end

function NetworkManager:initializeLogging()
    -- Initialize packet logging
end

function NetworkManager:logPacket(data, isOutgoing)
    -- Log packet data
end

-- Enhanced connection creation with anti-cheat
function NetworkManager:createConnection(address, port)
    local connection = Connection.new(address, port)
    
    -- Add anti-cheat monitoring
    connection.lastThreat = nil
    connection.threatCount = 0
    
    -- Override connection's send method to include anti-cheat signatures
    local originalSend = connection.send
    connection.send = function(self, data, profile)
        -- Add anti-cheat signature
        local packet = packet.Packet.new(data)
        packet.signature = self.antiCheat:signPacket(data)
        packet.timestamp = os.clock()
        packet.sequence = self.sequence
        
        return originalSend(self, packet:toBytes(), profile)
    end
    
    self.connections[address] = connection
    return connection
end

-- Add security-related methods
function NetworkManager:banAddress(address, reason)
    local now = os.time()
    
    -- Remove existing connections
    local connection = self.connections[address]
    if connection then
        -- Log the ban
        print(string.format("[%s] Banning %s: %s", 
            os.date("%Y-%m-%d %H:%M:%S"), 
            address, 
            reason))
        
        -- Notify other connected clients if needed
        self:broadcast({
            type = "security_event",
            event = "client_banned",
            address = address:match("([^:]+)") -- Only send IP, not port
        })
        
        -- Disconnect the client
        connection:disconnect(reason or "Banned")
        self.connections[address] = nil
        
        -- Update connection tracking
        local ip = address:match("([^:]+)")
        self.ipConnections[ip] = (self.ipConnections[ip] or 1) - 1
    end
    
    -- Add to banned list with expiration
    self.bannedAddresses = self.bannedAddresses or {}
    self.bannedAddresses[address] = {
        time = now,
        expires = now + self.config.banDuration,
        reason = reason,
        banCount = (self.bannedAddresses[address] and 
                   self.bannedAddresses[address].banCount or 0) + 1
    }
    
    -- Increase ban duration for repeat offenders
    if self.bannedAddresses[address].banCount > 1 then
        self.bannedAddresses[address].expires = 
            now + (self.config.banDuration * self.bannedAddresses[address].banCount)
    end
    
    -- Cleanup old bans periodically
    if now - (self.lastBanCleanup or 0) > 300 then
        self:cleanupBans()
    end
    
    -- Add HWID ban if enabled
    if self.config.enableHWIDBan then
        local hwid = self.clientHWIDs and self.clientHWIDs[address]
        
        if hwid then
            HWID:banHWID(hwid, reason)
            print(string.format("[%s] HWID banned: %s (%s)",
                os.date("%Y-%m-%d %H:%M:%S"),
                hwid,
                reason))
                
            -- Remove from tracking
            self.clientHWIDs[address] = nil
        end
    end
end

function NetworkManager:isAddressBanned(address)
    if not self.bannedAddresses then return false end
    
    local ban = self.bannedAddresses[address]
    if not ban then
        -- Check if recently unbanned
        if self.recentlyUnbanned and self.recentlyUnbanned[address] then
            -- Apply stricter rate limiting for recently unbanned addresses
            if not self:checkRateLimit(address, true) then
                self:banAddress(address, "Rate limit exceeded after unban")
                return true
            end
        end
        return false
    end
    
    -- Check if ban has expired
    local now = os.time()
    if now > ban.expires then
        self.bannedAddresses[address] = nil
        return false
    end
    
    return true
end

-- Add new function for handling connection requests
function NetworkManager:handleConnectionRequest(data, ip, port)
    local clientId = ip .. ":" .. port
    
    -- Check if HWID ban is enabled
    if self.config.enableHWIDBan then
        -- Extract HWID from connection request
        local pkt = packet.Packet.new()
        local success, err = pkt:deserialize(data)
        if not success then
            return false, "Invalid connection request"
        end
        
        -- Get HWID from packet data
        local hwid = pkt.data
        
        -- Check if HWID is banned
        if HWID:isHWIDBanned(hwid) then
            local banInfo = HWID:getBanInfo(hwid)
            print(string.format("[%s] Rejected connection from banned HWID %s: %s",
                os.date("%Y-%m-%d %H:%M:%S"),
                hwid,
                banInfo.reason))
            return false, "HWID banned: " .. banInfo.reason
        end
        
        -- Check for virtual machine
        if not self.config.allowVirtualMachine and HWID:isVirtualEnvironment() then
            print(string.format("[%s] Rejected connection from virtual environment: %s",
                os.date("%Y-%m-%d %H:%M:%S"),
                clientId))
            return false, "Virtual machines not allowed"
        end
        
        -- Store HWID for future reference
        self.clientHWIDs = self.clientHWIDs or {}
        self.clientHWIDs[clientId] = hwid
    end
    
    -- Create integrity challenge
    local challenge = Integrity.createChallenge()
    self.pendingChallenges[clientId] = challenge
    
    -- Send challenge to client
    local challengePkt = packet.Packet.new(challenge)
    challengePkt.header:setFlag(packet.PacketFlags.INTEGRITY_CHALLENGE)
    self:send(challengePkt:serialize(), ip, port)
    
    return true
end

-- Add new function for handling integrity responses
function NetworkManager:handleIntegrityResponse(data, ip, port)
    local clientId = ip .. ":" .. port
    local challenge = self.pendingChallenges[clientId]
    
    if not challenge then
        return false, "No pending challenge"
    end
    
    -- Verify response
    local response = packet.Packet.new(data):deserialize()
    local state, message = Integrity.verifyResponse(challenge, response)
    
    if state ~= Integrity.State.VERIFIED then
        -- Handle integrity check failure
        self.integrityFailures[clientId] = (self.integrityFailures[clientId] or 0) + 1
        
        if self.integrityFailures[clientId] >= self.config.maxIntegrityFailures then
            self:banAddress(clientId, "Integrity check failed: " .. message)
            return false, "Banned for integrity violations"
        end
        
        return false, message
    end
    
    -- Clear pending challenge
    self.pendingChallenges[clientId] = nil
    self.integrityChecks[clientId] = os.time()
    
    return true
end

-- Add rate limiting function
function NetworkManager:checkRateLimit(ip, isPostBan)
    local now = os.time()
    
    -- Initialize counters
    self.packetCounts[ip] = self.packetCounts[ip] or {
        count = 0,
        burstCount = 0,
        lastReset = now,
        burstReset = now
    }
    
    local counts = self.packetCounts[ip]
    
    -- Reset counters if windows expired
    if now - counts.lastReset >= 1 then
        counts.count = 0
        counts.lastReset = now
    end
    
    if now - counts.burstReset >= self.config.packetBurstWindow then
        counts.burstCount = 0
        counts.burstReset = now
    end
    
    -- Increment counters
    counts.count = counts.count + 1
    counts.burstCount = counts.burstCount + 1
    
    -- Check limits
    local maxPackets = isPostBan and 
        (self.config.maxPacketsPerSecond / 2) or 
        self.config.maxPacketsPerSecond
        
    if counts.count > maxPackets or 
       counts.burstCount > self.config.packetBurstLimit then
        return false
    end
    
    return true
end

-- Add connection attempt limiting
function NetworkManager:checkConnectionLimit(ip)
    local now = os.time()
    
    -- Clean up old attempts
    if now - self.lastCleanup > 60 then
        for addr, time in pairs(self.connectionAttempts) do
            if now - time > self.config.connectionCooldown then
                self.connectionAttempts[addr] = nil
            end
        end
        self.lastCleanup = now
    end
    
    -- Check cooldown
    if self.connectionAttempts[ip] and 
       now - self.connectionAttempts[ip] < self.config.connectionCooldown then
        return false, "Connection attempt too soon"
    end
    
    -- Check connections per IP
    self.ipConnections[ip] = self.ipConnections[ip] or 0
    if self.ipConnections[ip] >= self.config.maxConnectionsPerIP then
        return false, "Too many connections from IP"
    end
    
    -- Update tracking
    self.connectionAttempts[ip] = now
    self.ipConnections[ip] = self.ipConnections[ip] + 1
    
    return true
end

-- Add flood protection
function NetworkManager:checkFloodProtection(clientId)
    local now = os.time()
    local stats = self.connectionStats[clientId]
    
    if not stats then
        self.connectionStats[clientId] = {
            packetCount = 0,
            lastReset = now
        }
        return true
    end
    
    -- Reset counter if window expired
    if now - stats.lastReset >= 1 then
        stats.packetCount = 0
        stats.lastReset = now
    end
    
    -- Increment counter
    stats.packetCount = stats.packetCount + 1
    
    -- Check threshold
    if stats.packetCount > self.config.packetFloodThreshold then
        self:banAddress(clientId, "Packet flood detected")
        return false
    end
    
    return true
end

-- Add connection burst tracking
function NetworkManager:checkConnectionBurst(ip)
    local now = os.time()
    
    -- Cleanup old entries
    if now - self.connectionBurst.lastCleanup > 60 then
        for addr, data in pairs(self.connectionBurst.attempts) do
            if now - data.timestamp > self.config.connectionBurstWindow then
                self.connectionBurst.attempts[addr] = nil
            end
        end
        self.connectionBurst.lastCleanup = now
    end
    
    -- Initialize or get burst data
    local burst = self.connectionBurst.attempts[ip] or {
        count = 0,
        timestamp = now
    }
    
    -- Reset if window expired
    if now - burst.timestamp > self.config.connectionBurstWindow then
        burst.count = 0
        burst.timestamp = now
    end
    
    -- Increment and check
    burst.count = burst.count + 1
    self.connectionBurst.attempts[ip] = burst
    
    return burst.count <= self.config.connectionBurstLimit
end

-- Add ban cleanup
function NetworkManager:cleanupBans()
    local now = os.time()
    self.lastBanCleanup = now
    
    for address, ban in pairs(self.bannedAddresses) do
        if now > ban.expires then
            -- Keep track of expired bans for rate limiting
            self.recentlyUnbanned = self.recentlyUnbanned or {}
            self.recentlyUnbanned[address] = now
            
            -- Remove the ban
            self.bannedAddresses[address] = nil
        end
    end
    
    -- Cleanup old unbanned entries
    for address, time in pairs(self.recentlyUnbanned or {}) do
        if now - time > 3600 then -- Keep for 1 hour
            self.recentlyUnbanned[address] = nil
        end
    end
end

-- Add HWID unban function
function NetworkManager:unbanHWID(hwid)
    if not self.config.enableHWIDBan then
        return false, "HWID banning not enabled"
    end
    
    if not HWID:isHWIDBanned(hwid) then
        return false, "HWID not banned"
    end
    
    HWID:unbanHWID(hwid)
    print(string.format("[%s] HWID unbanned: %s",
        os.date("%Y-%m-%d %H:%M:%S"),
        hwid))
    
    return true
end

-- Add HWID ban check function
function NetworkManager:isHWIDBanned(hwid)
    if not self.config.enableHWIDBan then
        return false
    end
    
    return HWID:isHWIDBanned(hwid)
end

-- Add function to get all banned HWIDs
function NetworkManager:getBannedHWIDs()
    if not self.config.enableHWIDBan then
        return {}
    end
    
    local banned = {}
    for hwid, info in pairs(HWID.bannedHWIDs) do
        banned[hwid] = {
            reason = info.reason,
            timestamp = info.timestamp,
            banCount = info.banCount
        }
    end
    
    return banned
end

-- Add cleanup for HWID tracking
function NetworkManager:cleanup()
    -- Cleanup existing code
    self:cleanupFragments()
    self:cleanupBans()
    
    -- Cleanup HWID cache
    if self.config.enableHWIDBan then
        HWID:cleanup()
        
        -- Clean up disconnected client HWIDs
        for clientId, hwid in pairs(self.clientHWIDs or {}) do
            if not self.connections[clientId] then
                self.clientHWIDs[clientId] = nil
            end
        end
    end
end

return NetworkManager 