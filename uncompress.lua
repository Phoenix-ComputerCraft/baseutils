local filesystem = require "system.filesystem"
local util = require "system.util"

--[[
MIT License

Copyright (c) 2016 Rochet2

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local char = string.char
local type = type
local sub = string.sub
local tconcat = table.concat
local floor = math.floor
local byte = string.byte

local basedictdecompress = {}
for i = 0, 255 do
    local ic = char(i)
    basedictdecompress[i] = ic
end

local function dictAddB(str, dict, a, b)
    if a >= 256 then
        a, b = 0, b+1
        if b >= 256 then
            dict = {}
            b = 1
        end
    end
    dict[b*256+a] = str
    a = a+1
    return dict, a, b
end

local function decompress(input)
    if type(input) ~= "string" then
        return nil, "string expected, got "..type(input)
    end

    if #input < 1 then
        return nil, "invalid input - not a compressed string"
    end

    local len = #input

    if len < 3 then
        return nil, "invalid input - not a compressed string"
    end

    if sub(input, 1, 2) ~= "\x1F\x9D" then
        return nil, "invalid input - not a compressed string"
    end

    local nbits, buf, nbuf, pos = 9, 0, 0, 4
    local function readCode()
        while nbuf < nbits do
            if pos > len then return nil end
            buf = buf + byte(input, pos) * 2^nbuf
            pos = pos + 1
            nbuf = nbuf + 8
        end
        local res = buf % 2^nbits
        buf = floor(buf / 2^nbits)
        nbuf = nbuf - nbits
        return res
    end

    local dict = {}
    local a, b = 1, 1

    local result = {}
    local n = 1
    local last = readCode()
    result[n] = basedictdecompress[last] or dict[last]
    n = n+1
    while true do
        local code = readCode()
        if not code then break end
        local lastStr = basedictdecompress[last] or dict[last]
        if not lastStr then
            return nil, "could not find last from dict. Invalid input?"
        end
        local toAdd = basedictdecompress[code] or dict[code]
        if toAdd then
            result[n] = toAdd
            n = n+1
            dict, a, b = dictAddB(lastStr..sub(toAdd, 1, 1), dict, a, b)
        else
            local tmp = lastStr..sub(lastStr, 1, 1)
            result[n] = tmp
            n = n+1
            dict, a, b = dictAddB(tmp, dict, a, b)
        end
        if a == 256 and b == 2^(nbits - 8) - 1 then
            --if #res % nbits ~= 0 then res = res .. ("\0"):rep(nbits - (#res % nbits)) end
            local bits = nbuf % 8
            if bits ~= 0 then
                buf = floor(buf / 2^bits)
                nbuf = nbuf - bits
            end
            nbits = nbits + 1
        end
        last = code
    end
    return tconcat(result)
end

local args = assert(util.argparse({
    c = false,
    f = false,
    k = false,
    v = false
}, ...))
local data
if args[1] == "-" or args[1] == nil then data = io.read("*a")
else
    local file = assert(io.open(args[1], "rb"))
    data = file:read("*a")
    file:close()
end
local comp = assert(decompress(data))
if args.v then io.stderr:write(("%s: %.3g%%\n"):format(args[1], #comp / #data * 100)) end
if args.c then
    io.write(comp)
    return
end
local dest = args[1]:gsub("%.Z$", "")
if not args.f and filesystem.exists(dest) then
    io.write("replace file " .. dest .. "? (y/N) ")
    local response = io.read()
    if response ~= "Y" and response ~= "y" then return 1 end
end
local file = assert(io.open(dest, "wb"))
file:write(comp)
file:close()
if not args.k then os.remove(args[1]) end
