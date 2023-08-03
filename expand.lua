local util = require "system.util"
local args = assert(util.argparse({t = true}, ...))
args.t = args.t or "8"
if #args == 0 then args[1] = "-" end
local stops = {}
if args.t:match("^%d+$") then
    local t = tonumber(args.t)
    setmetatable(stops, {__index = function(_, n) return (math.ceil((n + 1) / t) * t) - n end})
elseif args.t:match("^[%d, ]+$") then
    local a = 1
    for tt in args.t:gmatch "%d+" do
        local t = tonumber(tt)
        assert(t > a, "expand: invalid tab stop format")
        for i = a, t - 1 do stops[i] = t - i end
        a = t
    end
    setmetatable(stops, {__index = function(_, n) return 1 end})
else error("expand: invalid tab stop format") end
for _, v in ipairs(args) do
    for line in io.lines(v ~= "-" and v or nil) do
        print(line:gsub("()\t", function(n) return (" "):rep(stops[n]) end))
    end
end