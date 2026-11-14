-- Stand-ins for the parts of the game's C_EncodingUtil that QuestieDB reads its
-- data with: base64, zlib (through LibDeflate) and CBOR.
--
--   local D = dofile("decode.lua")(LibDeflate)
--   D.DecodeBase64(s)  D.DecompressString(s, 1)  D.DeserializeCBOR(s)
--
-- Only decoding is provided. Invalid input raises an error, like the game does.

local byte, char, sub, concat = string.byte, string.char, string.sub, table.concat
local floor, ldexp, huge = math.floor, math.ldexp, math.huge
local unpack = unpack or table.unpack

return function(LibDeflate)
    local D = {}

    -- Base64 ---------------------------------------------------------------
    local SIX = {}
    do
        local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        for i = 1, #alphabet do SIX[byte(alphabet, i)] = i - 1 end
    end
    local EQ = byte("=")

    function D.DecodeBase64(text)
        if type(text) ~= "string" then error("DecodeBase64: expected a string", 2) end
        local len = #text
        if len % 4 ~= 0 then error("DecodeBase64: invalid length", 2) end
        local out, n, parts = {}, 0, {}
        for i = 1, len, 4 do
            local c1, c2, c3, c4 = byte(text, i, i + 3)
            local a, b, c, d = SIX[c1], SIX[c2], SIX[c3], SIX[c4]
            if not (a and b) then error("DecodeBase64: invalid character", 2) end
            local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
            n = n + 1
            out[n] = floor(v / 65536)
            if c then
                n = n + 1
                out[n] = floor(v / 256) % 256
            elseif c3 ~= EQ or c4 ~= EQ or i + 3 ~= len then
                error("DecodeBase64: invalid encoding", 2)
            end
            if d then
                n = n + 1
                out[n] = v % 256
            elseif c4 ~= EQ or i + 3 ~= len then
                error("DecodeBase64: invalid encoding", 2)
            end
            if n >= 3000 then
                parts[#parts + 1] = char(unpack(out, 1, n))
                n = 0
            end
        end
        if n > 0 then parts[#parts + 1] = char(unpack(out, 1, n)) end
        return concat(parts)
    end

    -- zlib -----------------------------------------------------------------
    function D.DecompressString(value, method)
        if method ~= 1 then error("DecompressString: only method 1 (zlib) is supported here", 2) end
        local output, leftover = LibDeflate:DecompressZlib(value)
        if output == nil or leftover ~= 0 then error("DecompressString: invalid compressed data", 2) end
        return output
    end

    -- CBOR (RFC 8949), decoding only ----------------------------------------
    -- Strings (byte or text) become Lua strings, arrays become 1-based tables,
    -- maps keep their keys as decoded, tags are skipped, null and undefined are nil.
    local s, pos, slen

    local function need(count)
        if pos + count - 1 > slen then error("DeserializeCBOR: unexpected end of data", 0) end
    end

    local function readUint(info)
        if info < 24 then return info end
        if info == 24 then
            need(1); local b = byte(s, pos); pos = pos + 1
            return b
        elseif info == 25 then
            need(2); local b1, b2 = byte(s, pos, pos + 1); pos = pos + 2
            return b1 * 256 + b2
        elseif info == 26 then
            need(4); local b1, b2, b3, b4 = byte(s, pos, pos + 3); pos = pos + 4
            return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
        elseif info == 27 then
            need(8); local b1, b2, b3, b4, b5, b6, b7, b8 = byte(s, pos, pos + 7); pos = pos + 8
            return (((b1 * 256 + b2) * 256 + b3) * 256 + b4) * 4294967296
                + ((b5 * 256 + b6) * 256 + b7) * 256 + b8
        end
        error("DeserializeCBOR: unsupported length encoding " .. info, 0)
    end

    local function half(b1, b2)
        local sign = b1 >= 128 and -1 or 1
        local e = floor(b1 / 4) % 32
        local m = (b1 % 4) * 256 + b2
        if e == 0 then return sign * ldexp(m, -24) end
        if e == 31 then return m == 0 and sign * huge or 0 / 0 end
        return sign * ldexp(m + 1024, e - 25)
    end

    local function single(b1, b2, b3, b4)
        local sign = b1 >= 128 and -1 or 1
        local e = (b1 % 128) * 2 + floor(b2 / 128)
        local m = ((b2 % 128) * 256 + b3) * 256 + b4
        if e == 0 then return sign * ldexp(m, -149) end
        if e == 255 then return m == 0 and sign * huge or 0 / 0 end
        return sign * ldexp(m + 8388608, e - 150)
    end

    local function double(b1, b2, b3, b4, b5, b6, b7, b8)
        local sign = b1 >= 128 and -1 or 1
        local e = (b1 % 128) * 16 + floor(b2 / 16)
        local m = (((b2 % 16) * 256 + b3) * 256 + b4) * 4294967296
            + ((b5 * 256 + b6) * 256 + b7) * 256 + b8
        if e == 0 then return sign * ldexp(m, -1074) end
        if e == 2047 then return m == 0 and sign * huge or 0 / 0 end
        return sign * ldexp(m + 4503599627370496, e - 1075)
    end

    local item
    function item(depth)
        if depth > 100 then error("DeserializeCBOR: nested too deeply", 0) end
        need(1)
        local ib = byte(s, pos)
        pos = pos + 1
        local major, info = floor(ib / 32), ib % 32
        if major == 0 then
            return readUint(info)
        elseif major == 1 then
            return -1 - readUint(info)
        elseif major == 2 or major == 3 then
            local n = readUint(info)
            need(n)
            local v = sub(s, pos, pos + n - 1)
            pos = pos + n
            return v
        elseif major == 4 then
            local n = readUint(info)
            local t = {}
            for i = 1, n do t[i] = item(depth + 1) end
            return t
        elseif major == 5 then
            local n = readUint(info)
            local t = {}
            for _ = 1, n do
                local k = item(depth + 1)
                local v = item(depth + 1)
                if k == nil then error("DeserializeCBOR: nil map key", 0) end
                t[k] = v
            end
            return t
        elseif major == 6 then
            readUint(info)
            return item(depth + 1)
        end
        -- major 7: simple values and floats
        if info == 20 then return false end
        if info == 21 then return true end
        if info == 22 or info == 23 then return nil end
        if info == 25 then
            need(2); local b1, b2 = byte(s, pos, pos + 1); pos = pos + 2
            return half(b1, b2)
        elseif info == 26 then
            need(4); local b1, b2, b3, b4 = byte(s, pos, pos + 3); pos = pos + 4
            return single(b1, b2, b3, b4)
        elseif info == 27 then
            need(8); local b1, b2, b3, b4, b5, b6, b7, b8 = byte(s, pos, pos + 7); pos = pos + 8
            return double(b1, b2, b3, b4, b5, b6, b7, b8)
        end
        error("DeserializeCBOR: unsupported simple value " .. info, 0)
    end

    function D.DeserializeCBOR(source)
        if type(source) ~= "string" then error("DeserializeCBOR: expected a string", 2) end
        s, pos, slen = source, 1, #source
        local ok, v = pcall(item, 0)
        local trailing = ok and pos <= slen
        s = nil
        if not ok then error(v, 2) end
        if trailing then error("DeserializeCBOR: trailing data", 2) end
        return v
    end

    return D
end
