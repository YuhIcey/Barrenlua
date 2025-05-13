--[[
    Hardware ID (HWID) System
    Handles hardware-based identification and banning
    Copyright (c) 2025 Barren Engine
--]]

local ffi = require("ffi")
local bit = require("bit")

-- Define necessary C functions
ffi.cdef[[
    // Windows
    typedef void* HANDLE;
    typedef unsigned long DWORD;
    typedef wchar_t WCHAR;
    typedef const wchar_t* LPCWSTR;
    typedef struct _SYSTEM_INFO {
        union {
            DWORD dwOemId;
            struct {
                WORD wProcessorArchitecture;
                WORD wReserved;
            };
        };
        DWORD dwPageSize;
        void* lpMinimumApplicationAddress;
        void* lpMaximumApplicationAddress;
        DWORD* dwActiveProcessorMask;
        DWORD dwNumberOfProcessors;
        DWORD dwProcessorType;
        DWORD dwAllocationGranularity;
        WORD wProcessorLevel;
        WORD wProcessorRevision;
    } SYSTEM_INFO, *LPSYSTEM_INFO;

    void GetSystemInfo(LPSYSTEM_INFO lpSystemInfo);
    
    // For disk information
    typedef struct _STORAGE_DEVICE_DESCRIPTOR {
        DWORD Version;
        DWORD Size;
        BYTE DeviceType;
        BYTE DeviceTypeModifier;
        BYTE RemovableMedia;
        BYTE CommandQueueing;
        DWORD VendorIdOffset;
        DWORD ProductIdOffset;
        DWORD ProductRevisionOffset;
        DWORD SerialNumberOffset;
        BYTE BusType;
        DWORD RawPropertiesLength;
        BYTE RawDeviceProperties[1];
    } STORAGE_DEVICE_DESCRIPTOR, *PSTORAGE_DEVICE_DESCRIPTOR;

    // For MAC address
    typedef struct _IP_ADAPTER_INFO {
        struct _IP_ADAPTER_INFO* Next;
        DWORD ComboIndex;
        char AdapterName[260];
        char Description[132];
        DWORD AddressLength;
        BYTE Address[8];
        DWORD Index;
        DWORD Type;
        DWORD DhcpEnabled;
        DWORD CurrentIpAddress;
        struct _IP_ADDR_STRING* IpAddressList;
        struct _IP_ADDR_STRING* GatewayList;
        struct _IP_ADDR_STRING* DhcpServer;
        BOOL HaveWins;
        struct _IP_ADDR_STRING* PrimaryWinsServer;
        struct _IP_ADDR_STRING* SecondaryWinsServer;
        time_t LeaseObtained;
        time_t LeaseExpires;
    } IP_ADAPTER_INFO, *PIP_ADAPTER_INFO;

    DWORD GetAdaptersInfo(PIP_ADAPTER_INFO pAdapterInfo, PDWORD pOutBufLen);
]]

local HWID = {
    -- Constants for HWID generation
    HASH_ITERATIONS = 10000,
    SALT_LENGTH = 16,
    
    -- Blacklisted hardware patterns
    BLACKLISTED_PATTERNS = {
        "VMware",
        "VirtualBox",
        "QEMU",
        "Virtual",
        "Sandbox"
    },
    
    -- Store banned HWIDs
    bannedHWIDs = {},
    
    -- Store HWID cache
    hwidCache = {},
    
    -- Last cleanup timestamp
    lastCleanup = os.time()
}

-- Helper function to get system information
local function getSystemInfo()
    local sysInfo = ffi.new("SYSTEM_INFO")
    ffi.C.GetSystemInfo(sysInfo)
    return {
        processorArchitecture = sysInfo.wProcessorArchitecture,
        numberOfProcessors = sysInfo.dwNumberOfProcessors,
        processorType = sysInfo.dwProcessorType,
        processorLevel = sysInfo.wProcessorLevel,
        processorRevision = sysInfo.wProcessorRevision
    }
end

-- Helper function to get MAC addresses
local function getMACAddresses()
    local bufSize = ffi.new("DWORD[1]", 0)
    local result = ffi.C.GetAdaptersInfo(nil, bufSize)
    
    if result == 111 then -- ERROR_BUFFER_OVERFLOW
        local pAdapterInfo = ffi.new("IP_ADAPTER_INFO[?]", bufSize[0])
        result = ffi.C.GetAdaptersInfo(pAdapterInfo, bufSize)
        
        if result == 0 then
            local macs = {}
            local adapter = pAdapterInfo
            while adapter ~= nil do
                local mac = ""
                for i = 0, tonumber(adapter.AddressLength) - 1 do
                    mac = mac .. string.format("%02X", adapter.Address[i])
                end
                table.insert(macs, mac)
                adapter = adapter.Next
            end
            return macs
        end
    end
    return {}
end

-- Generate a unique hardware identifier
function HWID:generate()
    local hwid = {}
    
    -- Get system information
    local sysInfo = getSystemInfo()
    for k, v in pairs(sysInfo) do
        table.insert(hwid, tostring(v))
    end
    
    -- Get MAC addresses (excluding virtual adapters)
    local macs = getMACAddresses()
    for _, mac in ipairs(macs) do
        local isVirtual = false
        for _, pattern in ipairs(self.BLACKLISTED_PATTERNS) do
            if mac:match(pattern) then
                isVirtual = true
                break
            end
        end
        if not isVirtual then
            table.insert(hwid, mac)
        end
    end
    
    -- Get CPU information
    local cpuInfo = io.popen("wmic cpu get processorid /format:value")
    if cpuInfo then
        local cpuId = cpuInfo:read("*a")
        cpuInfo:close()
        table.insert(hwid, cpuId)
    end
    
    -- Get disk serial
    local diskInfo = io.popen("wmic diskdrive get serialnumber /format:value")
    if diskInfo then
        local diskSerial = diskInfo:read("*a")
        diskInfo:close()
        table.insert(hwid, diskSerial)
    end
    
    -- Get BIOS serial
    local biosInfo = io.popen("wmic bios get serialnumber /format:value")
    if biosInfo then
        local biosSerial = biosInfo:read("*a")
        biosInfo:close()
        table.insert(hwid, biosSerial)
    end
    
    -- Generate hash from collected information
    local concat = table.concat(hwid, "|")
    local hash = self:hash(concat)
    
    return hash
end

-- Hash function with salt
function HWID:hash(data)
    local salt = self:generateSalt()
    local salted = data .. salt
    
    -- Multiple iterations of XOR and bit manipulation
    local hash = 0
    for i = 1, self.HASH_ITERATIONS do
        for j = 1, #salted do
            local byte = string.byte(salted, j)
            hash = bit.bxor(hash, byte)
            hash = bit.rol(hash, 7)
            hash = hash * 31 + byte
        end
    end
    
    return string.format("%016x", hash)
end

-- Generate random salt
function HWID:generateSalt()
    local salt = ""
    for i = 1, self.SALT_LENGTH do
        salt = salt .. string.char(math.random(0, 255))
    end
    return salt
end

-- Ban a HWID
function HWID:banHWID(hwid, reason)
    self.bannedHWIDs[hwid] = {
        timestamp = os.time(),
        reason = reason or "No reason provided",
        banCount = (self.bannedHWIDs[hwid] and self.bannedHWIDs[hwid].banCount or 0) + 1
    }
end

-- Check if HWID is banned
function HWID:isHWIDBanned(hwid)
    return self.bannedHWIDs[hwid] ~= nil
end

-- Get ban information
function HWID:getBanInfo(hwid)
    return self.bannedHWIDs[hwid]
end

-- Unban a HWID
function HWID:unbanHWID(hwid)
    self.bannedHWIDs[hwid] = nil
end

-- Clean up old cached HWIDs
function HWID:cleanup()
    local now = os.time()
    if now - self.lastCleanup > 3600 then -- Cleanup every hour
        for hwid, data in pairs(self.hwidCache) do
            if now - data.timestamp > 86400 then -- Remove after 24 hours
                self.hwidCache[hwid] = nil
            end
        end
        self.lastCleanup = now
    end
end

-- Detect virtual machine or sandbox environment
function HWID:isVirtualEnvironment()
    local signs = 0
    
    -- Check system information
    local sysInfo = getSystemInfo()
    if sysInfo.numberOfProcessors < 2 then
        signs = signs + 1
    end
    
    -- Check MAC addresses for virtual adapters
    local macs = getMACAddresses()
    for _, mac in ipairs(macs) do
        for _, pattern in ipairs(self.BLACKLISTED_PATTERNS) do
            if mac:match(pattern) then
                signs = signs + 1
                break
            end
        end
    end
    
    -- Check for common VM strings in system information
    local systemInfo = io.popen("systeminfo")
    if systemInfo then
        local info = systemInfo:read("*a"):lower()
        systemInfo:close()
        
        for _, pattern in ipairs(self.BLACKLISTED_PATTERNS) do
            if info:match(pattern:lower()) then
                signs = signs + 1
            end
        end
    end
    
    return signs >= 2 -- Consider it virtual if 2 or more signs are detected
end

-- Export the HWID module
return HWID 