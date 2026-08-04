--[[
	luak loader

	Replace OWNER and REPO below with your GitHub user and repository name, then
	paste the one-liner into Matcha:

	loadstring(game:HttpGet("https://raw.githubusercontent.com/OWNER/REPO/refs/heads/main/Scripts/Bedwars.lua"))()

	The version below does the same but survives a failed download. HttpGet never
	raises — it returns "" — and loadstring hands back a callable function even
	for broken source, printing the syntax error only once that function is
	called. An empty body therefore has to be caught here, or the loader silently
	does nothing.
]]

local URL = "https://raw.githubusercontent.com/OWNER/REPO/refs/heads/main/Scripts/Bedwars.lua"
local CACHE = "luak/Bedwars.lua"

local source

local downloaded = pcall(function()
	local body = game:HttpGet(URL)
	if type(body) == "string" and #body > 0 then
		source = body
	end
end)

if downloaded and source then
	pcall(function()
		writefile(CACHE, source)
	end)
else
	warn("[luak] download failed, falling back to cache")
	pcall(function()
		if isfile(CACHE) then
			source = readfile(CACHE)
		end
	end)
end

if source and #source > 0 then
	loadstring(source, "luak")()
else
	warn("[luak] no source available — check the URL and your connection")
end
