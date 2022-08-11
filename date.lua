local utc = false
local format = "%c"
for _, v in ipairs{...} do
    if v == "-u" then utc = true
    elseif v:sub(1, 1) == "+" then format = v:sub(2) end
end
if utc then format = "!" .. format end
print(os.date(format))
