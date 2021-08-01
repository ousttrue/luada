---@param src string
---@return string
local function normalize_path(src)
    local drive, path = src:match("^(%w:)(.*)")
    if not drive then
        drive = ""
        path = src
    end
    return drive:upper() .. path:gsub("/", "\\")
end

print(normalize_path("c:/a/b/c.lua"))
