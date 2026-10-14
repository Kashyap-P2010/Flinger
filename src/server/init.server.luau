-- init.server.luau
-- throw impact detection & debris vfx
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "GameRemotes"
local function getRemoteFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder
end

local function getOrCreateRemote(name: string): RemoteEvent
	local folder = getRemoteFolder()
	local rem = folder:FindFirstChild(name)
	if not rem then
		rem = Instance.new("RemoteEvent")
		rem.Name = name
		rem.Parent = folder
	end
	return rem :: RemoteEvent
end

local rGrabStart = getOrCreateRemote("GrabStart")
local rGrabMove = getOrCreateRemote("GrabMove")
local rGrabRelease = getOrCreateRemote("GrabRelease")
local rGrabThrow = getOrCreateRemote("GrabThrow")
local rImpactVFX = getOrCreateRemote("ImpactVFX")

local GRAB_MAX_DIST = 50
local POSITION_P = 12000
local POSITION_D = 800
local POSITION_MAX_FORCE = 1e5
local GYRO_P = 6e4
local GYRO_MAX_TORQUE = 8e4
local POSITION_LERP_ALPHA = 0.30
local GYRO_LERP_ALPHA = 0.28
local THROW_FORCE = 140

local grabState: {[Player]: any} = {}

local function getRootPart(hit: BasePart): BasePart?
	local obj: Instance = hit
	while obj.Parent do
		local parent = obj.Parent
		if parent == workspace then
			if obj:IsA("Model") then
				local hrp = obj:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then return hrp :: BasePart end
				local m = obj :: Model
				return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart") :: BasePart?
			elseif obj:IsA("BasePart") then
				return obj :: BasePart
			end
			return nil
		end
		obj = parent
	end
	return nil
end

local function attachBodyMovers(part: BasePart)
	local old = part:FindFirstChild("_FlingBodyPos"); if old then old:Destroy() end
	old = part:FindFirstChild("_FlingBodyGyro"); if old then old:Destroy() end

	local bp = Instance.new("BodyPosition")
	bp.Name = "_FlingBodyPos"
	bp.P = POSITION_P
	bp.D = POSITION_D
	bp.MaxForce = Vector3.new(POSITION_MAX_FORCE, POSITION_MAX_FORCE, POSITION_MAX_FORCE)
	bp.Position = part.Position
	bp.Parent = part

	local bg = Instance.new("BodyGyro")
	bg.Name = "_FlingBodyGyro"
	bg.P = GYRO_P
	bg.MaxTorque = Vector3.new(GYRO_MAX_TORQUE, GYRO_MAX_TORQUE, GYRO_MAX_TORQUE)
	bg.CFrame = part.CFrame
	bg.Parent = part

	return bp, bg
end

local function removeBodyMovers(part: BasePart)
	local bp = part:FindFirstChild("_FlingBodyPos"); if bp then bp:Destroy() end
	local bg = part:FindFirstChild("_FlingBodyGyro"); if bg then bg:Destroy() end
end

local function cleanupGrab(state: any)
	if state and state.part then
		pcall(removeBodyMovers, state.part)
	end
end

RunService.Heartbeat:Connect(function()
	for _, state in pairs(grabState) do
		if state.bodyPos and state.bodyPos.Parent then
			state.lerpedPos = state.lerpedPos:Lerp(state.targetPos, POSITION_LERP_ALPHA)
			state.bodyPos.Position = state.lerpedPos

			if state.bodyGyro and state.bodyGyro.Parent then
				state.bodyGyro.CFrame = state.bodyGyro.CFrame:Lerp(state.targetCF, GYRO_LERP_ALPHA)
			end
		end
	end
end)

rGrabStart.OnServerEvent:Connect(function(player: Player, hitPart: BasePart)
	if not hitPart or not hitPart:IsA("BasePart") then return end

	local existing = grabState[player]
	if existing then
		cleanupGrab(existing)
		grabState[player] = nil
	end

	local rootPart = getRootPart(hitPart)
	if not rootPart or rootPart.Anchored then return end

	local char = player.Character; if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart; if not hrp then return end
	if (rootPart.Position - hrp.Position).Magnitude > GRAB_MAX_DIST + 5 then return end

	local bp, bg = attachBodyMovers(rootPart)
	grabState[player] = {
		part = rootPart,
		bodyPos = bp,
		bodyGyro = bg,
		targetPos = rootPart.Position,
		targetCF = rootPart.CFrame,
		lerpedPos = rootPart.Position,
	}
end)

rGrabMove.OnServerEvent:Connect(function(player: Player, targetPos: Vector3, targetCF: CFrame)
	local state = grabState[player]
	if not state then return end
	if typeof(targetPos) ~= "Vector3" or typeof(targetCF) ~= "CFrame" then return end

	state.targetPos = targetPos
	state.targetCF = targetCF
end)

rGrabRelease.OnServerEvent:Connect(function(player: Player)
	local state = grabState[player]
	if not state then return end
	cleanupGrab(state)
	grabState[player] = nil
end)

rGrabThrow.OnServerEvent:Connect(function(player: Player, direction: Vector3, speed: number)
	local state = grabState[player]
	if not state then return end
	if typeof(direction) ~= "Vector3" then return end

	local part = state.part
	cleanupGrab(state)
	grabState[player] = nil

	if not part or not part.Parent then return end
	speed = math.clamp(speed or THROW_FORCE, 10, THROW_FORCE * 2)

	local bv = Instance.new("BodyVelocity")
	bv.Velocity = direction.Unit * speed
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.P = 1e4
	bv.Parent = part
	task.delay(0.14, function()
		if bv and bv.Parent then bv:Destroy() end
	end)

	-- check impact collision on hit
	local impactFired = false
	local impactConn: RBXScriptConnection? = nil
	impactConn = part.Touched:Connect(function(hit: BasePart)
		if impactFired then return end
		if not hit or not hit.Parent then return end
		local throwerChar = player.Character
		if throwerChar and hit:IsDescendantOf(throwerChar) then return end
		if not hit:IsA("BasePart") then return end

		local partVel = part.AssemblyLinearVelocity
		if partVel.Magnitude < 12 then return end

		impactFired = true
		if impactConn then impactConn:Disconnect(); impactConn = nil end
		rImpactVFX:FireAllClients(part.Position, partVel.Magnitude)
	end)

	task.delay(8, function()
		if impactConn then impactConn:Disconnect(); impactConn = nil end
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local state = grabState[player]
	if state then
		cleanupGrab(state)
		grabState[player] = nil
	end
end)

print("[Server] v05 impact detection active.")
