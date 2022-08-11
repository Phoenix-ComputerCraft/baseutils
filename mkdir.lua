local util = require "system.util"
local filesystem = require "system.filesystem"
local args = assert(util.argparse({p = false, m = true}, ...))
local mode = args.m
local oct = tonumber(mode, 8)
local function setmode(file)
    local stat = filesystem.stat(file)
    if oct then
        filesystem.chmod(file, stat.owner, bit32.band(bit32.rshift(oct, 6), 7))
        filesystem.chmod(file, nil, bit32.band(oct, 7))
    else
        for perm in mode:gmatch "[^,]+" do
            local user, arg = perm:match "^([^%+%-=]*)([%+%-=][rwxs]+)$"
            if not user then error("mkdir: invalid mode: " .. perm) end
            if user == "" then user = nil end
            filesystem.chmod(file, user, arg)
        end
    end
end
for _, v in ipairs(args) do
    if not args.p and not filesystem.isDir(filesystem.dirname(v)) then error("mkdir: " .. filesystem.dirname(v) .. ": Not a directory") end
    filesystem.mkdir(v)
    if mode then setmode(v) end
end
