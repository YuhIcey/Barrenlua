local lz4 = require("lz4")
local zstd = require("zstd")

local Compression = {}

-- Compression algorithms
Compression.Algorithm = {
    NONE = 0,
    LZ4 = 1,
    ZSTD = 2
}

-- Default compression settings
local DEFAULT_SETTINGS = {
    algorithm = Compression.Algorithm.ZSTD,
    level = 3, -- Default compression level
    windowSize = 1024 * 1024, -- 1MB window size for ZSTD
    dictionarySize = 32 * 1024 -- 32KB dictionary size
}

-- Initialize compression with settings
function Compression.initialize(settings)
    settings = settings or {}
    for k, v in pairs(DEFAULT_SETTINGS) do
        if settings[k] == nil then
            settings[k] = v
        end
    end
    return settings
end

-- Compress data using specified algorithm
function Compression.compress(data, settings)
    settings = Compression.initialize(settings)
    
    if not data or #data == 0 then
        return data
    end
    
    local compressed
    local algorithm = settings.algorithm
    
    if algorithm == Compression.Algorithm.NONE then
        return data
    elseif algorithm == Compression.Algorithm.LZ4 then
        compressed = Compression.compressLZ4(data, settings)
    elseif algorithm == Compression.Algorithm.ZSTD then
        compressed = Compression.compressZSTD(data, settings)
    else
        error("Unsupported compression algorithm: " .. tostring(algorithm))
    end
    
    return compressed
end

-- Decompress data using specified algorithm
function Compression.decompress(data, settings)
    settings = Compression.initialize(settings)
    
    if not data or #data == 0 then
        return data
    end
    
    local decompressed
    local algorithm = settings.algorithm
    
    if algorithm == Compression.Algorithm.NONE then
        return data
    elseif algorithm == Compression.Algorithm.LZ4 then
        decompressed = Compression.decompressLZ4(data, settings)
    elseif algorithm == Compression.Algorithm.ZSTD then
        decompressed = Compression.decompressZSTD(data, settings)
    else
        error("Unsupported compression algorithm: " .. tostring(algorithm))
    end
    
    return decompressed
end

-- LZ4 compression
function Compression.compressLZ4(data, settings)
    local level = settings.level
    return lz4.compress(data, level)
end

-- LZ4 decompression
function Compression.decompressLZ4(data, settings)
    return lz4.decompress(data)
end

-- ZSTD compression
function Compression.compressZSTD(data, settings)
    local level = settings.level
    local windowSize = settings.windowSize
    return zstd.compress(data, level, windowSize)
end

-- ZSTD decompression
function Compression.decompressZSTD(data, settings)
    return zstd.decompress(data)
end

-- Get compression statistics
function Compression.getStatistics(originalData, compressedData)
    if not originalData or not compressedData then
        return {
            originalSize = 0,
            compressedSize = 0,
            ratio = 1,
            savings = 0
        }
    end
    
    local originalSize = #originalData
    local compressedSize = #compressedData
    local ratio = compressedSize / originalSize
    local savings = 1 - ratio
    
    return {
        originalSize = originalSize,
        compressedSize = compressedSize,
        ratio = ratio,
        savings = savings
    }
end

-- Create a compression dictionary from sample data
function Compression.createDictionary(samples, settings)
    settings = Compression.initialize(settings)
    
    if settings.algorithm == Compression.Algorithm.ZSTD then
        return zstd.train_dictionary(samples, settings.dictionarySize)
    else
        return nil
    end
end

-- Compress data using a dictionary
function Compression.compressWithDictionary(data, dictionary, settings)
    settings = Compression.initialize(settings)
    
    if settings.algorithm == Compression.Algorithm.ZSTD then
        local cctx = zstd.create_cctx()
        zstd.cctx_load_dictionary(cctx, dictionary)
        return zstd.compress_using_cctx(cctx, data, settings.level)
    else
        return Compression.compress(data, settings)
    end
end

-- Decompress data using a dictionary
function Compression.decompressWithDictionary(data, dictionary, settings)
    settings = Compression.initialize(settings)
    
    if settings.algorithm == Compression.Algorithm.ZSTD then
        local dctx = zstd.create_dctx()
        zstd.dctx_load_dictionary(dctx, dictionary)
        return zstd.decompress_using_dctx(dctx, data)
    else
        return Compression.decompress(data, settings)
    end
end

-- Estimate compression ratio without actually compressing
function Compression.estimateCompressionRatio(data, settings)
    if not data or #data == 0 then
        return 1
    end
    
    -- Sample the data
    local sampleSize = math.min(1024, #data)
    local sample = data:sub(1, sampleSize)
    
    -- Compress the sample
    local compressed = Compression.compress(sample, settings)
    
    -- Calculate ratio from sample
    return #compressed / #sample
end

return Compression 