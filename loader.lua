--[[
	lurk loader — paste this into Matcha:

	loadstring(game:HttpGet("https://raw.githubusercontent.com/90dvd/lurk/refs/heads/main/loader.lua?t=" .. tick()))()

	Or load the script directly (recommended if the loader serves an old cache):

	loadstring(game:HttpGet("https://raw.githubusercontent.com/90dvd/lurk/refs/heads/main/Scripts/Bedwars.lua?t=" .. tick()))()
]]

local LOADER_VERSION = "2"
local BASE = "https://raw.githubusercontent.com/90dvd/lurk/refs/heads/main/Scripts/Bedwars.lua"
local CACHE = "lurk/Bedwars.lua"
local MIN_VERSION = "1.6.2"

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

local source = nil
for attempt = 1, 3 do
	source = fetch(BASE .. "?t=" .. tick() .. "&loader=" .. LOADER_VERSION .. "&try=" .. attempt)
	if source then
		break
	end
	wait(0.35)
end

if source then
	local version = parseVersion(source)
	print("[lurk] downloaded v" .. tostring(version or "?"))
	pcall(function()
		writefile(CACHE, source)
	end)
else
	warn("[lurk] download failed after 3 tries — not using cache (too old anyway)")
	warn("[lurk] paste this instead:")
	warn('[lurk] loadstring(game:HttpGet("' .. BASE .. '?t=" .. tick()))()')
	source = nil
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
