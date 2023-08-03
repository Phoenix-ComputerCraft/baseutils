local filesystem = require "system.filesystem"
local util = require "system.util"

local args = assert(util.argparse({a = false, s = false, k = false, h = false, x = false, H = false, L = false}, ...))
if #args == 0 then args[1] = "." end
local retval = 0

local function sz(n)
    if args.h then
        if n >= 1000000000000 then return ("%.3gT"):format(n / 1000000000000)
        elseif n >= 1000000000 then return ("%.3gG"):format(n / 1000000000)
        elseif n >= 1000000 then return ("%.3gM"):format(n / 1000000)
        elseif n >= 1000 then return ("%.3gK"):format(n / 1000)
        else return ("%.3g "):format(n) end
    elseif args.k then return math.ceil(n / 1024)
    else return math.ceil(n / 512) end
end

local function search(path, mp, first)
    local stat, err = filesystem.stat(path, not ((first and args.H) or args.L))
    if stat then
        if mp == true then mp = stat.mountpoint end
        if mp and mp ~= stat.mountpoint then return 0 end
        if stat.type == "directory" then
            local size = 0
            for _, v in ipairs(filesystem.list(path)) do
                size = size + search(filesystem.combine(path, v), mp)
            end
            if not args.s then print(sz(size), path) end
            return size
        else
            if args.a and not args.s then print(sz(stat.size), path) end
            return stat.size
        end
    else
        io.stderr:write("du: could not stat " .. path .. ": " .. (err or "") .. "\n")
        retval = 1
        return 0
    end
end

for _, v in ipairs(args) do
    local size = search(v, args.x, true)
    if args.s then print(sz(size), v) end
end
return retval