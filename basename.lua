local path = assert(..., "basename: missing path")
if path == "" then print "."
elseif path:match "^/+$" then print "/"
else
    local s = path:gsub("/+$", ""):match "[^/]+$"
    local suffix = select(2, ...)
    if suffix and s ~= suffix then s = s:gsub(suffix .. "$", "") end
    print(s)
end