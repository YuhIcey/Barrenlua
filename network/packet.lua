local struct = require("struct")

-- Packet flags
local PacketFlags = {
    NONE = 0,
    HAS_ACKS = 1 << 0,
    IS_FRAGMENT = 1 << 1,
    LAST_FRAGMENT = 1 << 2,
    COMPRESSED = 1 << 3,
    ENCRYPTED = 1 << 4,
    HAS_TIMESTAMP = 1 << 5,
    HAS_QOS = 1 << 6,
    RESERVED = 1 << 7,
    INTEGRITY_CHALLENGE = 0x1000,  -- Packet contains integrity challenge
    INTEGRITY_RESPONSE = 0x2000,   -- Packet contains integrity response
    VERSION_CHECK = 0x4000,        -- Packet contains version information
    INTEGRITY_FAILED = 0x8000,     -- Integrity check failed
    TAMPERED = 0x10000,           -- Packet shows signs of tampering
    INVALID_SEQUENCE = 0x20000,   -- Invalid sequence number
    INVALID_SIZE = 0x40000,       -- Invalid packet size
    INVALID_CHECKSUM = 0x80000,   -- Invalid checksum
    REPLAY_DETECTED = 0x100000,    -- Packet replay detected
    TIMESTAMP_INVALID = 0x200000,  -- Invalid timestamp
}

-- Packet header format:
-- uint32: sequence
-- uint32: ackSequence
-- uint16: dataLength
-- uint8:  flags
-- uint8:  reliability
-- uint8:  priority
-- uint8:  reserved
-- uint16: checksum
local HEADER_FORMAT = ">I4I4I2BBBBI2"
local HEADER_SIZE = 16

-- Add packet validation constants
local PACKET_VALIDATION = {
    MIN_SIZE = 16,               -- Minimum packet size (header)
    MAX_SIZE = 8192,             -- Maximum packet size
    SEQUENCE_WINDOW = 10000,     -- Maximum allowed sequence difference
    MAX_FRAGMENTS = 64,          -- Maximum fragments per message
    HEADER_MAGIC = 0xBAE0,       -- Magic number for header validation
    TIMESTAMP_FUTURE_TOLERANCE = 5,    -- Maximum seconds into future
    TIMESTAMP_PAST_TOLERANCE = 30,     -- Maximum seconds into past
    MAX_SEQUENCE_GAP = 10000,         -- Maximum allowed sequence gap
    REPLAY_WINDOW_SIZE = 1024,        -- Size of replay detection window
}

local PacketHeader = {}
PacketHeader.__index = PacketHeader

function PacketHeader.new()
    local self = setmetatable({}, PacketHeader)
    self.magic = PACKET_VALIDATION.HEADER_MAGIC
    self.sequence = 0
    self.ackSequence = 0
    self.dataLength = 0
    self.flags = PacketFlags.NONE
    self.reliability = 0
    self.priority = 0
    self.timestamp = os.time()
    self.checksum = 0
    return self
end

function PacketHeader:validate(connectionId)
    -- Check magic number
    if self.magic ~= PACKET_VALIDATION.HEADER_MAGIC then
        return false, "Invalid magic number"
    end
    
    -- Enhanced timestamp validation
    local now = os.time()
    local futureTime = now + PACKET_VALIDATION.TIMESTAMP_FUTURE_TOLERANCE
    local pastTime = now - PACKET_VALIDATION.TIMESTAMP_PAST_TOLERANCE
    
    if self.timestamp > futureTime then
        self:setFlag(PacketFlags.TIMESTAMP_INVALID)
        return false, "Timestamp too far in future"
    end
    
    if self.timestamp < pastTime then
        self:setFlag(PacketFlags.TIMESTAMP_INVALID)
        return false, "Timestamp too far in past"
    end
    
    -- Check replay protection if connection ID provided
    if connectionId then
        local valid, replayError = ReplayProtection.check(connectionId, self.sequence)
        if not valid then
            self:setFlag(PacketFlags.REPLAY_DETECTED)
            return false, replayError
        end
    end
    
    -- Check size limits
    if self.dataLength > PACKET_VALIDATION.MAX_SIZE - HEADER_SIZE then
        return false, "Packet too large"
    end
    
    -- Validate sequence number range
    if self.sequence == 0 or self.sequence > 0xFFFFFFFF then
        return false, "Invalid sequence number"
    end
    
    -- Check fragment limits
    if self:hasFlag(PacketFlags.IS_FRAGMENT) then
        local fragmentIndex = self.sequence & 0xFFFF
        if fragmentIndex > PACKET_VALIDATION.MAX_FRAGMENTS then
            return false, "Too many fragments"
        end
    end
    
    return true
end

function PacketHeader:serialize()
    -- Validate before serializing
    local valid, err = self:validate()
    if not valid then
        error("Cannot serialize invalid packet: " .. err)
    end
    
    -- Calculate checksum before serializing
    self.checksum = self:calculateChecksum()
    
    -- Add magic number to serialized data
    return struct.pack(">I2" .. HEADER_FORMAT,
        self.magic,
        self.sequence,
        self.ackSequence,
        self.dataLength,
        self.flags,
        self.reliability,
        self.priority,
        self.timestamp,
        self.checksum)
end

function PacketHeader:deserialize(data)
    if #data < HEADER_SIZE + 2 then -- +2 for magic number
        return nil, "Data too short for header"
    end
    
    -- Read and verify magic number first
    local magic = struct.unpack(">I2", data)
    if magic ~= PACKET_VALIDATION.HEADER_MAGIC then
        return nil, "Invalid packet magic number"
    end
    
    local sequence, ackSequence, dataLength, flags, reliability, priority, timestamp, checksum = 
        struct.unpack(HEADER_FORMAT, data:sub(3))
    
    self.magic = magic
    self.sequence = sequence
    self.ackSequence = ackSequence
    self.dataLength = dataLength
    self.flags = flags
    self.reliability = reliability
    self.priority = priority
    self.timestamp = timestamp
    self.checksum = checksum
    
    -- Validate deserialized data
    local valid, err = self:validate()
    if not valid then
        return nil, err
    end
    
    -- Verify checksum
    local expectedChecksum = self.checksum
    self.checksum = 0
    local calculatedChecksum = self:calculateChecksum()
    self.checksum = expectedChecksum
    
    if calculatedChecksum ~= expectedChecksum then
        return nil, "Invalid checksum"
    end
    
    return self
end

function PacketHeader:calculateChecksum()
    -- Save current checksum
    local savedChecksum = self.checksum
    self.checksum = 0
    
    -- Pack all header fields except checksum
    local data = struct.pack(">I2I4I4I2BBBBI4",
        self.magic,
        self.sequence,
        self.ackSequence,
        self.dataLength,
        self.flags,
        self.reliability,
        self.priority,
        self.timestamp)
    
    -- Calculate CRC32 instead of simple checksum
    local crc = 0xFFFFFFFF
    for i = 1, #data do
        local byte = data:byte(i)
        crc = crc ~ byte
        for _ = 1, 8 do
            local msb = crc & 0x80000000
            crc = (crc << 1) & 0xFFFFFFFF
            if msb ~= 0 then
                crc = crc ~ 0x04C11DB7
            end
        end
    end
    
    -- Restore original checksum
    self.checksum = savedChecksum
    
    return (~crc) & 0xFFFFFFFF
end

function PacketHeader:hasFlag(flag)
    return (self.flags & flag) ~= 0
end

function PacketHeader:setFlag(flag)
    self.flags = self.flags | flag
end

function PacketHeader:clearFlag(flag)
    self.flags = self.flags & ~flag
end

-- Packet class that combines header and data
local Packet = {}
Packet.__index = Packet

function Packet.new(data)
    local self = setmetatable({}, Packet)
    self.header = PacketHeader.new()
    self.data = data or ""
    self.securityFlags = 0
    return self
end

function Packet:validate()
    -- Check header
    local valid, err = self.header:validate()
    if not valid then
        return false, err
    end
    
    -- Check data length
    if #self.data ~= self.header.dataLength then
        return false, "Data length mismatch"
    end
    
    -- Check for suspicious patterns
    if self:containsSuspiciousPatterns() then
        return false, "Suspicious data patterns detected"
    end
    
    return true
end

function Packet:containsSuspiciousPatterns()
    -- More comprehensive pattern detection
    local suspiciousPatterns = {
        "\x00\x00\x00\x00\x00\x00",     -- Null byte padding
        "%%00%%00%%00%%00",             -- URL encoded null bytes
        "%.%.[\\/]",                     -- Directory traversal (improved regex)
        "[<>]script",                    -- Script tags
        "SELECT.*FROM",                  -- SQL injection
        "UNION.*SELECT",                 -- SQL union injection
        "exec.*%(.*%)",                  -- Code execution attempt
        "eval.*%(.*%)",                  -- Eval injection
        "require.*%(.*%)",               -- Require injection
        "os%.[a-zA-Z]+",                -- OS command attempt
        "io%.[a-zA-Z]+",                -- IO operation attempt
        "file%:[/\\]+",                 -- File protocol
        "data%:[/\\]+",                 -- Data protocol
        "\\x[0-9a-fA-F][0-9a-fA-F]",   -- Hex encoded chars
        "function.*%(.*%)",             -- Function definition
        "load[file]*%(.*%)",            -- Load attempt
        "dofile%(.*%)",                 -- DoFile attempt
    }
    
    -- Check data for suspicious patterns
    for _, pattern in ipairs(suspiciousPatterns) do
        if self.data:find(pattern) then
            return true
        end
    end
    
    -- Check for unusual character frequencies
    local charFreq = {}
    local totalChars = #self.data
    for i = 1, totalChars do
        local char = self.data:sub(i,i)
        charFreq[char] = (charFreq[char] or 0) + 1
    end
    
    -- Check for suspicious character distributions
    for char, freq in pairs(charFreq) do
        local percentage = freq / totalChars
        if percentage > 0.4 then  -- More than 40% same character
            return true
        end
    end
    
    -- Check for long sequences of the same character
    local currentChar = nil
    local currentCount = 0
    local maxAllowed = 16  -- Maximum allowed repeated characters
    
    for i = 1, #self.data do
        local char = self.data:sub(i,i)
        if char == currentChar then
            currentCount = currentCount + 1
            if currentCount > maxAllowed then
                return true
            end
        else
            currentChar = char
            currentCount = 1
        end
    end
    
    return false
end

function Packet:serialize()
    -- Validate before serializing
    local valid, err = self:validate()
    if not valid then
        error("Cannot serialize invalid packet: " .. err)
    end
    
    self.header.dataLength = #self.data
    local headerData = self.header:serialize()
    return headerData .. self.data
end

function Packet:deserialize(data)
    if #data < PACKET_VALIDATION.MIN_SIZE then
        return nil, "Data too short"
    end
    
    if #data > PACKET_VALIDATION.MAX_SIZE then
        return nil, "Data too large"
    end
    
    local header, err = PacketHeader.new():deserialize(data:sub(1, HEADER_SIZE + 2))
    if not header then
        return nil, err
    end
    
    self.header = header
    self.data = data:sub(HEADER_SIZE + 3)
    
    -- Validate after deserializing
    local valid, validateErr = self:validate()
    if not valid then
        return nil, validateErr
    end
    
    return self
end

-- Add replay protection
local ReplayProtection = {
    windows = {},  -- Per-connection replay windows
    lastCleanup = os.time()
}

function ReplayProtection.init(connectionId)
    ReplayProtection.windows[connectionId] = {
        bitmap = {},  -- Bitmap of received sequences
        windowStart = 0,  -- Start of sliding window
        lastSequence = 0  -- Last received sequence
    }
end

function ReplayProtection.check(connectionId, sequence)
    local window = ReplayProtection.windows[connectionId]
    if not window then
        ReplayProtection.init(connectionId)
        window = ReplayProtection.windows[connectionId]
    end

    -- Check sequence gap
    if math.abs(sequence - window.lastSequence) > PACKET_VALIDATION.MAX_SEQUENCE_GAP then
        return false, "Sequence gap too large"
    end

    -- Check if sequence is too old
    if sequence < window.windowStart then
        return false, "Sequence too old"
    end

    -- Check if sequence was already received
    local index = sequence % PACKET_VALIDATION.REPLAY_WINDOW_SIZE
    if window.bitmap[index] then
        return false, "Replay detected"
    end

    -- Update window
    window.bitmap[index] = true
    window.lastSequence = sequence
    
    -- Slide window if necessary
    if sequence - window.windowStart > PACKET_VALIDATION.REPLAY_WINDOW_SIZE then
        window.windowStart = sequence - PACKET_VALIDATION.REPLAY_WINDOW_SIZE
        -- Clear old entries
        for i = 0, PACKET_VALIDATION.REPLAY_WINDOW_SIZE - 1 do
            if (window.windowStart + i) < sequence then
                window.bitmap[(window.windowStart + i) % PACKET_VALIDATION.REPLAY_WINDOW_SIZE] = nil
            end
        end
    end

    return true
end

-- Add cleanup for replay protection
function ReplayProtection.cleanup()
    local now = os.time()
    if now - ReplayProtection.lastCleanup > 60 then  -- Cleanup every minute
        for connectionId, window in pairs(ReplayProtection.windows) do
            if now - window.lastUpdate > 300 then  -- Remove windows inactive for 5 minutes
                ReplayProtection.windows[connectionId] = nil
            end
        end
        ReplayProtection.lastCleanup = now
    end
end

return {
    Packet = Packet,
    PacketHeader = PacketHeader,
    PacketFlags = PacketFlags,
    HEADER_SIZE = HEADER_SIZE,
    PACKET_VALIDATION = PACKET_VALIDATION,
    ReplayProtection = ReplayProtection
} 