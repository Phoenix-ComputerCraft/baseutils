local ipc = require "system.ipc"
local args = {}
local sig = ipc.signal.SIGTERM
local nextArg
for _, v in ipairs{...} do
    if nextArg then sig, nextArg = ipc.signal["SIG" .. v] or sig, nil
    elseif v:sub(1, 1) == "-" then
        v = v:sub(2)
        if v == "s" then nextArg = true
        elseif v == "l" then args.l = true
        elseif ipc.signal["SIG" .. v] then sig = ipc.signal["SIG" .. v]
        elseif tonumber(v) then sig = tonumber(v)
        else error("unknown argument " .. v) end
    else args[#args+1] = assert(tonumber(v), "invalid PID " .. v) end
end
if args.l then
    if args[1] then
        for k, v in pairs(ipc.signal) do if v == args[1] then print(k:sub(4)) return end end
        print("UNKNOWN")
        return false
    else
        for k, v in pairs(ipc.signal) do io.write(k:sub(4) .. " ") end
        print()
    end
else for _, v in ipairs(args) do ipc.kill(v, sig) end end
