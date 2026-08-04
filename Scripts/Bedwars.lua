--[[
	lurk — base script for the Matcha LuaVM
	https://doc.wabisabi.mom/matcha/

	Loaded with (see loader.lua):
	loadstring(game:HttpGet("https://raw.githubusercontent.com/90dvd/lurk/refs/heads/main/Scripts/Bedwars.lua"))()

	Single file on purpose: Matcha's `require` resolves against its own module
	root, which is separate from the writefile workspace, so a written module
	can never be required back in.

	The chunk must not rely on a top-level `return` value — Matcha drops those.
	The public handle is the `_G.LURK` global set at the bottom.
]]

--=============================================================================
-- Environment
--=============================================================================

local Env = {}

do
	local name, version = "unknown", "unknown"
	if type(identifyexecutor) == "function" then
		name, version = identifyexecutor()
	end

	Env.name = name
	Env.version = version
	Env.isMatcha = name == "Matcha"
	Env.hasMemory = type(getbase) == "function"
	Env.hasGarbageCollector = type(getgc) == "function"
	Env.hasDrawing = type(Drawing) == "table" or type(Drawing) == "userdata"
	Env.hasFilesystem = type(writefile) == "function" and type(isfile) == "function"
end

--=============================================================================
-- Compatibility shims
--
-- Matcha deviates from Roblox/Luau in a few places. Everything below exists so
-- the rest of the script can be written the way it would be anywhere else.
--=============================================================================

local Compat = {}

-- Matcha's `error` only prints a red line; it neither raises nor halts.
-- `assert(false, msg)` is the only way to produce a pcall-catchable error.
function Compat.throw(message)
	assert(false, tostring(message))
end

function Compat.try(callback, ...)
	return pcall(callback, ...)
end

-- `task.spawn` does not forward extra arguments to the target.
function Compat.spawn(callback, ...)
	local argc = select("#", ...)
	if argc == 0 then
		task.spawn(callback)
		return
	end

	local args = { ... }
	task.spawn(function()
		callback(unpack(args, 1, argc))
	end)
end

-- `task.delay` is a no-op in the current build: the callback never runs.
function Compat.delay(seconds, callback, ...)
	local argc = select("#", ...)
	local args = { ... }
	task.spawn(function()
		wait(seconds)
		callback(unpack(args, 1, argc))
	end)
end

-- `task.defer` is a no-op as well.
function Compat.defer(callback, ...)
	local argc = select("#", ...)
	local args = { ... }
	task.spawn(function()
		task.wait()
		callback(unpack(args, 1, argc))
	end)
end

-- Neither `wait` nor `task.wait` return the elapsed time; `tick` is monotonic.
function Compat.sleep(seconds)
	local started = tick()
	if seconds then
		wait(seconds)
	else
		task.wait()
	end
	return tick() - started
end

-- `CFrame == CFrame` compares by reference, so components have to be compared.
function Compat.cframeEquals(a, b, epsilon)
	epsilon = epsilon or 1e-4
	local ca = { a:GetComponents() }
	local cb = { b:GetComponents() }
	for i = 1, 12 do
		if math.abs(ca[i] - cb[i]) > epsilon then
			return false
		end
	end
	return true
end

--=============================================================================
-- Logging
--=============================================================================

local Log = {}
Log.prefix = "[lurk]"
Log.enabled = true

function Log.info(...)
	if Log.enabled then
		print(Log.prefix, ...)
	end
end

function Log.warn(...)
	if Log.enabled then
		warn(Log.prefix, ...)
	end
end

function Log.error(...)
	errorl(Log.prefix, ...)
end

function Log.notify(message, title, duration)
	if type(notify) == "function" then
		notify(tostring(message), title or "lurk", duration or 3)
	end
	Log.info(message)
end

--=============================================================================
-- Utility
--=============================================================================

local Util = {}

function Util.clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	elseif value > maximum then
		return maximum
	end
	return value
end

function Util.lerp(from, to, alpha)
	return from + (to - from) * alpha
end

function Util.round(value, decimals)
	local factor = 10 ^ (decimals or 0)
	return math.floor(value * factor + 0.5) / factor
end

function Util.distance(a, b)
	return (a - b).Magnitude
end

-- Matcha renders Vector3 as "Vector3(1.0000, 2.0000, 3.0000)".
function Util.vectorToString(vector, decimals)
	decimals = decimals or 2
	if typeof(vector) == "Vector2" then
		return string.format("%." .. decimals .. "f, %." .. decimals .. "f", vector.X, vector.Y)
	end
	return string.format("%." .. decimals .. "f, %." .. decimals .. "f, %." .. decimals .. "f",
		vector.X, vector.Y, vector.Z)
end

function Util.copy(source)
	local result = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			result[key] = Util.copy(value)
		else
			result[key] = value
		end
	end
	return result
end

function Util.mergeDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = Util.copy(value)
			else
				Util.mergeDefaults(target[key], value)
			end
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end

--=============================================================================
-- Services
--=============================================================================

local Services = setmetatable({}, {
	__index = function(self, name)
		local ok, service = pcall(function()
			return game:GetService(name)
		end)
		if not ok or not service then
			return nil
		end
		self[name] = service
		return service
	end,
})

local Players = Services.Players
local RunService = Services.RunService
local Workspace = Services.Workspace
local HttpService = Services.HttpService

--=============================================================================
-- Local player
--=============================================================================

local Me = {}

function Me.player()
	return Players and Players.LocalPlayer or nil
end

function Me.camera()
	return Workspace and Workspace.CurrentCamera or nil
end

function Me.mouse()
	local player = Me.player()
	if not player then
		return nil
	end
	local ok, mouse = pcall(function()
		return player:GetMouse()
	end)
	return ok and mouse or nil
end

function Me.character()
	local player = Me.player()
	return player and player.Character or nil
end

function Me.humanoid()
	local character = Me.character()
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function Me.root()
	local character = Me.character()
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

function Me.position()
	local root = Me.root()
	return root and root.Position or nil
end

function Me.alive()
	local humanoid = Me.humanoid()
	return humanoid ~= nil and humanoid.Health > 0
end

--=============================================================================
-- Player queries
--=============================================================================

local Query = {}

local function characterPart(player, partName)
	local character = player.Character
	if not character then
		return nil
	end
	if partName then
		return character:FindFirstChild(partName)
	end
	return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

Query.part = characterPart

function Query.isAlive(player)
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function Query.isTeammate(player)
	local me = Me.player()
	if not me or not me.Team or not player.Team then
		return false
	end
	return me.Team == player.Team
end

function Query.others()
	local result = {}
	if not Players then
		return result
	end

	local me = Me.player()
	for _, player in pairs(Players:GetPlayers()) do
		if player ~= me then
			result[#result + 1] = player
		end
	end
	return result
end

function Query.targets(options)
	options = options or {}

	local result = {}
	for _, player in pairs(Query.others()) do
		local keep = true

		if options.aliveOnly ~= false and not Query.isAlive(player) then
			keep = false
		end
		if keep and options.ignoreTeam and Query.isTeammate(player) then
			keep = false
		end
		if keep and options.maxDistance then
			local origin = Me.position()
			local part = characterPart(player, options.partName)
			if not origin or not part or Util.distance(origin, part.Position) > options.maxDistance then
				keep = false
			end
		end
		if keep and options.filter and not options.filter(player) then
			keep = false
		end

		if keep then
			result[#result + 1] = player
		end
	end
	return result
end

-- Closest on-screen target to the cursor, or to the viewport centre without one.
function Query.closestToCursor(options)
	options = options or {}

	local camera = Me.camera()
	if not camera then
		return nil
	end

	local origin
	local mouse = Me.mouse()
	if mouse and not options.fromCenter then
		origin = Vector2.new(mouse.X, mouse.Y)
	else
		local viewport = camera.ViewportSize
		origin = Vector2.new(viewport.X / 2, viewport.Y / 2)
	end

	local radius = options.radius or math.huge
	local best, bestPart, bestDistance = nil, nil, radius

	for _, player in pairs(Query.targets(options)) do
		local part = characterPart(player, options.partName)
		if part then
			local screen, onScreen = WorldToScreen(part.Position)
			if onScreen then
				local dx = screen.X - origin.X
				local dy = screen.Y - origin.Y
				local distance = math.sqrt(dx * dx + dy * dy)
				if distance < bestDistance then
					best, bestPart, bestDistance = player, part, distance
				end
			end
		end
	end

	return best, bestPart, bestDistance
end

function Query.closestToMe(options)
	options = options or {}

	local origin = Me.position()
	if not origin then
		return nil
	end

	local best, bestPart, bestDistance = nil, nil, options.maxDistance or math.huge
	for _, player in pairs(Query.targets(options)) do
		local part = characterPart(player, options.partName)
		if part then
			local distance = Util.distance(origin, part.Position)
			if distance < bestDistance then
				best, bestPart, bestDistance = player, part, distance
			end
		end
	end

	return best, bestPart, bestDistance
end

--=============================================================================
-- Input
--
-- Polled through iskeypressed (Windows virtual-key codes) rather than
-- UserInputService, so binds keep working while the game swallows input.
--=============================================================================

local Input = {}

Input.VK = {
	LBUTTON = 0x01, RBUTTON = 0x02, MBUTTON = 0x04,
	BACKSPACE = 0x08, TAB = 0x09, ENTER = 0x0D, SHIFT = 0x10,
	CTRL = 0x11, ALT = 0x12, CAPSLOCK = 0x14, ESCAPE = 0x1B,
	SPACE = 0x20, PAGEUP = 0x21, PAGEDOWN = 0x22, END = 0x23, HOME = 0x24,
	LEFT = 0x25, UP = 0x26, RIGHT = 0x27, DOWN = 0x28,
	INSERT = 0x2D, DELETE = 0x2E,
	ZERO = 0x30, ONE = 0x31, TWO = 0x32, THREE = 0x33, FOUR = 0x34,
	FIVE = 0x35, SIX = 0x36, SEVEN = 0x37, EIGHT = 0x38, NINE = 0x39,
	A = 0x41, B = 0x42, C = 0x43, D = 0x44, E = 0x45, F = 0x46, G = 0x47,
	H = 0x48, I = 0x49, J = 0x4A, K = 0x4B, L = 0x4C, M = 0x4D, N = 0x4E,
	O = 0x4F, P = 0x50, Q = 0x51, R = 0x52, S = 0x53, T = 0x54, U = 0x55,
	V = 0x56, W = 0x57, X = 0x58, Y = 0x59, Z = 0x5A,
	F1 = 0x70, F2 = 0x71, F3 = 0x72, F4 = 0x73, F5 = 0x74, F6 = 0x75,
	F7 = 0x76, F8 = 0x77, F9 = 0x78, F10 = 0x79, F11 = 0x7A, F12 = 0x7B,
}

local tracked = {}
local currentState = {}
local previousState = {}

local function track(keycode)
	if tracked[keycode] == nil then
		tracked[keycode] = true
		currentState[keycode] = iskeypressed(keycode)
		previousState[keycode] = currentState[keycode]
	end
end

function Input.update()
	for keycode in pairs(tracked) do
		previousState[keycode] = currentState[keycode]
		currentState[keycode] = iskeypressed(keycode)
	end
end

function Input.focused()
	return isrbxactive()
end

function Input.down(keycode)
	return iskeypressed(keycode) == true
end

function Input.pressed(keycode)
	track(keycode)
	return currentState[keycode] == true and previousState[keycode] ~= true
end

function Input.released(keycode)
	track(keycode)
	return currentState[keycode] ~= true and previousState[keycode] == true
end

local binds = {}

-- Fires once per key press. `onlyFocused` defaults to true.
function Input.bind(keycode, callback, onlyFocused)
	track(keycode)
	binds[#binds + 1] = {
		keycode = keycode,
		callback = callback,
		onlyFocused = onlyFocused ~= false,
	}
end

function Input.toggle(keycode, callback, initial)
	local state = initial == true
	Input.bind(keycode, function()
		state = not state
		callback(state)
	end)
	return function()
		return state
	end
end

local function runBinds()
	for _, bind in pairs(binds) do
		if not (bind.onlyFocused and not isrbxactive()) then
			if Input.pressed(bind.keycode) then
				local ok, err = pcall(bind.callback)
				if not ok then
					Log.error("bind:", err)
				end
			end
		end
	end
end

--=============================================================================
-- Drawing
--
-- Drawing objects outlive the script, so every object is tracked and removed
-- on unload.
--=============================================================================

local Draw = {}
local drawings = {}

function Draw.new(kind, properties)
	local object = Drawing.new(kind)

	if properties then
		for key, value in pairs(properties) do
			object[key] = value
		end
	end

	drawings[#drawings + 1] = object
	return object
end

function Draw.square(properties)
	return Draw.new("Square", properties)
end

function Draw.line(properties)
	return Draw.new("Line", properties)
end

function Draw.circle(properties)
	return Draw.new("Circle", properties)
end

function Draw.text(properties)
	return Draw.new("Text", properties)
end

function Draw.triangle(properties)
	return Draw.new("Triangle", properties)
end

function Draw.image(properties)
	return Draw.new("Image", properties)
end

function Draw.remove(object)
	for index, tracked in pairs(drawings) do
		if tracked == object then
			table.remove(drawings, index)
			break
		end
	end
	pcall(function()
		object:Remove()
	end)
end

function Draw.clear()
	for _, object in pairs(drawings) do
		pcall(function()
			object:Remove()
		end)
	end
	drawings = {}
end

function Draw.hideAll()
	for _, object in pairs(drawings) do
		pcall(function()
			object.Visible = false
		end)
	end
end

--=============================================================================
-- Config
--=============================================================================

local Config = {}

Config.path = "lurk/config.json"

-- mergeDefaults only fills in missing keys, so a saved config would keep an old
-- value forever after a default changes. Bump this whenever that must not
-- happen and the stored file gets discarded instead.
Config.version = 2

Config.defaults = {
	version = Config.version,
	enabled = true,
	unloadKey = Input.VK.END,
}
Config.data = Util.copy(Config.defaults)

function Config.load()
	if not Env.hasFilesystem or not isfile(Config.path) then
		Config.data = Util.copy(Config.defaults)
		return Config.data
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(readfile(Config.path))
	end)

	if not ok or type(decoded) ~= "table" then
		Log.warn("config unreadable, using defaults")
		Config.data = Util.copy(Config.defaults)
	elseif decoded.version ~= Config.version then
		Log.info("config is from an older version, resetting to defaults")
		Config.data = Util.copy(Config.defaults)
	else
		Config.data = Util.mergeDefaults(decoded, Config.defaults)
	end

	return Config.data
end

function Config.save()
	if not Env.hasFilesystem then
		return false
	end

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(Config.data)
	end)
	if not ok then
		Log.warn("config encode failed:", encoded)
		return false
	end

	local written = pcall(function()
		writefile(Config.path, encoded)
	end)
	if not written then
		Log.warn("config write failed")
	end
	return written
end

--=============================================================================
-- Runtime
--=============================================================================

local Runtime = {}

Runtime.running = true
Runtime.connections = {}
Runtime.cleanups = {}
Runtime.frame = 0
Runtime.startedAt = 0

-- A handler that errors does so every frame, so identical messages are
-- collapsed and reported at most once every few seconds with a repeat count.
local ERROR_COOLDOWN = 5
local reported = {}

local function reportError(key, message)
	local now = tick()
	local record = reported[key]

	if record and record.message == message then
		if now - record.at < ERROR_COOLDOWN then
			record.suppressed = record.suppressed + 1
			return
		end

		if record.suppressed > 0 then
			Log.error(key .. ":", message, string.format("(repeated %dx)", record.suppressed))
		else
			Log.error(key .. ":", message)
		end
		reported[key] = { message = message, at = now, suppressed = 0 }
		return
	end

	Log.error(key .. ":", message)
	reported[key] = { message = message, at = now, suppressed = 0 }
end

local function guard(callback, label)
	local key = label or "handler"
	return function(...)
		if not Runtime.running then
			return
		end
		local ok, err = pcall(callback, ...)
		if not ok then
			reportError(key, tostring(err))
		end
	end
end

Runtime.guard = guard

-- Matcha does not document Disconnect on connections, so the wrapper's running
-- flag is the reliable off switch; Disconnect is only attempted best-effort.
function Runtime.connect(signal, callback, label)
	local connection = signal:Connect(guard(callback, label))
	Runtime.connections[#Runtime.connections + 1] = connection
	return connection
end

function Runtime.onRender(callback, label)
	return Runtime.connect(RunService.RenderStepped, callback, label or "render")
end

function Runtime.onHeartbeat(callback, label)
	return Runtime.connect(RunService.Heartbeat, callback, label or "heartbeat")
end

-- Matcha passes only deltaTime to Stepped, unlike Roblox (time, deltaTime).
function Runtime.onStepped(callback, label)
	return Runtime.connect(RunService.Stepped, callback, label or "stepped")
end

function Runtime.onCleanup(callback)
	Runtime.cleanups[#Runtime.cleanups + 1] = callback
end

-- Runs `callback` every `interval` seconds on its own thread. The callback runs
-- inside a pcall, so it must not yield.
function Runtime.every(interval, callback, label)
	task.spawn(function()
		while Runtime.running do
			local ok, err = pcall(callback)
			if not ok then
				reportError(label or "loop", tostring(err))
			end
			wait(interval)
		end
	end)
end

function Runtime.unload()
	if not Runtime.running then
		return
	end
	Runtime.running = false

	for index = #Runtime.cleanups, 1, -1 do
		pcall(Runtime.cleanups[index])
	end

	for _, connection in pairs(Runtime.connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	Runtime.connections = {}

	Draw.clear()
	Config.save()

	Log.notify("unloaded", "lurk", 2)
	_G.LURK = nil
end

--=============================================================================
-- Features
--
-- Register features here. Each one gets its own do-block, declares its config
-- defaults, and exposes init() — which runs after Config.load().
--=============================================================================

local Features = {}
Features.list = {}

function Features.register(name, feature)
	feature.name = name
	Features[name] = feature
	Features.list[#Features.list + 1] = feature
	return feature
end

--=============================================================================
-- Bed ESP (Roblox BedWars)
--=============================================================================

do
	local BedESP = Features.register("BedESP", {})

	Config.defaults.bedEsp = {
		enabled = true,
		toggleKey = Input.VK.B,
		box = false,
		label = true,
		distance = true,
		tracer = false,
		hideOwnTeam = true,
		maxDistance = 0,
		fontSize = 14,
		rescanInterval = 4,
		enemyColor = { 255, 75, 75 },
		ownColor = { 90, 220, 120 },
	}

	-- Beds are found through their `BedPosition` attachment; the plain `Bed`
	-- name is a fallback for maps that do not carry the attachment.
	local ANCHOR_NAMES = { bedposition = true }
	local BED_NAMES = { bed = true }

	-- Cosmetic bed previews live under LockerPreview and must not be drawn.
	local EXCLUDED_PATHS = { "lockerpreview", "preview", "lobby", "viewmodel", "template" }

	local TEAM_ATTRIBUTES = { "Team", "TeamName", "BedTeam", "team" }

	-- Studs within which two hits are treated as the same bed.
	local MERGE_RADIUS = 14

	BedESP.beds = {}

	local function isExcluded(path)
		local lowered = string.lower(path)
		for _, needle in pairs(EXCLUDED_PATHS) do
			if string.find(lowered, needle, 1, true) then
				return true
			end
		end
		return false
	end

	local function nearestModel(instance)
		local current = instance
		for _ = 1, 6 do
			local parent = current.Parent
			if not parent then
				return nil
			end
			if parent:IsA("Model") then
				return parent
			end
			current = parent
		end
		return nil
	end

	local function anchorPart(instance)
		if instance:IsA("BasePart") then
			return instance
		end

		local current = instance
		for _ = 1, 4 do
			local parent = current.Parent
			if not parent then
				break
			end
			if parent:IsA("BasePart") then
				return parent
			end
			if parent:IsA("Model") and parent.PrimaryPart then
				return parent.PrimaryPart
			end
			current = parent
		end

		return instance:FindFirstChildWhichIsA("BasePart")
	end

	-- IsA("BasePart") can be true for instances whose Position/Size Matcha does
	-- not emulate, so both are validated before use instead of trusted.
	local function partExtents(part)
		local ok, position, size = pcall(function()
			return part.Position, part.Size
		end)

		if not ok or typeof(position) ~= "Vector3" then
			return nil
		end
		if typeof(size) ~= "Vector3" then
			size = Vector3.zero
		end

		return position, size
	end

	-- Matcha's BasePart exposes Position and Size but no CFrame, so the box is
	-- an axis-aligned bounding box over every part of the bed.
	local function computeBounds(root, fallback)
		local parts = {}

		if root then
			local ok, descendants = pcall(function()
				return root:GetDescendants()
			end)
			if ok then
				for _, descendant in pairs(descendants) do
					if descendant:IsA("BasePart") then
						parts[#parts + 1] = descendant
					end
				end
			end
		end
		if fallback then
			parts[#parts + 1] = fallback
		end

		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
		local valid = 0

		for _, part in pairs(parts) do
			local position, size = partExtents(part)
			if position then
				valid = valid + 1
				local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5

				minX = math.min(minX, position.X - hx)
				minY = math.min(minY, position.Y - hy)
				minZ = math.min(minZ, position.Z - hz)
				maxX = math.max(maxX, position.X + hx)
				maxY = math.max(maxY, position.Y + hy)
				maxZ = math.max(maxZ, position.Z + hz)
			end
		end

		if valid == 0 then
			return nil
		end

		return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
	end

	local function resolveTeam(instance)
		local current = instance
		for _ = 1, 5 do
			if not current then
				break
			end

			local target = current
			for _, key in pairs(TEAM_ATTRIBUTES) do
				local ok, value = pcall(function()
					return target:GetAttribute(key)
				end)
				if ok and type(value) == "string" and value ~= "" then
					return value
				end
			end

			current = current.Parent
		end
		return nil
	end

	function BedESP.scan()
		local found = {}
		if not Workspace then
			return found
		end

		local ok, descendants = pcall(function()
			return Workspace:GetDescendants()
		end)
		if not ok then
			return found
		end

		local myTeam
		local me = Me.player()
		if me and me.Team then
			myTeam = me.Team.Name
		end

		local stats = { candidates = 0, excluded = 0, unpositioned = 0, duplicates = 0 }

		for _, descendant in pairs(descendants) do
			local lowered = string.lower(descendant.Name)
			local isAnchor = ANCHOR_NAMES[lowered] == true
			local isBed = BED_NAMES[lowered] == true
				and (descendant:IsA("Model") or descendant:IsA("BasePart"))

			if isAnchor or isBed then
				stats.candidates = stats.candidates + 1

				local pathOk, path = pcall(function()
					return descendant:GetFullName()
				end)

				if pathOk and isExcluded(path) then
					stats.excluded = stats.excluded + 1
				end

				if pathOk and not isExcluded(path) then
					local root = descendant:IsA("Model") and descendant or nearestModel(descendant)
					local part = anchorPart(descendant)

					if part or root then
						local minimum, maximum = computeBounds(root, part)
						if minimum then
							local team = resolveTeam(descendant)
							found[#found + 1] = {
								root = root,
								part = part,
								minimum = minimum,
								maximum = maximum,
								center = (minimum + maximum) * 0.5,
								span = (maximum - minimum).Magnitude,
								team = team,
								isOwn = team ~= nil and myTeam ~= nil and string.lower(team) == string.lower(myTeam),
								path = path,
								fromAnchor = isAnchor,
							}
						else
							stats.unpositioned = stats.unpositioned + 1
						end
					end
				end
			end
		end

		-- A single bed carries several matching instances (two BedPosition
		-- anchors plus sometimes the model itself), and they resolve to different
		-- roots, so their bounding boxes and centres differ by a few studs. Two
		-- hits this close together are therefore the same bed. Two real beds are
		-- never within this radius of each other.
		local merged = {}

		for _, bed in pairs(found) do
			local absorbed = false

			for index, kept in pairs(merged) do
				if Util.distance(bed.center, kept.center) <= MERGE_RADIUS then
					absorbed = true
					stats.duplicates = stats.duplicates + 1

					-- Prefer the tighter box: a larger one usually means a parent
					-- container got picked up instead of the bed itself.
					if bed.span < kept.span then
						merged[index] = bed
					end
					break
				end
			end

			if not absorbed then
				merged[#merged + 1] = bed
			end
		end

		BedESP.stats = stats
		return merged
	end

	function BedESP.dump()
		local stats = BedESP.stats or {}
		Log.info(string.format("%d bed(s) drawn | candidates=%s excluded=%s duplicates=%s without position=%s",
			#BedESP.beds,
			tostring(stats.candidates),
			tostring(stats.excluded),
			tostring(stats.duplicates),
			tostring(stats.unpositioned)))

		for index, bed in pairs(BedESP.beds) do
			Log.info(string.format("  %d. %s | team=%s own=%s anchor=%s span=%.1f | %s",
				index,
				bed.path,
				tostring(bed.team),
				tostring(bed.isOwn),
				tostring(bed.fromAnchor),
				bed.span,
				Util.vectorToString(bed.center, 0)))
		end
	end

	-- Lists every Workspace instance whose name mentions a bed, so the real
	-- hierarchy can be confirmed when the scan comes up empty.
	function BedESP.probe(needle, limit)
		needle = string.lower(needle or "bed")
		limit = limit or 60

		local ok, descendants = pcall(function()
			return Workspace:GetDescendants()
		end)
		if not ok then
			Log.error("probe: Workspace:GetDescendants() failed")
			return
		end

		local matched = 0
		for _, descendant in pairs(descendants) do
			if string.find(string.lower(descendant.Name), needle, 1, true) then
				matched = matched + 1
				if matched <= limit then
					local pathOk, path = pcall(function()
						return descendant:GetFullName()
					end)
					local position = partExtents(descendant)

					Log.info(string.format("  [%s]%s %s%s",
						descendant.ClassName,
						position and "" or " (no position)",
						pathOk and path or descendant.Name,
						(pathOk and isExcluded(path)) and "  <- excluded" or ""))
				end
			end
		end

		Log.info(string.format("%d instance(s) matched '%s'%s",
			matched,
			needle,
			matched > limit and string.format(" (showing %d)", limit) or ""))
	end

	local pool = {}

	-- The docs call the text size FontSize, but the VM rejects that name on at
	-- least some builds, so the actual property is probed once and remembered.
	-- `false` means neither name works and the size is left at its default.
	local sizeProperty

	local function applyFontSize(text, value)
		if sizeProperty == false then
			return
		end

		if sizeProperty then
			text[sizeProperty] = value
			return
		end

		for _, candidate in pairs({ "FontSize", "Size", "TextSize" }) do
			local ok = pcall(function()
				text[candidate] = value
			end)
			if ok then
				sizeProperty = candidate
				return
			end
		end

		sizeProperty = false
		Log.warn("no usable text size property on this Matcha build")
	end

	local function acquire(index)
		local slot = pool[index]
		if slot then
			return slot
		end

		local text = Draw.text({ Center = true, Outline = true, Visible = false, ZIndex = 3 })
		if type(Drawing.Fonts) == "table" and Drawing.Fonts.Monospace then
			pcall(function()
				text.Font = Drawing.Fonts.Monospace
			end)
		end

		slot = {
			box = Draw.square({ Filled = false, Thickness = 1, Visible = false, ZIndex = 2 }),
			text = text,
			tracer = Draw.line({ Thickness = 1, Visible = false, ZIndex = 1 }),
		}

		pool[index] = slot
		return slot
	end

	local function hideSlot(slot)
		slot.box.Visible = false
		slot.text.Visible = false
		slot.tracer.Visible = false
	end

	local function hideFrom(index)
		for position = index, #pool do
			hideSlot(pool[position])
		end
	end

	local function projectBounds(minimum, maximum)
		local minX, minY = math.huge, math.huge
		local maxX, maxY = -math.huge, -math.huge
		local anyVisible = false

		for corner = 0, 7 do
			local x = (corner % 2 == 0) and minimum.X or maximum.X
			local y = (math.floor(corner / 2) % 2 == 0) and minimum.Y or maximum.Y
			local z = (math.floor(corner / 4) % 2 == 0) and minimum.Z or maximum.Z

			local screen, onScreen = WorldToScreen(Vector3.new(x, y, z))
			if onScreen then
				anyVisible = true
				minX = math.min(minX, screen.X)
				minY = math.min(minY, screen.Y)
				maxX = math.max(maxX, screen.X)
				maxY = math.max(maxY, screen.Y)
			end
		end

		if not anyVisible then
			return nil
		end
		return minX, minY, maxX, maxY
	end

	local function render()
		local settings = Config.data.bedEsp

		if not settings.enabled then
			hideFrom(1)
			return
		end

		local camera = Me.camera()
		if not camera then
			hideFrom(1)
			return
		end

		local viewport = camera.ViewportSize
		local eye = Me.position() or camera.Position
		local enemyColor = Color3.fromRGB(settings.enemyColor[1], settings.enemyColor[2], settings.enemyColor[3])
		local ownColor = Color3.fromRGB(settings.ownColor[1], settings.ownColor[2], settings.ownColor[3])
		local used = 0

		for _, bed in pairs(BedESP.beds) do
			local drawIt = true

			if settings.hideOwnTeam and bed.isOwn then
				drawIt = false
			end

			local distance = 0
			if drawIt and eye then
				distance = Util.distance(eye, bed.center)
				if settings.maxDistance > 0 and distance > settings.maxDistance then
					drawIt = false
				end
			end

			if drawIt then
				local minX, minY, maxX, maxY = projectBounds(bed.minimum, bed.maximum)
				if minX then
					used = used + 1
					local slot = acquire(used)
					local color = bed.isOwn and ownColor or enemyColor

					if settings.box then
						slot.box.Color = color
						slot.box.Position = Vector2.new(minX, minY)
						slot.box.Size = Vector2.new(maxX - minX, maxY - minY)
						slot.box.Visible = true
					else
						slot.box.Visible = false
					end

					if settings.label then
						local caption = bed.team and (string.upper(bed.team) .. " BED") or "BED"
						if settings.distance then
							caption = caption .. string.format("  [%dm]", math.floor(distance + 0.5))
						end

						slot.text.Text = caption
						slot.text.Color = color
						if slot.fontSize ~= settings.fontSize then
							applyFontSize(slot.text, settings.fontSize)
							slot.fontSize = settings.fontSize
						end
						slot.text.Position = Vector2.new((minX + maxX) * 0.5, minY - settings.fontSize - 2)
						slot.text.Visible = true
					else
						slot.text.Visible = false
					end

					if settings.tracer then
						slot.tracer.Color = color
						slot.tracer.From = Vector2.new(viewport.X * 0.5, viewport.Y)
						slot.tracer.To = Vector2.new((minX + maxX) * 0.5, maxY)
						slot.tracer.Visible = true
					else
						slot.tracer.Visible = false
					end
				end
			end
		end

		hideFrom(used + 1)
	end

	function BedESP.init()
		local settings = Config.data.bedEsp

		Input.bind(settings.toggleKey, function()
			settings.enabled = not settings.enabled
			Log.notify("Bed ESP " .. (settings.enabled and "on" or "off"), "lurk", 1.5)
		end)

		local lastCount = -1
		Runtime.every(settings.rescanInterval, function()
			BedESP.beds = BedESP.scan()
			if #BedESP.beds ~= lastCount then
				lastCount = #BedESP.beds
				local stats = BedESP.stats or {}
				Log.info(string.format("beds: %d drawn, %s candidate(s)",
					lastCount, tostring(stats.candidates)))
			end
		end, "bed scan")

		Runtime.onRender(render, "bed esp")
		Runtime.onCleanup(function()
			hideFrom(1)
		end)
	end
end

--=============================================================================
-- Bootstrap
--=============================================================================

local function waitForPlayer(timeout)
	local deadline = tick() + (timeout or 10)
	while tick() < deadline do
		if Me.player() then
			return true
		end
		task.wait()
	end
	return Me.player() ~= nil
end

local function main()
	if type(_G.LURK) == "table" and _G.LURK.Runtime then
		pcall(_G.LURK.Runtime.unload)
	end

	if not Env.isMatcha then
		Log.warn("running on '" .. tostring(Env.name) .. "', not Matcha — behaviour may differ")
	end

	if not waitForPlayer(10) then
		Log.error("Players.LocalPlayer never became available")
		return
	end

	Config.load()
	Runtime.startedAt = tick()

	Input.bind(Config.data.unloadKey, function()
		Runtime.unload()
	end)

	-- Input runs before the features so binds settle on the current frame.
	Runtime.onRender(function()
		Runtime.frame = Runtime.frame + 1
		Input.update()
		runBinds()
	end, "input")

	for _, feature in pairs(Features.list) do
		if type(feature.init) == "function" then
			local ok, err = pcall(feature.init)
			if not ok then
				Log.error("feature " .. tostring(feature.name) .. " failed to init:", err)
			end
		end
	end

	_G.LURK = {
		Env = Env,
		Compat = Compat,
		Log = Log,
		Util = Util,
		Services = Services,
		Me = Me,
		Query = Query,
		Input = Input,
		Draw = Draw,
		Config = Config,
		Runtime = Runtime,
		Features = Features,
	}

	Log.notify(string.format("loaded on %s %s", Env.name, Env.version), "lurk", 3)
end

main()
