--[[
	lurk loader — paste this into Matcha:

	loadstring(game:HttpGet("https://raw.githubusercontent.com/90dvd/lurk/main/loader.lua?t=" .. tick()))()

	If GitHub CDN is stale, load by commit (always fresh):

	loadstring(game:HttpGet("https://raw.githubusercontent.com/90dvd/lurk/9275ade/Scripts/Bedwars.lua?t=" .. tick()))()
]]

local LOADER_VERSION = "5"
local BASE = "https://raw.githubusercontent.com/90dvd/lurk/main/Scripts/Bedwars.lua"
-- Bypasses raw.githubusercontent.com/main/ CDN lag (update on each release).
local FALLBACK = "https://raw.githubusercontent.com/90dvd/lurk/9275ade/Scripts/Bedwars.lua"
local CACHE = "lurk/Bedwars.lua"
local MIN_VERSION = "1.6.7"

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

local function parseVersion(source)
	if type(source) ~= "string" then
		return nil
	end
	return source:match('SCRIPT_VERSION = "([%d%.]+)"')
end

local function versionAtLeast(version, minimum)
	if not version or not minimum then
		return false
	end
	local function parts(text)
		local numbers = {}
		for part in text:gmatch("%d+") do
			numbers[#numbers + 1] = tonumber(part)
		end
		return numbers
	end
	local left = parts(version)
	local right = parts(minimum)
	for index = 1, math.max(#left, #right) do
		local a = left[index] or 0
		local b = right[index] or 0
		if a > b then
			return true
		end
		if a < b then
			return false
		end
	end
	return true
end

local function acceptDownload(body)
	if not body then
		return nil, nil
	end
	local version = parseVersion(body)
	if versionAtLeast(version, MIN_VERSION) then
		return body, version
	end
	return nil, version
end

local source = nil
for attempt = 1, 5 do
	local body, version = acceptDownload(fetch(BASE .. "?t=" .. tick() .. "&loader=" .. LOADER_VERSION .. "&try=" .. attempt))
	if body then
		source = body
		print("[lurk] downloaded v" .. tostring(version) .. " (main)")
		break
	end
	if version then
		warn("[lurk] CDN still serving v" .. tostring(version) .. " (need v" .. MIN_VERSION .. "+), retry " .. attempt .. "/5")
	end
	wait(0.5)
end

if not source then
	local body, version = acceptDownload(fetch(FALLBACK .. "?t=" .. tick() .. "&loader=" .. LOADER_VERSION .. "&fb=1"))
	if body then
		source = body
		print("[lurk] downloaded v" .. tostring(version) .. " (commit fallback)")
	else
		warn("[lurk] main CDN stale" .. (version and (" (v" .. version .. ")") or "") .. ", commit fallback failed too")
	end
end

if source then
	pcall(function()
		writefile(CACHE, source)
	end)
else
	warn("[lurk] download failed — try commit URL:")
	warn('[lurk] loadstring(game:HttpGet("' .. FALLBACK .. '?t=" .. tick()))()')
end

if not source then
	local cached
	pcall(function()
		if isfile(CACHE) then
			cached = readfile(CACHE)
		end
	end)
	local cachedVersion = parseVersion(cached)
	if cached and versionAtLeast(cachedVersion, MIN_VERSION) then
		warn("[lurk] using cache v" .. tostring(cachedVersion))
		source = cached
	else
		if cachedVersion then
			warn("[lurk] cache is v" .. tostring(cachedVersion) .. " but need v" .. MIN_VERSION .. "+ — delete lurk/Bedwars.lua or fix HttpGet")
		end
	end
end

if source and #source > 0 then
	loadstring(source, "lurk")()
else
	warn("[lurk] no source — open https://github.com/90dvd/lurk")
end
