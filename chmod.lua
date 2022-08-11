-- Different mode syntax:
-- (user)?[+-=][rwxs]+(,(user)?[+-=][rwxs]+)*
-- Octal permissions are retained for compatibility, but group perms are ignored
local filesystem = require "system.filesystem"
local args = {...}
local recursive = false
if args[1] == "-R" then
    recursive = true
    table.remove(args, 1)
end
local mode = table.remove(args, 1)
local oct = tonumber(mode, 8)
local function setmode(file)
    local stat = filesystem.stat(file)
    if oct then
        filesystem.chmod(file, stat.owner, bit32.band(bit32.rshift(oct, 6), 7))
        filesystem.chmod(file, nil, bit32.band(oct, 7))
    else
        for perm in mode:gmatch "[^,]+" do
            local user, arg = perm:match "^([^%+%-=]*)([%+%-=][rwxs]+)$"
            if not user then error("chmod: invalid mode: " .. perm) end
            if user == "" then user = nil end
            filesystem.chmod(file, user, arg)
        end
    end
    if recursive and stat.type == "directory" then
        for _, v in ipairs(filesystem.list(file)) do
            setmode(filesystem.combine(file, v))
        end
    end
end
for _, file in ipairs(args) do setmode(file) end