local args = {...}

local month_names = {"january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"}
local month_lengths = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local function parseMonth(mon)
    if #mon < 3 then return end
    local s = "^" .. mon:lower()
    for i, v in ipairs(month_names) do if v:match(s) then return i end end
end

local date = os.date("*t")

local month, year
if args[2] then month, year = assert(tonumber(args[1]) or parseMonth(args[1]), "cal: " .. args[1] .. " is neither a month number (1..12) nor a name"), assert(tonumber(args[2]), "cal: year `" .. args[2] .. "' not in range 1..9999")
elseif args[1] then year = assert(tonumber(args[1]), "cal: year `" .. args[1] .. "' not in range 1..9999")
else month, year = date.month, date.year end
if year < 1 or year > 9999 then error("cal: year `" .. year .. "' not in range 1..9999") end
if month and (month < 1 or month > 12) then error("cal: " .. month .. " is neither a month number (1..12) nor a name") end

if month then
    local header = month_names[month]:gsub("^.", string.upper) .. " " .. year
    header = (" "):rep(math.floor((20 - #header) / 2)) .. header
    print(header)
    print("Su Mo Tu We Th Fr Sa")
    local x = os.date("*t", os.time({year = year, month = month, day = 1})).wday
    io.stdout:write(("   "):rep(x - 1))
    local len = month_lengths[month]
    if month == 2 and ((year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0) then len = 29 end
    for i = 1, len do
        if date.year == year and date.month == month and date.day == i then io.stdout:write(("\x1b[7m%2d\x1b[7m "):format(i))
        else io.stdout:write(("%2d "):format(i)) end
        x = x + 1
        if x > 7 then
            print()
            x = 1
        end
    end
    if x > 1 then print() end
else
    print(("                              %4d"):format(year))
    local function generateMonth(m)
        local header = month_names[m]:gsub("^.", string.upper)
        header = (" "):rep(math.floor((20 - #header) / 2)) .. header .. (" "):rep(math.ceil((20 - #header) / 2))
        coroutine.yield(header)
        coroutine.yield("Su Mo Tu We Th Fr Sa")
        local x = os.date("*t", os.time({year = year, month = m, day = 1})).wday
        local line = ("   "):rep(x - 1)
        local len = month_lengths[m]
        if m == 2 and ((year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0) then len = 29 end
        for i = 1, len do
            if date.year == year and date.month == m and date.day == i then line = line .. ("\x1b[7m%2d\x1b[7m "):format(i)
            else line = line .. ("%2d "):format(i) end
            x = x + 1
            if x > 7 then
                coroutine.yield(line:sub(1, -2))
                line, x = "", 1
            end
        end
        if x > 1 then coroutine.yield(line:sub(1, -2) .. (" "):rep(20 - #line + 1)) end
    end
    for i = 0, 3 do
        local coro1, coro2, coro3 = coroutine.create(function() generateMonth(i*3+1) end), coroutine.create(function() generateMonth(i*3+2) end), coroutine.create(function() generateMonth(i*3+3) end)
        while coroutine.status(coro1) == "suspended" or coroutine.status(coro2) == "suspended" or coroutine.status(coro3) == "suspended" do
            local line = ""
            local ok, res = coroutine.resume(coro1)
            if ok and res then line = res .. "  " end
            ok, res = coroutine.resume(coro2)
            if ok and res then line = line .. res .. "  " end
            ok, res = coroutine.resume(coro3)
            if ok and res then line = line .. res end
            print(line)
        end
    end
end