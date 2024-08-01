local args = { ... }
if type(args[1]) ~= "string" or type(args[2]) ~= "string" then
    print("Usage: attach <side> <type> [options...]")
else
    if tonumber(args[3]) ~= nil then args[3] = tonumber(args[3]) end
    local ok, err, err2 = coroutine.yield("syscall", "attach", args[1], args[2], args[3])
    if not ok then io.stderr:write("Could not attach peripheral" .. (err and ": " .. err or "") .. "\n")
    elseif not err then io.stderr:write("Could not attach peripheral" .. (err2 and ": " .. err2 or "") .. "\n") end
end