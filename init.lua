--[[
    Barren Engine - Lua Edition
    Copyright (c) 2025 Barren Engine Contributors
    All rights reserved.

    This software is proprietary and confidential.
    Unauthorized copying, modification, distribution, or use of this software
    is strictly prohibited.

    When using this engine, you agree to the terms of the EULA. You can use this for your projects. This will not be updated. but bugs and errors will be fixed. this is very light weight
    and is not intended to be used for heavy duty applications or games. this is not using winsock or lua socket. this is using the barren engine socket library.
    This is a work in progress and will not be used in production. if you are too fork this and make it better, please do not edit this file and give credit to C/Drive Studios. This is a fork of the C++ version.


        if you have any questions, please contact me in the discord server : https://discord.gg/yjEkHz4hkx
        I recommend you to use the C++ version of the engine. do not edit the lua version. as it is not intended to use heavy loads.
        if you want to use this for your projects or fork it if you are just gonna be using the base source code go along ahead.
        This is a WIP and will not be updated regularly only for bugs and errors. new features will not be added. 




    DO NOT EDIT THIS FILE.
    DO NOT EDIT THE NETWORK MANAGER FILE.
    DO NOT EDIT THE CONNECTION FILE.
    DO NOT EDIT THE COMPRESSION ALGORITHM FILE.
    DO NOT EDIT THE CRYPTO MODE FILE.
    DO NOT EDIT THE NETWORK PROTOCOL FILE.
    DO NOT EDIT THE PACKET PRIORITY FILE.
    DO NOT EDIT THE PACKET RELIABILITY FILE.
    DO NOT EDIT THE QOS FILE.
    DO NOT EDIT THE SIMULATION FILE.    
]]

local Barren = {
    _VERSION = '1.0.0',
    _DESCRIPTION = 'Barren Engine - A Lightweight Game Networking Engine'
}

-- Core modules
Barren.Event = require('core.event')
Barren.Log = require('core.log')
Barren.Config = require('core.config')
Barren.Timer = require('core.timer')
Barren.Math = require('core.math')
Barren.Utils = require('core.utils')

-- Network modules
Barren.Network = {
    Manager = require('network.manager'),
    Connection = require('network.connection'),
    Packet = require('network.packet'),
    QoS = require('network.qos'),
    Simulation = require('network.simulation')
}

-- Support modules
Barren.Compression = require('compression')
Barren.Crypto = require('crypto')

-- Constants
Barren.NetworkProtocol = {
    UDP = 0,
    TCP = 1
}

Barren.PacketReliability = {
    UNRELIABLE = 0,                    -- No guarantee of delivery
    UNRELIABLE_SEQUENCED = 1,          -- No guarantee, but packets arrive in order
    RELIABLE = 2,                      -- Guaranteed delivery
    RELIABLE_ORDERED = 3,              -- Guaranteed delivery and order
    RELIABLE_SEQUENCED = 4,            -- Guaranteed delivery, order within sequence
    RELIABLE_WITH_ACK_RECEIPT = 5,     -- Guaranteed delivery with acknowledgment
    RELIABLE_ORDERED_WITH_ACK_RECEIPT = 6  -- Guaranteed delivery, order, and acknowledgment
}

Barren.PacketPriority = {
    IMMEDIATE_PRIORITY = 0,    -- Highest priority, sent immediately
    HIGH_PRIORITY = 1,         -- High priority, sent within 10ms
    MEDIUM_PRIORITY = 2,       -- Normal priority, sent within 100ms
    LOW_PRIORITY = 3,          -- Low priority, sent within 500ms
    LOWEST_PRIORITY = 4        -- Lowest priority, sent when bandwidth available
}

Barren.CompressionAlgorithm = {
    NONE = 0,
    LZ4 = 1,
    ZSTD = 2
}

Barren.CryptoMode = {
    NONE = 0,
    AES_GCM = 1,
    CHACHA20_POLY1305 = 2
}

-- Default configuration
local DEFAULT_CONFIG = {
    network = {
        port = 7000,
        maxConnections = 32,
        tickRate = 60,
        timeout = 30000,
        bufferSize = 1024 * 64,
        compression = true,
        encryption = false
    },
    simulation = {
        enabled = false,
        packetLoss = 0,
        latency = 0,
        jitter = 0
    },
    log = {
        level = 'info',
        showTimestamp = true,
        showSource = true,
        useColors = true
    }
}

-- Engine instance
local instance = nil

-- Initialize the engine
function Barren.init(config)
    if instance then
        Barren.Log.warn("Engine already initialized")
        return instance
    end
    
    -- Merge config with defaults
    config = Barren.Utils.table.merge(Barren.Utils.table.deepCopy(DEFAULT_CONFIG), config or {})
    
    -- Configure logging
    Barren.Log.configure({
        level = Barren.Log.Level[string.upper(config.log.level)] or Barren.Log.Level.INFO,
        showTimestamp = config.log.showTimestamp,
        showSource = config.log.showSource,
        useColors = config.log.useColors
    })
    
    -- Create logger
    local logger = Barren.Log.createLogger("Barren")
    
    -- Initialize configuration
    Barren.Config.setDefaults(config)
    
    -- Create network manager
    local networkManager = Barren.Network.Manager.new(config.network)
    
    -- Setup network simulation if enabled
    if config.simulation.enabled then
        local simulator = Barren.Network.Simulation.new({
            packetLoss = config.simulation.packetLoss,
            latency = config.simulation.latency,
            jitter = config.simulation.jitter
        })
        networkManager:setSimulator(simulator)
    end
    
    -- Create engine instance
    instance = {
        config = config,
        logger = logger,
        network = networkManager,
        running = false,
        
        -- Start the engine
        start = function(self)
            if self.running then
                self.logger.warn("Engine already running")
                return false
            end
            
            self.logger.info("Starting Barren Engine v" .. Barren._VERSION)
            
            -- Start network manager
            local success, err = self.network:start()
            if not success then
                self.logger.error("Failed to start network manager: " .. err)
                return false
            end
            
            self.running = true
            self.logger.info("Engine started successfully")
            
            -- Start main loop
            self:loop()
            return true
        end,
        
        -- Stop the engine
        stop = function(self)
            if not self.running then
                self.logger.warn("Engine not running")
                return false
            end
            
            self.logger.info("Stopping engine")
            
            -- Stop network manager
            self.network:stop()
            
            -- Cancel all timers
            Barren.Timer.cancelAll()
            
            self.running = false
            self.logger.info("Engine stopped")
            return true
        end,
        
        -- Main loop
        loop = function(self)
            if not self.running then return end
            
            local function tick()
                -- Update timers
                Barren.Timer.update()
                
                -- Update network
                self.network:update()
                
                -- Schedule next tick
                if self.running then
                    local tickDelay = 1 / config.network.tickRate
                    Barren.Timer.after(tickDelay, function() self:loop() end)
                end
            end
            
            tick()
        end,
        
        -- Get engine statistics
        getStats = function(self)
            return {
                network = self.network:getStatistics(),
                timers = Barren.Timer.getActiveCount()
            }
        end
    }
    
    -- Setup event handlers
    Barren.Event.on('network:error', function(err)
        instance.logger.error("Network error: " .. tostring(err))
    end)
    
    Barren.Event.on('network:connection', function(connection)
        instance.logger.info("New connection from " .. tostring(connection.address))
    end)
    
    Barren.Event.on('network:disconnection', function(connection)
        instance.logger.info("Connection closed: " .. tostring(connection.address))
    end)
    
    return instance
end

-- Get the engine instance
function Barren.getInstance()
    return instance
end

-- Shutdown the engine
function Barren.shutdown()
    if instance then
        instance:stop()
        instance = nil
    end
end

return Barren 