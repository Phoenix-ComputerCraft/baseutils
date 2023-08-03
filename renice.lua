local process = require "system.process"
local util = require "system.util"
local args = assert(util.argparse({n = "number"}, ...))
if not args[1] or not args.n then error("Usage: renice -n <increment> <PID...>") end
for _, v in ipairs(args) do
    v = tonumber(v) or error("renice: argument " .. v .. " is not a PID")
    process.nice(args.n, v)
end
