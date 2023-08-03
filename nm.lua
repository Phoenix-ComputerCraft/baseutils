local filesystem = require "system.filesystem"
local process = require "system.process"
local util = require "system.util"

local args = assert(util.argparse({
    A = false,
    e = false,
    f = false,
    g = false,
    o = false,
    P = false,
    t = true,
    u = false,
    v = false,
    x = false
}, ...))
if args.t then assert(args.t:match "^[dox]$", "nm: invalid option '" .. args.t .. "' for argument -t") end
if #args == 0 then error("nm: missing file operand") end
if args.o then args.t = "o" end
args.t = args.t or (args.P and "d" or "x")
local fmt = {
    d = "%s%s %s %d %d",
    o = "%s%s %s %o %o",
    x = "%s%s %s %x %x"
}

for _, v in ipairs(args) do
    local libs = {}
    local require = require
    local symbols = {}
    local env = setmetatable({
        require = function(name)
            local lib = require(name)
            local info = {name = name, lib = lib, used = {}}
            libs[#libs+1] = info
            return setmetatable({}, {__index = function(_, idx)
                info.used[idx] = true
                return lib[idx]
            end, __newindex = function(_, idx, val)
                info.used[idx] = true
                lib[idx] = val
            end})
        end,
        __scrapelocals = function()
            if not args.g and not args.e then
                for i = 1, math.huge do
                    local k, l = debug.getlocal(2, i)
                    if not k then break end
                    local tt = type(l)
                    if tt == "function" then symbols[#symbols+1] = {lib = v, type = "t", name = k, value = tonumber(tostring(l):match(": (%x+)"), 16), size = #string.dump(l)}
                    elseif tt == "string" then symbols[#symbols+1] = {lib = v, type = "d", name = k, value = i, size = #l}
                    elseif tt == "number" then symbols[#symbols+1] = {lib = v, type = "d", name = k, value = i, size = 8}
                    elseif tt == "boolean" then symbols[#symbols+1] = {lib = v, type = "d", name = k, value = i, size = 1}
                    elseif tt == "nil" then symbols[#symbols+1] = {lib = v, type = "d", name = k, value = i, size = 0}
                    else symbols[#symbols+1] = {lib = v, type = "d", name = k, value = tonumber(tostring(l):match(": (%x+)"), 16), size = #l or 8} end
                end
            end
        end
    }, {__index = _G})
    local file, err = filesystem.open(v, "r")
    if file then
        local data = file.readAll()
        file.close()
        local lastreturn
        repeat
            local n = data:find("%f[A-Za-z0-9_]return%f[^A-Za-z0-9_]", lastreturn and lastreturn + 1)
            if n then lastreturn = n end
        until not n
        if lastreturn and data:find("%f[A-Za-z0-9_]end%f[^A-Za-z0-9_]", lastreturn) then lastreturn = nil end
        if lastreturn then data = data:sub(1, lastreturn - 1) .. " __scrapelocals() " .. data:sub(lastreturn)
        else data = data .. " __scrapelocals()" end
        local fn, err = load(data, "@" .. v, nil, env)
        if fn then
            local dir = process.getcwd()
            process.chdir(filesystem.dirname(v))
            local ok, res = pcall(fn, filesystem.basename(v):gsub("%.lua$", ""), v)
            process.chdir(dir)
            if ok then
                local t = type(res)
                if not args.u then
                    if t == "function" then symbols[#symbols+1] = {lib = v, type = "T", name = "", value = tonumber(tostring(res):match(": (%x+)"), 16), size = #string.dump(res)}
                    elseif t == "table" then
                        local i = 1
                        for k, l in pairs(res) do
                            local tt = type(l)
                            if tt == "function" then symbols[#symbols+1] = {lib = v, type = "T", name = k, value = tonumber(tostring(l):match(": (%x+)"), 16), size = #string.dump(l)}
                            elseif tt == "string" then symbols[#symbols+1] = {lib = v, type = "D", name = k, value = i, size = #l}
                            elseif tt == "number" then symbols[#symbols+1] = {lib = v, type = "D", name = k, value = i, size = 8}
                            elseif tt == "boolean" then symbols[#symbols+1] = {lib = v, type = "D", name = k, value = i, size = 1}
                            elseif tt == "nil" then symbols[#symbols+1] = {lib = v, type = "D", name = k, value = i, size = 0}
                            else symbols[#symbols+1] = {lib = v, type = "D", name = k, value = tonumber(tostring(l):match(": (%x+)"), 16), size = #l or 8} end
                            i=i+1
                        end
                    end
                end
            else io.stderr:write("nm: could not require " .. v .. ": " .. res .. "\n") end
            if not args.u then
                for k, l in pairs(env) do if k ~= "require" and k ~= "__scrapelocals" and k ~= "_ENV" and k ~= "_G" then
                    local tt = type(l)
                    if tt == "function" then symbols[#symbols+1] = {lib = v, type = "A", name = k, value = tonumber(tostring(l):match(": (%x+)"), 16), size = #string.dump(l)}
                    elseif tt == "string" then symbols[#symbols+1] = {lib = v, type = "A", name = k, value = i, size = #l}
                    elseif tt == "number" then symbols[#symbols+1] = {lib = v, type = "A", name = k, value = i, size = 8}
                    elseif tt == "boolean" then symbols[#symbols+1] = {lib = v, type = "A", name = k, value = i, size = 1}
                    elseif tt == "nil" then symbols[#symbols+1] = {lib = v, type = "A", name = k, value = i, size = 0}
                    else symbols[#symbols+1] = {lib = v, type = "A", name = k, value = tonumber(tostring(l):match(": (%x+)"), 16), size = #l or 8} end
                end end
            end
            if not args.g and not args.e then
                for _, lib in ipairs(libs) do
                    for k in pairs(lib.used) do
                        symbols[#symbols+1] = {lib = lib.name, type = "U", name = k}
                    end
                end
            end
            if args.v then table.sort(symbols, function(a, b) return (a.value or -1) < (b.value or -1) end)
            else table.sort(symbols, function(a, b) return a.name < b.name end) end
            if #args > 1 then print(v .. ":") end
            for _, s in ipairs(symbols) do
                if args.P then
                    print(fmt[args.t]:format(args.A and s.lib .. ": " or "", s.name, s.type, s.value or 0, s.size or 0))
                else
                    if args.A then io.write(s.name .. ":") end
                    if s.value then io.write(("%016x "):format(s.value)) else io.write("         ") end
                    print(s.type .. " " .. s.name)
                end
            end
        else io.stderr:write("nm: could not load " .. v .. ": " .. err .. "\n") end
    else io.stderr:write("nm: could not load " .. v .. ": " .. err .. "\n") end
end