-- TODO: real expr parser
print(assert(load(table.concat({...}, " "):gsub("&", " and "):gsub("|", " or "), "=expr", "t", {}))())