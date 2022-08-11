local syscall = setmetatable({}, {__index = function(self, idx)
    return function(...)
        local retval = table.pack(coroutine.yield("syscall", idx, ...))
        if retval[1] then return table.unpack(retval, 2, retval.n)
        else error(retval[2], 2) end
    end
end, __newindex = function() end})

local pids = syscall.getplist()
print("PID\tTTY\tTIME\t\tCMD")
for _, v in ipairs(pids) do
    local info = syscall.getpinfo(v)
    if info then
        print(v, info.stdout and "tty" .. info.stdout or "?", ("%02d:%02d:%02d.%03d"):format(math.floor(info.cputime / 3600), math.floor(info.cputime / 60), math.floor(info.cputime), math.floor(info.cputime * 1000) % 1000), info.name)
    end
end