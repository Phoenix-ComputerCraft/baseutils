local filesystem = require "system.filesystem"
local util = require "system.util"
local args = assert(util.argparse({m = true}, ...))
local function setmode(file)
    local stat = filesystem.stat(file, true)
    local oct = tonumber(args.m, 8)
    if oct then
        filesystem.chmod(file, stat.owner, bit32.band(bit32.rshift(oct, 6), 7))
        filesystem.chmod(file, nil, bit32.band(oct, 7))
    else
        for perm in args.m:gmatch "[^,]+" do
            local user, arg = perm:match "^([^%+%-=]*)([%+%-=][rwxs]+)$"
            if not user then error("chmod: invalid mode: " .. perm) end
            if user == "" then user = nil end
            filesystem.chmod(file, user, arg)
        end
    end
end
for _, v in ipairs(args) do
    filesystem.mkfifo(v)
    if args.m then setmode(v) end
end