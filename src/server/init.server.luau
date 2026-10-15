-- init.server.luau
-- r6 npc spawning, wander ai & floppy ragdolls
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

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
local rGrabFreeze = getOrCreateRemote("GrabFreeze")
local rGrabColor = getOrCreateRemote("GrabColor")
local rGrabScale = getOrCreateRemote("GrabScale")
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
local SCALE_MIN = 0.15
local SCALE_MAX = 8.0
local NPC_COUNT = 5
local NPC_WANDER_RADIUS = 45
local NPC_WALK_SPEED = 8

local grabState: {[Player]: any} = {}

-- ragdoll logic
local TAG_RAGDOLLED = "IsRagdolled"
local TAG_GRABBED = "IsGrabbed"

local function isNPCModel(part: BasePart): (boolean, Model?)
	local obj: Instance = part
	while obj and obj ~= workspace do
		if obj:IsA("Model") then
			local hum = obj:FindFirstChildOfClass("Humanoid")
			if hum then
				for _, player in ipairs(Players:GetPlayers()) do
					if player.Character == obj then return false, nil end
				end
				return true, obj :: Model
			end
		end
		obj = obj.Parent
	end
	return false, nil
end

local function ragdoll(model: Model)
	if model:GetAttribute(TAG_RAGDOLLED) then return end
	model:SetAttribute(TAG_RAGDOLLED, true)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	for _, motor in ipairs(model:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			motor.Enabled = false

			local att0 = Instance.new("Attachment")
			att0.Name = "_RagAtt0"; att0.CFrame = motor.C0; att0.Parent = motor.Part0
			local att1 = Instance.new("Attachment")
			att1.Name = "_RagAtt1"; att1.CFrame = motor.C1; att1.Parent = motor.Part1

			local bsc = Instance.new("BallSocketConstraint")
			bsc.Name = "_RagBSC"
			bsc.Attachment0 = att0
			bsc.Attachment1 = att1
			bsc.LimitsEnabled = true
			bsc.UpperAngle = 55
			bsc.TwistLimitsEnabled = false
			bsc.Parent = motor.Part0
		end
	end

	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Name ~= "HumanoidRootPart" then
			obj.CanCollide = true
		end
	end
end

local function unragdoll(model: Model)
	if not model:GetAttribute(TAG_RAGDOLLED) then return end
	if model:GetAttribute(TAG_GRABBED) then return end
	model:SetAttribute(TAG_RAGDOLLED, false)

	for _, obj in ipairs(model:GetDescendants()) do
		if obj.Name == "_RagBSC" or obj.Name == "_RagAtt0" or obj.Name == "_RagAtt1" then
			obj:Destroy()
		end
	end

	for _, motor in ipairs(model:GetDescendants()) do
		if motor:IsA("Motor6D") then motor.Enabled = true end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		task.wait(0.05)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart
	if hrp then hrp.CFrame = hrp.CFrame + Vector3.new(0, 1.5, 0) end
end

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

local function cleanupGrab(state: any, delay: number?)
	pcall(removeBodyMovers, state.part)

	if state.npcModel and state.npcModel.Parent then
		state.npcModel:SetAttribute("IsGrabbed", false)
		task.delay(delay or 2, function()
			if state.npcModel and state.npcModel.Parent then
				unragdoll(state.npcModel)
			end
		end)
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
		cleanupGrab(existing, 1)
		grabState[player] = nil
	end

	local isNPC, npcModel = isNPCModel(hitPart)
	local rootPart = getRootPart(hitPart)
	if not rootPart or rootPart.Anchored then return end

	local char = player.Character; if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart; if not hrp then return end
	if (rootPart.Position - hrp.Position).Magnitude > GRAB_MAX_DIST + 5 then return end

	if isNPC and npcModel then
		ragdoll(npcModel)
		npcModel:SetAttribute("IsGrabbed", true)
		task.wait(0.05)
	end

	local bp, bg = attachBodyMovers(rootPart)
	local isLonePart = (rootPart.Parent == workspace)

	grabState[player] = {
		part = rootPart,
		bodyPos = bp,
		bodyGyro = bg,
		targetPos = rootPart.Position,
		targetCF = rootPart.CFrame,
		lerpedPos = rootPart.Position,
		isLonePart = isLonePart,
		npcModel = npcModel,
		originalSize = isLonePart and rootPart.Size or nil,
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
	if state.frozen and state.part and state.part.Parent then
		state.part.Anchored = false
	end
	cleanupGrab(state, 2)
	grabState[player] = nil
end)

rGrabThrow.OnServerEvent:Connect(function(player: Player, direction: Vector3, speed: number)
	local state = grabState[player]
	if not state then return end
	if typeof(direction) ~= "Vector3" then return end

	local part = state.part
	if state.frozen and part and part.Parent then
		part.Anchored = false
	end
	cleanupGrab(state, 3)
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

rGrabFreeze.OnServerEvent:Connect(function(player: Player, isFrozen: boolean)
	local state = grabState[player]
	if not state or not state.part or not state.part.Parent then return end
	if state.npcModel then return end

	if isFrozen then
		pcall(removeBodyMovers, state.part)
		state.bodyPos = nil
		state.bodyGyro = nil
		state.part.Anchored = true
		state.frozen = true
	else
		state.part.Anchored = false
		local bp, bg = attachBodyMovers(state.part)
		state.bodyPos = bp
		state.bodyGyro = bg
		state.lerpedPos = state.part.Position
		state.frozen = false
	end
end)

rGrabColor.OnServerEvent:Connect(function(player: Player, color: Color3)
	local state = grabState[player]
	if not state or not state.part or not state.part.Parent then return end
	if typeof(color) ~= "Color3" then return end

	if state.npcModel then
		for _, obj in ipairs(state.npcModel:GetDescendants()) do
			if obj:IsA("BasePart") and obj.Name ~= "HumanoidRootPart" then
				obj.Color = color
			end
		end
		return
	end

	if state.isLonePart then
		state.part.Color = color
		return
	end

	local model = state.part.Parent
	if model and model:IsA("Model") then
		for _, obj in ipairs(model:GetDescendants()) do
			if obj:IsA("BasePart") and not obj:IsA("UnionOperation") then
				obj.Color = color
			end
		end
	else
		state.part.Color = color
	end
end)

rGrabScale.OnServerEvent:Connect(function(player: Player, multiplier: number)
	local state = grabState[player]
	if not state or typeof(multiplier) ~= "number" then return end
	multiplier = math.clamp(multiplier, SCALE_MIN, SCALE_MAX)

	if state.isLonePart and state.originalSize then
		local part = state.part
		if part and part.Parent then
			part.Size = state.originalSize * multiplier
		end
	end
end)

-- simple npc wander ai
local function startWander(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.WalkSpeed = NPC_WALK_SPEED

	task.spawn(function()
		while model and model.Parent do
			if model:GetAttribute("IsRagdolled") or model:GetAttribute("IsGrabbed") then
				task.wait(0.3)
				continue
			end

			local angle = math.random() * math.pi * 2
			local radius = math.random(8, NPC_WANDER_RADIUS)
			local target = Vector3.new(math.cos(angle) * radius, 0.5, math.sin(angle) * radius)
			humanoid:MoveTo(target)

			local arrived = false
			local conn
			conn = humanoid.MoveToFinished:Connect(function()
				arrived = true
				conn:Disconnect()
			end)

			local elapsed = 0
			while not arrived and elapsed < 8 do
				task.wait(0.2)
				elapsed += 0.2
				if model:GetAttribute("IsRagdolled") or model:GetAttribute("IsGrabbed") then
					if conn then conn:Disconnect() end
					break
				end
			end
			if conn then pcall(function() conn:Disconnect() end) end
			task.wait(math.random(1, 3))
		end
	end)
end

-- spawn npcs in ring
local NPC_NAMES = { "Bob", "Steve", "Dave", "Jim", "Max" }
task.spawn(function()
	task.wait(1.5)
	local template = ServerStorage:FindFirstChild("NPCRig")
	if not template then return end

	for i = 1, NPC_COUNT do
		local angle = (i / NPC_COUNT) * math.pi * 2
		local radius = math.random(15, 30)
		local pos = Vector3.new(math.cos(angle) * radius, 4, math.sin(angle) * radius)

		local model = template:Clone()
		model.Name = "NPC_" .. (NPC_NAMES[i] or ("Guy" .. i))
		local anim = model:FindFirstChild("Animate"); if anim then anim:Destroy() end

		local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart
		if hrp then hrp.CFrame = CFrame.new(pos) end
		model.Parent = workspace
		task.delay(0.5, function() startWander(model) end)
		task.wait(0.2)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local state = grabState[player]
	if state then
		cleanupGrab(state, 0)
		grabState[player] = nil
	end
end)

print("[Server] v09 npc system initialized.")
