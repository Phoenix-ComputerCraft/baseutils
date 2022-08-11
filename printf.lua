local args = {...}
local format = table.remove(args, 1)
local opts = {}
for f in format:gmatch "%%[%-%+ #0]?%d*%.?%d*[jzt]?[diuoxXfFeEgGaAcsq]" do
    local t = f:sub(-1, -1)
    local n = #opts+1
    local v = assert(args[n], "printf: missing argument for " .. f)
    if t == "q" or t == "s" then opts[n] = v
    else opts[n] = assert(tonumber(v), "printf: argument " .. v .. " not a number") end
end
print(format:format(table.unpack(opts)))
