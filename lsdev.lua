local hardware = require "system.hardware"
local util = require "system.util"

local args = assert(util.argparse({v = false}, ...))

local function list(node, level)
    for _, v in ipairs(hardware.children(node)) do
        local info = hardware.info(node .. "/" .. v)
        if args.v then
            print(("%sDevice %s (%s): %s"):format((" "):rep(level), v, info.uuid, info.displayName or ""))
            io.write((" "):rep(level) .. "Types: ")
            local start = true
            for k, w in pairs(info.types) do io.write((start and "" or ", ") .. k .. " (" .. w .. ")") start = false end
            print()
        else
            print(("%sDevice %s: %s"):format((" "):rep(level), v, info.displayName or ""))
        end
        list(node .. "/" .. v, level + 2)
    end
end

local info = hardware.info("/")
if args.v then
    print(("Device / (%s): %s"):format(info.uuid, info.displayName or ""))
    io.write("Types: ")
    local start = true
    for k, w in pairs(info.types) do io.write((start and "" or ", ") .. k .. " (" .. w .. ")") start = false end
    print()
else
    print(("Device /: %s"):format(info.displayName or ""))
end
list("/", 2)