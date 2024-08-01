local filesystem = require "system.filesystem"
local util = require "system.util"

local args = assert(util.argparse({k = false, P = false, t = false, h = false}, ...))
local mounts = filesystem.mountlist()
local info = {}
if #args == 0 then for i, v in ipairs(mounts) do info[i], v.stat = v, filesystem.stat(v.path) end
else
    for i, v in ipairs(args) do
        local stat, err = filesystem.stat(v)
        if stat then for _, m in ipairs(mounts) do if m.path == stat.mountpoint then info[i], m.stat = m, stat break end end
        else io.stderr:write("df: could not stat " .. v .. ": " .. (err or "") .. "\n") end
    end
end
local function inf(n) if n == math.huge then return "inf" elseif n ~= n then return "nan" else return tostring(n) end end
if args.P then
    local bs = args.k and 1024 or 512
    print("Filesystem " .. bs .. "-blocks Used Available Capacity Mounted on")
    for _, v in ipairs(info) do
        print(("%s %s %s %s %s%% %s"):format(
            v.source,
            inf(math.ceil(v.stat.capacity / bs)),
            inf(math.ceil((v.stat.capacity - v.stat.freeSpace) / bs)),
            inf(math.ceil(v.stat.freeSpace / bs)),
            inf(math.floor((v.stat.capacity - v.stat.freeSpace) / v.stat.capacity * 100)),
            v.path
        ))
    end
elseif args.h then
    local function sz(n)
        if n == math.huge then return "inf"
        elseif n ~= n then return "nan"
        elseif n >= 1000000000000 then return ("%.3gT"):format(n / 1000000000000)
        elseif n >= 1000000000 then return ("%.3gG"):format(n / 1000000000)
        elseif n >= 1000000 then return ("%.3gM"):format(n / 1000000)
        elseif n >= 1000 then return ("%.3gK"):format(n / 1000)
        else return ("%.3g "):format(n) end
    end
    print("Filesystem\tSize\tUsed\tAvail\tUse%\tMounted on")
    for _, v in ipairs(info) do
        print(("%s\t%s\t%s\t%s\t%s%%\t%s"):format(
            v.source .. (#v.source < 8 and "\t" or ""),
            sz(v.stat.capacity),
            sz(v.stat.capacity - v.stat.freeSpace),
            sz(v.stat.freeSpace),
            inf(math.floor((v.stat.capacity - v.stat.freeSpace) / v.stat.capacity * 100)),
            v.path
        ))
    end
else
    local bs = args.k and 1024 or 512
    print("Filesystem\tSize\tUsed\tAvail\tUse%\tMounted on")
    for _, v in ipairs(info) do
        print(("%s\t%s\t%s\t%s\t%s%%\t%s"):format(
            v.source .. (#v.source < 8 and "\t" or ""),
            inf(math.ceil(v.stat.capacity / bs)),
            inf(math.ceil((v.stat.capacity - v.stat.freeSpace) / bs)),
            inf(math.ceil(v.stat.freeSpace / bs)),
            inf(math.floor((v.stat.capacity - v.stat.freeSpace) / v.stat.capacity * 100)),
            v.path
        ))
    end
end