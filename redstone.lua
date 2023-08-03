local hardware = require "system.hardware"
local util = require "system.util"
local args = {...}
if args[1] == "probe" then
    local bundled = false
    print("Redstone inputs:")
    local t = {}
    for _, v in ipairs(hardware.children("/redstone")) do
        local side = hardware.wrap("/redstone/" .. v)
        local b = side.bundledInput
        if b and b > 0 then bundled = true end
        local r = side.input
        if r then t[#t+1] = v .. " (" .. r .. ")" end
    end
    if #t > 0 then print(table.concat(t, ", "))
    else print("None.") end
    if bundled then
        print()
        print("Bundled inputs:")
        local colors = {[0] = "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray", "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black"}
        for _, v in ipairs(hardware.children("/redstone")) do
            local side = hardware.wrap("/redstone/" .. v)
            local b = side.bundledInput
            if b and b > 0 then
                io.write(v .. ": ")
                local t = {}
                for i = 0, 15 do
                    if bit32.btest(b, 2^i) then t[#t+1] = colors[i] end
                end
                print(table.concat(t, ", "))
            end
        end
    end
elseif args[1] == "set" then
    if #args < 3 then error("Usage: redstone set <side> [color] <value>") end
    local side = assert(hardware.wrap("/redstone/" .. args[2]), "Not a side")
    if #args >= 4 then
        if not side.bundledOutput then error("Bundled output is not available") end
        local colors = {
            white = 0,
            orange = 1,
            magenta = 2,
            lightBlue = 3,
            yellow = 4,
            lime = 5,
            pink = 6,
            gray = 7,
            grey = 7,
            lightGray = 8,
            lightGrey = 8,
            cyan = 9,
            purple = 10,
            blue = 11,
            brown = 12,
            green = 13,
            red = 14,
            black = 15
        }
        local color = 2^assert(colors[args[3]], "Invalid color")
        if args[4]:lower() == "true" then side.bundledOutput = bit32.bor(side.bundledOutput, color)
        else side.bundledOutput = bit32.band(side.bundledOutput, bit32.bnot(color)) end
    else
        local value
        if args[3]:lower() == "true" then value = 15
        else value = tonumber(args[3]) or 0 end
        side.output = value
    end
elseif args[1] == "pulse" then
    if #args < 4 then error("Usage: redstone pulse <side> <count> <period>") end
    local side = assert(hardware.wrap("/redstone/" .. args[2]), "Not a side")
    local count = tonumber(args[3]) or 1
    local period = tonumber(args[4]) or 0.5
    for _ = 1, count do
        side.output = true
        util.sleep(period / 2)
        side.output = false
        util.sleep(period / 2)
    end
else
    print("Usage: redstone <probe|set|pulse> ...")
end