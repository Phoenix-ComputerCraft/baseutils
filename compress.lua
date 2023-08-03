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
local floor = math.floor

local basedictcompress = {}
for i = 0, 255 do
    local ic = char(i)
    basedictcompress[ic] = i
end

local function dictAddA(str, dict, a, b)
    if a >= 256 then
        a, b = 0, b+1
        if b >= 256 then
            dict = {}
            b = 1
        end
    end
    dict[str] = b * 256 + a
    a = a+1
    return dict, a, b
end

local function compress(input, maxb)
    if type(input) ~= "string" then
        return nil, "string expected, got "..type(input)
    end
    local len = #input

    local dict = {}
    local a, b = 1, 1

    local word = ""
    local nbits, res, buf, nbuf = 9, "\x1F\x9D\x90", 0, 0
    for i = 1, len do
        local c = sub(input, i, i)
        local wc = word..c
        if not (basedictcompress[wc] or dict[wc]) then
            local write = basedictcompress[word] or dict[word]
            if not write then
                return nil, "algorithm error, could not fetch word"
            end
            buf = buf + write * 2^nbuf
            nbuf = nbuf + nbits
            while nbuf >= 8 do
                res = res .. char(buf % 256)
                buf = floor(buf / 256)
                nbuf = nbuf - 8
            end
            if b < maxb then
                dict, a, b = dictAddA(wc, dict, a, b)
                if a == 1 and b == 2^(nbits - 8) then
                    if nbuf > 0 then res = res .. char(buf % 256) end
                    --if #res % nbits ~= 0 then res = res .. ("\0"):rep(nbits - (#res % nbits)) end
                    buf = 0
                    nbuf = 0
                    nbits = nbits + 1
                end
            end
            word = c
        else
            word = wc
        end
    end
    buf = buf + (basedictcompress[word] or dict[word]) * 2^nbuf
    nbuf = nbuf + nbits
    while nbuf >= 8 do
        res = res .. char(buf % 256)
        buf = floor(buf / 256)
        nbuf = nbuf - 8
    end
    if nbuf > 0 then res = res .. char(buf) end
    return res
end

local args = assert(util.argparse({
    b = "number",
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
local comp = compress(data, args.b and 2^(args.b - 8) or 256)
if args.v then io.stderr:write(("%s: %.3g%%\n"):format(args[1], #comp / #data * 100)) end
if args.c then
    io.write(comp)
    return
end
if not args.f and #comp > #data then return 2 end
if not args.f and filesystem.exists(args[1] .. ".Z") then
    io.write("replace file " .. args[1] .. ".Z? (y/N) ")
    local response = io.read()
    if response ~= "Y" and response ~= "y" then return 1 end
end
local file = assert(io.open(args[1] .. ".Z", "wb"))
file:write(comp)
file:close()
if not args.k then os.remove(args[1]) end
