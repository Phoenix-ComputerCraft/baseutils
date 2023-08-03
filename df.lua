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
if args.P then
    local bs = args.k and 1024 or 512
    print("Filesystem " .. bs .. "-blocks Used Available Capacity Mounted on")
    for _, v in ipairs(info) do
        print(("%s %d %d %d %d%% %s"):format(
            v.source,
            math.ceil(v.stat.capacity / bs),
            math.ceil((v.stat.capacity - v.stat.freeSpace) / bs),
            math.ceil(v.stat.freeSpace / bs),
            math.floor((v.stat.capacity - v.stat.freeSpace) / v.stat.capacity * 100),
            v.path
        ))
    end
elseif args.h then
    local function sz(n)
        if n >= 1000000000000 then return ("%.3gT"):format(n / 1000000000000)
        elseif n >= 1000000000 then return ("%.3gG"):format(n / 1000000000)
        elseif n >= 1000000 then return ("%.3gM"):format(n / 1000000)
        elseif n >= 1000 then return ("%.3gK"):format(n / 1000)
        else return ("%.3g "):format(n) end
    end
    print("Filesystem\tSize\tUsed\tAvail\tUse%\tMounted on")
    for _, v in ipairs(info) do
        print(("%s\t%s\t%s\t%s\t%3d%%\t%s"):format(
            v.source .. (#v.source < 8 and "\t" or ""),
            sz(v.stat.capacity),
            sz(v.stat.capacity - v.stat.freeSpace),
            sz(v.stat.freeSpace),
            math.floor((v.stat.capacity - v.stat.freeSpace) / v.stat.capacity * 100),
            v.path
        ))
    end
else
    local bs = args.k and 1024 or 512
    print("Filesystem\tSize\tUsed\tAvail\tUse%\tMounted on")
    for _, v in ipairs(info) do
        print(("%s\t%d\t%d\t%d\t%d%%\t%s"):format(
            v.source .. (#v.source < 8 and "\t" or ""),
            math.ceil(v.stat.capacity / bs),
            math.ceil((v.stat.capacity - v.stat.freeSpace) / bs),
            math.ceil(v.stat.freeSpace / bs),
            math.floor((v.stat.capacity - v.stat.freeSpace) / v.stat.capacity * 100),
            v.path
        ))
    end
end