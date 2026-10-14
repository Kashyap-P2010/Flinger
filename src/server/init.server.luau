-- init.server.luau
-- basic grab physics & body mover networking
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- setup remots folder
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

-- cfg values
local GRAB_MAX_DIST = 50
local POSITION_P = 12000
local POSITION_D = 800
local POSITION_MAX_FORCE = 1e5
local GYRO_P = 6e4
local GYRO_MAX_TORQUE = 8e4

-- track active grab per player
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
	-- clean up old movers if any
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

rGrabStart.OnServerEvent:Connect(function(player: Player, hitPart: BasePart)
	if not hitPart or not hitPart:IsA("BasePart") then return end

	local existing = grabState[player]
	if existing then
		cleanupGrab(existing)
		grabState[player] = nil
	end

	local rootPart = getRootPart(hitPart)
	-- dont grab anchord parts
	if not rootPart or rootPart.Anchored then return end

	-- basic dist check against exploitr
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
	}
end)

rGrabMove.OnServerEvent:Connect(function(player: Player, targetPos: Vector3, targetCF: CFrame)
	local state = grabState[player]
	if not state then return end
	if typeof(targetPos) ~= "Vector3" or typeof(targetCF) ~= "CFrame" then return end

	state.targetPos = targetPos
	state.targetCF = targetCF

	if state.bodyPos and state.bodyPos.Parent then
		state.bodyPos.Position = targetPos
	end
	if state.bodyGyro and state.bodyGyro.Parent then
		state.bodyGyro.CFrame = targetCF
	end
end)

rGrabRelease.OnServerEvent:Connect(function(player: Player)
	local state = grabState[player]
	if not state then return end
	cleanupGrab(state)
	grabState[player] = nil
end)

-- cleanup when player leaves server
Players.PlayerRemoving:Connect(function(player: Player)
	local state = grabState[player]
	if state then
		cleanupGrab(state)
		grabState[player] = nil
	end
end)

print("[Server] v01 grab ready.")
