--[[
	lurk loader — paste this into Matcha:

	loadstring(game:HttpGet("https://raw.githubusercontent.com/90dvd/lurk/refs/heads/main/loader.lua?t=" .. tick()))()

	Or the direct script URL (same cache-bust trick):

	loadstring(game:HttpGet("https://raw.githubusercontent.com/90dvd/lurk/refs/heads/main/Scripts/Bedwars.lua?t=" .. tick()))()
]]

local BASE = "https://raw.githubusercontent.com/90dvd/lurk/refs/heads/main/Scripts/Bedwars.lua"
local CACHE = "lurk/Bedwars.lua"

local function fetch(url)
	local body
	local ok = pcall(function()
		body = game:HttpGet(url)
	end)
	if ok and type(body) == "string" and #body > 0 then
		return body
	end
	return nil
end

-- ?t= bypasses raw.githubusercontent.com CDN caching stale files.
local source = fetch(BASE .. "?t=" .. tick())

if source then
	pcall(function()
		writefile(CACHE, source)
	end)
else
	warn("[lurk] download failed, trying cache")
	pcall(function()
		if isfile(CACHE) then
			source = readfile(CACHE)
		end
	end)
end

if source and #source > 0 then
	loadstring(source, "lurk")()
else
	warn("[lurk] no source — check https://github.com/90dvd/lurk")
end
