-- init.server.luau
-- complete server system (engine minimum 1 file)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
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
local rGrabNotify = getOrCreateRemote("GrabNotify")
local rGrabEscape = getOrCreateRemote("GrabEscape")
local rGrabCancel = getOrCreateRemote("GrabCancel")
local rGrabBroadcast = getOrCreateRemote("GrabBroadcast")
local rImpactVFX = getOrCreateRemote("ImpactVFX")
local rPurchase = getOrCreateRemote("PurchaseItem")
local rUpdateCoins = getOrCreateRemote("UpdateCoins")
local rSpawnItem = getOrCreateRemote("SpawnItem")

local CFG = {
	GRAB_MAX_DISTANCE = 50,
	GRAB_MIN_DIST = 3,
	GRAB_MAX_DIST = 40,
	GRAB_DEFAULT_DIST = 15,
	SCROLL_SENSITIVITY = 1.2,
	THROW_FLICK_THRESHOLD = 6,
	THROW_FLICK_SAMPLES = 5,
	THROW_FORCE = 140,
	ROT_SENSITIVITY = 0.004,
	POSITION_P = 12000,
	POSITION_D = 800,
	POSITION_MAX_FORCE = 1e5,
	GYRO_P = 6e4,
	GYRO_MAX_TORQUE = 8e4,
	POSITION_LERP_ALPHA = 0.30,
	GYRO_LERP_ALPHA = 0.28,
	SCALE_MIN = 0.15,
	SCALE_MAX = 8.0,
	SCALE_STEP = 0.03,
	NPC_COUNT = 5,
	NPC_WANDER_RADIUS = 45,
	NPC_WALK_SPEED = 8,
	GRAB_ESCAPE_TIME = 10,
	DATASTORE_NAME = "FlingGameData_v3",
	REWARD_PART_NAME = "RewardPart",
	REWARD_COINS = 500,
	REWARD_COOLDOWN = 10,
	SHOP_ITEMS = {
		{ id = "WoodenPlank", displayName = "Wooden Plank", price = 0, isStarter = true },
		{ id = "Doll", displayName = "Doll", price = 200, description = "A creepy little doll." },
		{ id = "Chest", displayName = "Chest", price = 350, description = "A heavy wooden chest." },
		{ id = "Duck", displayName = "Duck", price = 500, description = "The legendary rubber duck." },
	}
}

-- datastore & player data
local DataStore = DataStoreService:GetDataStore(CFG.DATASTORE_NAME)
local playerData: {[Player]: any} = {}
local playerSpawnedItem: {[Player]: Instance?} = {}

local function loadData(player: Player)
	local key = "player_" .. player.UserId
	local success, result = pcall(function() return DataStore:GetAsync(key) end)
	local data
	if success then
		data = {
			coins = (result and result.coins) or 0,
			ownedItems = (result and result.ownedItems) or { WoodenPlank = true },
		}
		data.ownedItems["WoodenPlank"] = true
	else
		data = { coins = 0, ownedItems = { WoodenPlank = true }, _loadFailed = true }
	end
	playerData[player] = data
end

local function saveData(player: Player)
	local data = playerData[player]
	if not data or data._loadFailed then return end
	local key = "player_" .. player.UserId
	pcall(function()
		DataStore:UpdateAsync(key, function()
			return { coins = data.coins, ownedItems = data.ownedItems }
		end)
	end)
end

local CoinsAPI = {}
function CoinsAPI.addCoins(player: Player, amount: number)
	local data = playerData[player]; if not data then return end
	data.coins = data.coins + amount
	rUpdateCoins:FireClient(player, data.coins)
end

local coinsBindable = Instance.new("BindableFunction")
coinsBindable.Name = "CoinsAPI"
coinsBindable.Parent = ServerScriptService
coinsBindable.OnInvoke = function(action: string, player: Player, amount: number)
	if action == "addCoins" then CoinsAPI.addCoins(player, amount); return true
	elseif action == "getCoins" then return (playerData[player] and playerData[player].coins) or 0 end
	return nil
end

local function getItemTemplate(itemId: string): Instance?
	local item = ReplicatedStorage:FindFirstChild(itemId)
	if not item then
		for _, child in ipairs(ReplicatedStorage:GetChildren()) do
			if child:IsA("Folder") then
				local found = child:FindFirstChild(itemId)
				if found then item = found; break end
			end
		end
	end
	return item
end

local function spawnItemForPlayer(player: Player, itemId: string)
	local char = player.Character; if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart; if not hrp then return end

	local existing = playerSpawnedItem[player]
	if existing and existing.Parent then existing:Destroy() end
	playerSpawnedItem[player] = nil

	local template = getItemTemplate(itemId)
	local spawnCF = hrp.CFrame * CFrame.new(0, 2, -5)
	local clone: Instance? = nil

	if template then
		clone = template:Clone()
		if clone:IsA("Model") then
			if clone.PrimaryPart then
				clone.PrimaryPart.Anchored = false
				clone:SetPrimaryPartCFrame(spawnCF)
			else
				local fp = clone:FindFirstChildWhichIsA("BasePart")
				if fp then clone.PrimaryPart = fp; fp.Anchored = false; clone:SetPrimaryPartCFrame(spawnCF) end
			end
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then part.Anchored = false end
			end
		elseif clone:IsA("BasePart") then
			clone.Anchored = false
			clone.CFrame = spawnCF
		end
	elseif itemId == "WoodenPlank" then
		local plank = Instance.new("Part")
		plank.Name = "WoodenPlank"
		plank.Size = Vector3.new(8, 0.5, 2)
		plank.Material = Enum.Material.Wood
		plank.Color = Color3.fromRGB(163, 120, 63)
		plank.Anchored = false
		plank.CFrame = spawnCF
		clone = plank
	end

	if clone then
		clone:SetAttribute("OwnerId", player.UserId)
		clone.Parent = workspace
		playerSpawnedItem[player] = clone
		rSpawnItem:FireClient(player, itemId, clone)
	end
end

-- grab & physics state
local grabState: {[Player]: any} = {}
local TAG_RAGDOLLED = "IsRagdolled"
local TAG_GRABBED = "IsGrabbed"

local function classifyHit(hitPart: BasePart, grabber: Player): (boolean, Model?, Player?)
	local obj: Instance = hitPart
	while obj and obj ~= workspace do
		if obj:IsA("Model") then
			local hum = obj:FindFirstChildOfClass("Humanoid")
			if hum then
				for _, p in ipairs(Players:GetPlayers()) do
					if p.Character == obj then
						if p == grabber then return false, nil, nil end
						return false, nil, p
					end
				end
				return true, obj :: Model, nil
			end
		end
		obj = obj.Parent
	end
	return false, nil, nil
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

			local att0 = Instance.new("Attachment"); att0.Name = "_RagAtt0"; att0.CFrame = motor.C0; att0.Parent = motor.Part0
			local att1 = Instance.new("Attachment"); att1.Name = "_RagAtt1"; att1.CFrame = motor.C1; att1.Parent = motor.Part1

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
	bp.P = CFG.POSITION_P
	bp.D = CFG.POSITION_D
	bp.MaxForce = Vector3.new(CFG.POSITION_MAX_FORCE, CFG.POSITION_MAX_FORCE, CFG.POSITION_MAX_FORCE)
	bp.Position = part.Position
	bp.Parent = part

	local bg = Instance.new("BodyGyro")
	bg.Name = "_FlingBodyGyro"
	bg.P = CFG.GYRO_P
	bg.MaxTorque = Vector3.new(CFG.GYRO_MAX_TORQUE, CFG.GYRO_MAX_TORQUE, CFG.GYRO_MAX_TORQUE)
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
			if state.npcModel and state.npcModel.Parent then unragdoll(state.npcModel) end
		end)
	end

	if state.victimPlayer then
		local victimChar = state.victimPlayer.Character
		if victimChar then
			task.delay(delay or 1.5, function()
				if victimChar and victimChar.Parent then
					for _, p in ipairs(victimChar:GetDescendants()) do
						if p:IsA("BasePart") then pcall(p.SetNetworkOwner, p, state.victimPlayer) end
					end
					unragdoll(victimChar)
				end
			end)
		end
		pcall(function() rGrabNotify:FireClient(state.victimPlayer, false) end)
	end
end

RunService.Heartbeat:Connect(function()
	for _, state in pairs(grabState) do
		if state.bodyPos and state.bodyPos.Parent then
			state.lerpedPos = state.lerpedPos:Lerp(state.targetPos, CFG.POSITION_LERP_ALPHA)
			state.bodyPos.Position = state.lerpedPos

			if state.bodyGyro and state.bodyGyro.Parent then
				state.bodyGyro.CFrame = state.bodyGyro.CFrame:Lerp(state.targetCF, CFG.GYRO_LERP_ALPHA)
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

	local isNPC, npcModel, victimPlayer = classifyHit(hitPart, player)
	local rootPart = getRootPart(hitPart)
	if not rootPart or rootPart.Anchored then return end

	local char = player.Character; if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart; if not hrp then return end
	if (rootPart.Position - hrp.Position).Magnitude > CFG.GRAB_MAX_DISTANCE + 5 then return end

	if isNPC and npcModel then
		ragdoll(npcModel)
		npcModel:SetAttribute("IsGrabbed", true)
		task.wait(0.05)
	end

	if victimPlayer then
		local victimChar = victimPlayer.Character
		if victimChar then
			for _, p in ipairs(victimChar:GetDescendants()) do
				if p:IsA("BasePart") then pcall(p.SetNetworkOwner, p, nil) end
			end
			ragdoll(victimChar)
			task.wait(0.05)
		end
		pcall(function() rGrabNotify:FireClient(victimPlayer, true) end)
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
		victimPlayer = victimPlayer,
		originalSize = isLonePart and rootPart.Size or nil,
		grabStartTime = victimPlayer and tick() or nil,
	}
	pcall(function() rGrabBroadcast:FireAllClients(player, rootPart) end)
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
	pcall(function() rGrabBroadcast:FireAllClients(player, nil) end)
end)

rGrabThrow.OnServerEvent:Connect(function(player: Player, direction: Vector3, speed: number)
	local state = grabState[player]
	if not state then return end
	if typeof(direction) ~= "Vector3" then return end

	local part = state.part
	if state.frozen and part and part.Parent then part.Anchored = false end
	cleanupGrab(state, 3)
	grabState[player] = nil
	pcall(function() rGrabBroadcast:FireAllClients(player, nil) end)

	if not part or not part.Parent then return end
	speed = math.clamp(speed or CFG.THROW_FORCE, 10, CFG.THROW_FORCE * 2)

	local bv = Instance.new("BodyVelocity")
	bv.Velocity = direction.Unit * speed
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.P = 1e4
	bv.Parent = part
	task.delay(0.14, function() if bv and bv.Parent then bv:Destroy() end end)

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

rGrabEscape.OnServerEvent:Connect(function(escaper: Player)
	local grabberFound: Player? = nil
	local stateFound: any = nil

	for grabber, state in pairs(grabState) do
		if state.victimPlayer == escaper then
			grabberFound = grabber
			stateFound = state
			break
		end
	end

	if not grabberFound or not stateFound then return end

	local elapsed = tick() - (stateFound.grabStartTime or 0)
	if elapsed < CFG.GRAB_ESCAPE_TIME then return end

	local victimChar = escaper.Character
	if victimChar then task.spawn(function() unragdoll(victimChar) end) end

	cleanupGrab(stateFound, 0)
	grabState[grabberFound] = nil
	pcall(function() rGrabCancel:FireClient(grabberFound) end)
end)

rGrabFreeze.OnServerEvent:Connect(function(player: Player, isFrozen: boolean)
	local state = grabState[player]
	if not state or not state.part or not state.part.Parent then return end
	if state.victimPlayer or state.npcModel then return end

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

	if state.victimPlayer then
		local victimChar = state.victimPlayer.Character
		if victimChar then
			for _, obj in ipairs(victimChar:GetDescendants()) do
				if obj:IsA("BasePart") and obj.Name ~= "HumanoidRootPart" then obj.Color = color end
			end
		end
		return
	end

	if state.npcModel then
		for _, obj in ipairs(state.npcModel:GetDescendants()) do
			if obj:IsA("BasePart") and obj.Name ~= "HumanoidRootPart" then obj.Color = color end
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
			if obj:IsA("BasePart") and not obj:IsA("UnionOperation") then obj.Color = color end
		end
	else
		state.part.Color = color
	end
end)

rGrabScale.OnServerEvent:Connect(function(player: Player, multiplier: number)
	local state = grabState[player]
	if not state or typeof(multiplier) ~= "number" then return end
	multiplier = math.clamp(multiplier, CFG.SCALE_MIN, CFG.SCALE_MAX)

	if state.isLonePart and state.originalSize then
		local part = state.part
		if part and part.Parent then part.Size = state.originalSize * multiplier end
	end
end)

rPurchase.OnServerEvent:Connect(function(player: Player, itemId: string)
	local data = playerData[player]; if not data then return end

	local itemConfig = nil
	for _, cfg in ipairs(CFG.SHOP_ITEMS) do
		if cfg.id == itemId then itemConfig = cfg; break end
	end
	if not itemConfig or itemConfig.isStarter then return end

	if data.ownedItems[itemId] then
		spawnItemForPlayer(player, itemId)
		return
	end

	if data.coins < itemConfig.price then
		rUpdateCoins:FireClient(player, data.coins)
		return
	end

	data.coins = data.coins - itemConfig.price
	data.ownedItems[itemId] = true
	rUpdateCoins:FireClient(player, data.coins)
	spawnItemForPlayer(player, itemId)
	task.spawn(saveData, player)
end)

Players.PlayerAdded:Connect(function(player: Player)
	loadData(player)
	player.CharacterAdded:Connect(function(char)
		task.wait(1)
		local data = playerData[player]; if not data then return end
		rUpdateCoins:FireClient(player, data.coins)

		local existingPlank = workspace:FindFirstChild("WoodenPlank")
		if existingPlank then
			rSpawnItem:FireClient(player, "WoodenPlank", existingPlank)
		else
			local plank = Instance.new("Part")
			plank.Name = "WoodenPlank"
			plank.Size = Vector3.new(8, 0.5, 2)
			plank.Material = Enum.Material.Wood
			plank.Color = Color3.fromRGB(163, 120, 63)
			plank.Anchored = false
			local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart
			plank.CFrame = hrp and (hrp.CFrame * CFrame.new(0, 2, -6)) or CFrame.new(0, 5, 0)
			plank:SetAttribute("OwnerId", player.UserId)
			plank.Parent = workspace
			playerSpawnedItem[player] = plank
			rSpawnItem:FireClient(player, "WoodenPlank", plank)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	saveData(player)
	local item = playerSpawnedItem[player]
	if item and item.Parent then item:Destroy() end
	playerSpawnedItem[player] = nil
	playerData[player] = nil

	local state = grabState[player]
	if state then cleanupGrab(state, 0); grabState[player] = nil end
	for grabber, state2 in pairs(grabState) do
		if state2.victimPlayer == player then
			cleanupGrab(state2, 0)
			grabState[grabber] = nil
		end
	end
end)

-- reward block touch
task.spawn(function()
	local rewardPart = workspace:WaitForChild(CFG.REWARD_PART_NAME, 10) :: BasePart
	if not rewardPart then
		rewardPart = Instance.new("Part")
		rewardPart.Name = CFG.REWARD_PART_NAME
		rewardPart.Size = Vector3.new(4, 4, 4)
		rewardPart.Position = Vector3.new(0, 2, 25)
		rewardPart.Anchored = true
		rewardPart.Material = Enum.Material.Neon
		rewardPart.Color = Color3.fromRGB(255, 200, 50)
		rewardPart.Parent = workspace
	end

	local cooldowns: {[number]: number} = {}
	rewardPart.Touched:Connect(function(hit: BasePart)
		local char = hit.Parent
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end

		local now = tick()
		local last = cooldowns[player.UserId] or 0
		if now - last < CFG.REWARD_COOLDOWN then return end
		cooldowns[player.UserId] = now

		CoinsAPI.addCoins(player, CFG.REWARD_COINS)
	end)
end)

game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do saveData(p) end
	task.wait(2)
end)

print("[Server] v12 complete system ready.")
