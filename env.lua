local process = require "system.process"
local args = {...}
local env = process.getenv()
while #args > 0 do
    if args[1] == "-i" then
        for k in pairs(env) do env[k] = nil end
        table.remove(args, 1)
    elseif args[1]:find("=") then
        local k, v = table.remove(args, 1):match "^([^=]+)=(.*)$"
        env[k] = v
    else break end
end
if #args == 0 then for k, v in pairs(env) do print(k .. "=" .. v) end
else return process.execp(table.unpack(args)) end