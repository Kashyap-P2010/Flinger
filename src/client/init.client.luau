-- init.client.luau
-- complete interactive client w cheap simple shop ui & crosshair
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = localPlayer:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("GameRemotes", 10)
local function getRemote(name: string): RemoteEvent
	return remotesFolder:WaitForChild(name, 10) :: RemoteEvent
end

local rGrabStart = getRemote("GrabStart")
local rGrabMove = getRemote("GrabMove")
local rGrabRelease = getRemote("GrabRelease")
local rGrabThrow = getRemote("GrabThrow")
local rGrabFreeze = getRemote("GrabFreeze")
local rGrabColor = getRemote("GrabColor")
local rGrabScale = getRemote("GrabScale")
local rGrabNotify = getRemote("GrabNotify")
local rGrabEscape = getRemote("GrabEscape")
local rGrabCancel = getRemote("GrabCancel")
local rGrabBroadcast = getRemote("GrabBroadcast")
local rImpactVFX = getRemote("ImpactVFX")
local rPurchase = getRemote("PurchaseItem")
local rUpdateCoins = getRemote("UpdateCoins")
local rSpawnItem = getRemote("SpawnItem")

local CFG = {
	GRAB_MAX_DIST = 50,
	GRAB_MIN_DIST = 3,
	GRAB_MAX_HOLD_DIST = 40,
	GRAB_DEFAULT_DIST = 15,
	SCROLL_SENSITIVITY = 1.2,
	THROW_FLICK_THRESHOLD = 6,
	THROW_FLICK_SAMPLES = 5,
	THROW_FORCE = 140,
	ROT_SENSITIVITY = 0.004,
	SCALE_MIN = 0.15,
	SCALE_MAX = 8.0,
	SCALE_STEP = 0.03,
	GRAB_ESCAPE_TIME = 10,
	SHOP_ITEMS = {
		{ id = "WoodenPlank", displayName = "Wooden Plank", price = 0, isStarter = true },
		{ id = "Doll", displayName = "Doll", price = 200, description = "A creepy doll." },
		{ id = "Chest", displayName = "Chest", price = 350, description = "A wooden chest." },
		{ id = "Duck", displayName = "Duck", price = 500, description = "A rubber duck." },
	}
}

local COLOR_PALETTE = {
	Color3.fromRGB(255, 55, 55),
	Color3.fromRGB(55, 110, 255),
	Color3.fromRGB(55, 210, 80),
	Color3.fromRGB(255, 215, 50),
	Color3.fromRGB(255, 80, 200),
	Color3.fromRGB(255, 145, 40),
	Color3.fromRGB(150, 55, 255),
	Color3.fromRGB(0, 255, 200),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(35, 35, 35),
}
local colorIdx = 1

local grabbed: BasePart? = nil
local grabDist = CFG.GRAB_DEFAULT_DIST
local rotating = false
local frozen = false
local frozenPos: Vector3? = nil
local rotateCF = CFrame.identity
local scalingUp = false
local scalingDown = false
local scaleMulti = 1.0
local lastScaleSend = 0

local isBeingHeld = false
local holdStartTime = 0
local escapeAvailable = false

local currentCoins = 0
local shopOpen = false
local ownedItems: {[string]: boolean} = { WoodenPlank = true }

local lastMousePos = Vector2.new(0, 0)
local mouseSpeedBuf: {number} = {}

local function recordMouse()
	local pos = UIS:GetMouseLocation()
	local spd = (pos - lastMousePos).Magnitude
	lastMousePos = pos
	table.insert(mouseSpeedBuf, spd)
	if #mouseSpeedBuf > CFG.THROW_FLICK_SAMPLES then
		table.remove(mouseSpeedBuf, 1)
	end
end

local function avgMouseSpeed(): number
	if #mouseSpeedBuf == 0 then return 0 end
	local s = 0
	for _, v in ipairs(mouseSpeedBuf) do s = s + v end
	return s / #mouseSpeedBuf
end

local function enforceFirstPerson()
	if not isBeingHeld and not shopOpen then
		camera.CameraType = Enum.CameraType.Custom
		localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		localPlayer.CameraMinZoomDistance = 0.5
		localPlayer.CameraMaxZoomDistance = 0.5
	end
end

UIS.MouseIconEnabled = false

-- cheap clean ui root
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlingGameUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- cheap crosshair
local crosshair = Instance.new("Frame")
crosshair.Name = "Crosshair"
crosshair.Size = UDim2.new(0, 16, 0, 16)
crosshair.Position = UDim2.new(0.5, -8, 0.5, -8)
crosshair.BackgroundTransparency = 1
crosshair.Parent = screenGui

local chH = Instance.new("Frame", crosshair)
chH.Size = UDim2.new(1, 0, 0, 2); chH.Position = UDim2.new(0, 0, 0.5, -1)
chH.BackgroundColor3 = Color3.fromRGB(0, 255, 180); chH.BorderSizePixel = 0

local chV = Instance.new("Frame", crosshair)
chV.Size = UDim2.new(0, 2, 1, 0); chV.Position = UDim2.new(0.5, -1, 0, 0)
chV.BackgroundColor3 = Color3.fromRGB(0, 255, 180); chV.BorderSizePixel = 0

-- cheap coin counter
local coinHUD = Instance.new("Frame")
coinHUD.Size = UDim2.new(0, 100, 0, 30)
coinHUD.Position = UDim2.new(1, -112, 0, 12)
coinHUD.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
coinHUD.BackgroundTransparency = 0.2
coinHUD.BorderSizePixel = 0
coinHUD.Parent = screenGui
Instance.new("UICorner", coinHUD).CornerRadius = UDim.new(0, 6)

local coinLabel = Instance.new("TextLabel", coinHUD)
coinLabel.Size = UDim2.new(1, 0, 1, 0)
coinLabel.BackgroundTransparency = 1
coinLabel.Font = Enum.Font.GothamBold
coinLabel.TextSize = 14
coinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
coinLabel.Text = "🪙 0"

-- cheap bottom-left hud
local hud = Instance.new("Frame")
hud.Name = "ControlsHUD"
hud.Size = UDim2.new(0, 170, 0, 0)
hud.AutomaticSize = Enum.AutomaticSize.Y
hud.Position = UDim2.new(0, 12, 1, -12)
hud.AnchorPoint = Vector2.new(0, 1)
hud.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
hud.BackgroundTransparency = 0.3
hud.BorderSizePixel = 0
hud.Parent = screenGui
Instance.new("UICorner", hud).CornerRadius = UDim.new(0, 6)

local pad = Instance.new("UIPadding", hud)
pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)

local list = Instance.new("UIListLayout", hud)
list.Padding = UDim.new(0, 3)

local function makeHudRow(txt: string)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 16)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Gotham
	l.TextSize = 12
	l.TextColor3 = Color3.fromRGB(200, 200, 210)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = txt
	l.Parent = hud
	return l
end

makeHudRow("[LMB] Grab")
local rotLabel = makeHudRow("[R] Rotate")
local freezeLabel = makeHudRow("[F] Freeze Ray")
makeHudRow("[C] Color")
makeHudRow("[Z/X] Scale")
makeHudRow("[Scroll] Dist")
makeHudRow("[RMB] Throw")
makeHudRow("[E] Shop")

-- cheap simple shop panel
local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
shopFrame.Size = UDim2.new(0, 480, 0, 320)
shopFrame.Position = UDim2.new(0.5, -240, 0.5, -160)
shopFrame.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
shopFrame.BorderSizePixel = 0
shopFrame.Visible = false
shopFrame.Parent = screenGui
Instance.new("UICorner", shopFrame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel", shopFrame)
title.Size = UDim2.new(1, -40, 0, 36)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Shop"

local closeBtn = Instance.new("TextButton", shopFrame)
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.BorderSizePixel = 0
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

local itemsScroll = Instance.new("ScrollingFrame", shopFrame)
itemsScroll.Size = UDim2.new(1, -20, 1, -46)
itemsScroll.Position = UDim2.new(0, 10, 0, 38)
itemsScroll.BackgroundTransparency = 1
itemsScroll.BorderSizePixel = 0
itemsScroll.ScrollBarThickness = 4

local grid = Instance.new("UIGridLayout", itemsScroll)
grid.CellSize = UDim2.new(0, 140, 0, 180)
grid.CellPadding = UDim2.new(0, 10, 0, 10)

local buyButtons: {[string]: TextButton} = {}

for _, item in ipairs(CFG.SHOP_ITEMS) do
	if item.isStarter then continue end

	local card = Instance.new("Frame", itemsScroll)
	card.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
	card.BorderSizePixel = 0
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

	local vp = Instance.new("ViewportFrame", card)
	vp.Size = UDim2.new(1, -12, 0, 80)
	vp.Position = UDim2.new(0, 6, 0, 6)
	vp.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	vp.BorderSizePixel = 0
	Instance.new("UICorner", vp).CornerRadius = UDim.new(0, 4)

	local vpCam = Instance.new("Camera", vp)
	vp.CurrentCamera = vpCam

	local template = ReplicatedStorage:FindFirstChild(item.id)
	if template then
		local clone = template:Clone()
		clone.Parent = vp
		if clone:IsA("Model") and clone.PrimaryPart then
			clone:SetPrimaryPartCFrame(CFrame.new(0, 0, 0))
			vpCam.CFrame = CFrame.new(Vector3.new(0, 2, 6), Vector3.new(0, 0, 0))
		elseif clone:IsA("BasePart") then
			clone.CFrame = CFrame.new(0, 0, 0)
			vpCam.CFrame = CFrame.new(Vector3.new(0, 2, 6), Vector3.new(0, 0, 0))
		end
	end

	local nameL = Instance.new("TextLabel", card)
	nameL.Size = UDim2.new(1, 0, 0, 20)
	nameL.Position = UDim2.new(0, 0, 0, 90)
	nameL.BackgroundTransparency = 1
	nameL.Font = Enum.Font.GothamBold
	nameL.TextSize = 13
	nameL.TextColor3 = Color3.fromRGB(240, 240, 240)
	nameL.Text = item.displayName

	local priceL = Instance.new("TextLabel", card)
	priceL.Size = UDim2.new(1, 0, 0, 16)
	priceL.Position = UDim2.new(0, 0, 0, 112)
	priceL.BackgroundTransparency = 1
	priceL.Font = Enum.Font.Gotham
	priceL.TextSize = 12
	priceL.TextColor3 = Color3.fromRGB(255, 215, 0)
	priceL.Text = "🪙 " .. item.price

	local btn = Instance.new("TextButton", card)
	btn.Size = UDim2.new(1, -16, 0, 26)
	btn.Position = UDim2.new(0, 8, 1, -34)
	btn.BackgroundColor3 = Color3.fromRGB(0, 200, 150)
	btn.Text = "Buy"
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(10, 20, 15)
	btn.BorderSizePixel = 0
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

	btn.Activated:Connect(function() rPurchase:FireServer(item.id) end)
	buyButtons[item.id] = btn
end

local function refreshShopCards()
	for _, item in ipairs(CFG.SHOP_ITEMS) do
		local btn = buyButtons[item.id]
		if not btn then continue end
		if ownedItems[item.id] then
			btn.Text = "Equipped"
			btn.BackgroundColor3 = Color3.fromRGB(50, 160, 90)
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		elseif currentCoins >= item.price then
			btn.Text = "Buy"
			btn.BackgroundColor3 = Color3.fromRGB(0, 200, 150)
			btn.TextColor3 = Color3.fromRGB(10, 20, 15)
		else
			btn.Text = "Locked"
			btn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
			btn.TextColor3 = Color3.fromRGB(140, 140, 150)
		end
	end
end

local function openShop()
	shopOpen = true
	shopFrame.Visible = true
	UIS.MouseIconEnabled = true
	crosshair.Visible = false
	refreshShopCards()
end

local function closeShop()
	shopOpen = false
	shopFrame.Visible = false
	UIS.MouseIconEnabled = false
	crosshair.Visible = true
	enforceFirstPerson()
end

closeBtn.Activated:Connect(closeShop)

RS:BindToRenderStep("ShopMouseOverride", Enum.RenderPriority.Camera.Value + 1, function()
	if shopOpen then UIS.MouseBehavior = Enum.MouseBehavior.Default end
end)

-- cheap escape hud
local escapeFrame = Instance.new("Frame")
escapeFrame.Name = "EscapeHUD"
escapeFrame.Size = UDim2.new(0, 260, 0, 42)
escapeFrame.Position = UDim2.new(0.5, -130, 0.8, 0)
escapeFrame.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
escapeFrame.BorderSizePixel = 0
escapeFrame.Visible = false
escapeFrame.Parent = screenGui
Instance.new("UICorner", escapeFrame).CornerRadius = UDim.new(0, 6)

local escapeLabel = Instance.new("TextLabel", escapeFrame)
escapeLabel.Size = UDim2.new(1, 0, 1, 0)
escapeLabel.BackgroundTransparency = 1
escapeLabel.Font = Enum.Font.GothamBold
escapeLabel.TextSize = 13
escapeLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
escapeLabel.Text = "HELD! Escaping in 10s..."

local victimConn: RBXScriptConnection? = nil

rGrabNotify.OnClientEvent:Connect(function(isHeld: boolean)
	if isHeld then
		isBeingHeld = true
		holdStartTime = tick()
		escapeAvailable = false
		escapeFrame.Visible = true
		escapeLabel.TextColor3 = Color3.fromRGB(255, 100, 100)

		local char = localPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.PlatformStand = true
				hum.AutoRotate = false
				hum:ChangeState(Enum.HumanoidStateType.Physics)
			end
			for _, desc in ipairs(char:GetDescendants()) do
				if desc:IsA("Motor6D") then desc.Enabled = false end
			end
		end

		localPlayer.CameraMode = Enum.CameraMode.Classic
		localPlayer.CameraMaxZoomDistance = 10
		localPlayer.CameraMinZoomDistance = 5

		if victimConn then victimConn:Disconnect() end
		victimConn = RS.Heartbeat:Connect(function()
			local elapsed = tick() - holdStartTime
			if elapsed >= CFG.GRAB_ESCAPE_TIME then
				escapeAvailable = true
				escapeLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
				escapeLabel.Text = "READY! Press [Space] to break free"
			else
				local rem = math.ceil(CFG.GRAB_ESCAPE_TIME - elapsed)
				escapeLabel.Text = "HELD! Escape ready in " .. rem .. "s..."
			end
		end)
	else
		isBeingHeld = false
		escapeAvailable = false
		escapeFrame.Visible = false

		local char = localPlayer.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.PlatformStand = false
				hum.AutoRotate = true
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
			for _, desc in ipairs(char:GetDescendants()) do
				if desc:IsA("Motor6D") then desc.Enabled = true end
			end
		end

		if victimConn then victimConn:Disconnect(); victimConn = nil end
		enforceFirstPerson()
	end
end)

rGrabCancel.OnClientEvent:Connect(function()
	if grabbed then
		grabbed = nil
		rotating = false
		frozen = false
		frozenPos = nil
	end
end)

rUpdateCoins.OnClientEvent:Connect(function(coins: number)
	currentCoins = coins
	coinLabel.Text = "🪙 " .. tostring(coins)
	refreshShopCards()
end)

rSpawnItem.OnClientEvent:Connect(function(itemId: string)
	ownedItems[itemId] = true
	refreshShopCards()
end)

-- impact particles & debris
local function spawnImpactVFX(pos: Vector3, speed: number)
	local intensity = math.clamp(speed / 90, 0.4, 3.5)
	local flash = Instance.new("Part")
	flash.Name = "_ImpactFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.1, 0.1, 0.1)
	flash.Position = pos
	flash.Anchored = true; flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 200, 80)
	flash.Parent = workspace

	local light = Instance.new("PointLight")
	light.Brightness = 9; light.Range = intensity * 30
	light.Color = Color3.fromRGB(255, 175, 50); light.Parent = flash

	TweenService:Create(flash, TweenInfo.new(0.28), {
		Size = Vector3.new(intensity * 5, intensity * 5, intensity * 5),
		Transparency = 1,
	}):Play()
	TweenService:Create(light, TweenInfo.new(0.22), {Brightness = 0}):Play()
	Debris:AddItem(flash, 1.2)

	local numBits = math.floor(math.clamp(intensity * 4, 2, 12))
	for _ = 1, numBits do
		local bit = Instance.new("Part")
		bit.Name = "_ImpactDebris"
		bit.Size = Vector3.new(0.4, 0.4, 0.4) * (math.random() * 0.5 + 0.5) * intensity
		bit.Position = pos + Vector3.new(math.random(-10, 10) / 10, math.random(0, 10) / 10, math.random(-10, 10) / 10)
		bit.Material = Enum.Material.Slate
		bit.Color = Color3.fromRGB(120, 120, 120)
		bit.CanCollide = true
		bit.Parent = workspace

		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		local spread = Vector3.new(math.random(-100, 100) / 100, math.random(50, 150) / 100, math.random(-100, 100) / 100)
		bv.Velocity = spread.Unit * (math.random(15, 45) * intensity)
		bv.Parent = bit

		Debris:AddItem(bv, 0.1)
		Debris:AddItem(bit, math.random(2, 4))
	end
end

rImpactVFX.OnClientEvent:Connect(function(pos: Vector3, speed: number)
	spawnImpactVFX(pos, speed)
end)

-- red beams for other players
local otherGrabs: {[Player]: {folder: Folder?, conn: RBXScriptConnection?}} = {}

local function removeOtherBeam(grabber: Player)
	local d = otherGrabs[grabber]
	if d then
		if d.conn then d.conn:Disconnect() end
		if d.folder and d.folder.Parent then d.folder:Destroy() end
		otherGrabs[grabber] = nil
	end
end

local function createOtherBeam(grabber: Player, part: BasePart)
	removeOtherBeam(grabber)
	local char = grabber.Character; if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart; if not hrp then return end

	local folder = Instance.new("Folder")
	folder.Name = "_OtherFling_" .. grabber.Name
	folder.Parent = workspace

	local p0 = Instance.new("Part"); p0.Size = Vector3.new(0.05, 0.05, 0.05)
	p0.Anchored = true; p0.CanCollide = false; p0.Transparency = 1; p0.Parent = folder
	local p1 = Instance.new("Part"); p1.Size = Vector3.new(0.05, 0.05, 0.05)
	p1.Anchored = true; p1.CanCollide = false; p1.Transparency = 1; p1.Parent = folder
	local a0 = Instance.new("Attachment", p0)
	local a1 = Instance.new("Attachment", p1)

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0; beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 60, 60))
	beam.Width0 = 0.25; beam.Width1 = 0.08
	beam.FaceCamera = true
	beam.Parent = p0

	local conn = RS.RenderStepped:Connect(function()
		if not hrp.Parent or not part.Parent then removeOtherBeam(grabber); return end
		p0.CFrame = CFrame.new(hrp.Position)
		p1.CFrame = CFrame.new(part.Position)
		local dist = (part.Position - hrp.Position).Magnitude
		beam.CurveSize0 = dist * 0.2; beam.CurveSize1 = dist * 0.2
	end)

	otherGrabs[grabber] = { folder = folder, conn = conn }
end

rGrabBroadcast.OnClientEvent:Connect(function(grabber: Player, part: BasePart?)
	if grabber == localPlayer then return end
	if part then createOtherBeam(grabber, part) else removeOtherBeam(grabber) end
end)

local beamFolder: Folder? = nil
local beamPart0: Part? = nil
local beamPart1: Part? = nil
local ballPart: Part? = nil
local beamRef: Beam? = nil

local function destroyVisuals()
	if beamFolder then beamFolder:Destroy(); beamFolder = nil end
	beamPart0 = nil; beamPart1 = nil; ballPart = nil; beamRef = nil
end

local function createVisuals(targetPart: BasePart)
	destroyVisuals()

	local folder = Instance.new("Folder")
	folder.Name = "_FlingVisuals"
	folder.Parent = workspace
	beamFolder = folder

	local function makeAnchor(cf: CFrame): Part
		local p = Instance.new("Part")
		p.Size = Vector3.new(0.05, 0.05, 0.05)
		p.Anchored = true; p.CanCollide = false
		p.Transparency = 1; p.Parent = folder
		p.CFrame = cf
		return p
	end

	local p0 = makeAnchor(camera.CFrame)
	local p1 = makeAnchor(targetPart.CFrame)
	local a0 = Instance.new("Attachment", p0)
	local a1 = Instance.new("Attachment", p1)

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0; beam.Attachment1 = a1
	beam.Color = ColorSequence.new(Color3.fromRGB(0, 255, 180))
	beam.Width0 = 0.25; beam.Width1 = 0.08
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Parent = p0
	beamRef = beam

	local ball = Instance.new("Part")
	ball.Name = "_FlingBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.4, 0.4, 0.4)
	ball.Anchored = true; ball.CanCollide = false
	ball.Material = Enum.Material.Neon
	ball.Color = Color3.fromRGB(0, 255, 180)
	ball.CFrame = targetPart.CFrame
	ball.Parent = folder

	beamPart0 = p0; beamPart1 = p1; ballPart = ball
end

local function updateVisuals(targetPart: BasePart)
	if not beamPart0 or not beamPart1 or not ballPart then return end

	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	local origin = hrp and hrp.Position or camera.CFrame.Position
	local objPos = targetPart.Position

	beamPart0.CFrame = CFrame.new(origin, objPos)
	beamPart1.CFrame = CFrame.new(objPos, origin)
	ballPart.CFrame = CFrame.new(objPos)

	local dist = (objPos - origin).Magnitude
	if beamRef then
		beamRef.CurveSize0 = dist * 0.2
		beamRef.CurveSize1 = dist * 0.2
	end
end

local function clearGrabState()
	grabbed = nil
	rotating = false
	frozen = false
	frozenPos = nil
	scalingUp = false
	scalingDown = false
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	destroyVisuals()
	rotLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	freezeLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
end

local function tryGrab()
	if grabbed or isBeingHeld or shopOpen then return end
	local char = localPlayer.Character; if not char then return end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {char}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(
		camera.CFrame.Position,
		camera.CFrame.LookVector * CFG.GRAB_MAX_DIST,
		params
	)
	if not result then return end
	local hp = result.Instance
	if not hp or not hp:IsA("BasePart") or hp.Anchored then return end

	grabbed = hp
	grabDist = math.clamp(result.Distance, CFG.GRAB_MIN_DIST, CFG.GRAB_MAX_HOLD_DIST)
	rotateCF = hp.CFrame.Rotation
	frozen = false; frozenPos = nil
	scaleMulti = 1.0
	mouseSpeedBuf = {}
	createVisuals(hp)
	rGrabStart:FireServer(hp)
end

local function releaseGrab()
	if not grabbed then return end
	rGrabRelease:FireServer()
	clearGrabState()
end

local function throwGrab()
	if not grabbed then return end
	local speed = math.clamp(
		CFG.THROW_FORCE * (0.7 + avgMouseSpeed() / 20),
		CFG.THROW_FORCE * 0.6,
		CFG.THROW_FORCE * 2
	)
	rGrabThrow:FireServer(camera.CFrame.LookVector, speed)
	clearGrabState()
end

UIS.InputBegan:Connect(function(input: InputObject, gp: boolean)
	if input.KeyCode == Enum.KeyCode.Space and isBeingHeld then
		if escapeAvailable then rGrabEscape:FireServer() end
		return
	end

	if gp or isBeingHeld then return end

	if input.KeyCode == Enum.KeyCode.E then
		if shopOpen then closeShop() else openShop() end
		return
	end

	if shopOpen then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not grabbed then tryGrab() end
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if grabbed then
			if avgMouseSpeed() >= CFG.THROW_FLICK_THRESHOLD then throwGrab() else releaseGrab() end
		end
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		releaseGrab()
		return
	end

	if not grabbed then return end

	if input.KeyCode == Enum.KeyCode.R then
		rotating = not rotating
		if rotating then
			frozenPos = camera.CFrame.Position + camera.CFrame.LookVector * grabDist
			UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			rotLabel.TextColor3 = Color3.fromRGB(0, 255, 180)
		else
			frozenPos = nil
			UIS.MouseBehavior = Enum.MouseBehavior.Default
			rotLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		frozen = not frozen
		rGrabFreeze:FireServer(frozen)
		freezeLabel.TextColor3 = frozen and Color3.fromRGB(80, 180, 255) or Color3.fromRGB(200, 200, 210)
		return
	end

	if input.KeyCode == Enum.KeyCode.C then
		colorIdx = (colorIdx % #COLOR_PALETTE) + 1
		local col = COLOR_PALETTE[colorIdx]
		rGrabColor:FireServer(col)
		return
	end

	if input.KeyCode == Enum.KeyCode.Z then scalingUp = true; return end
	if input.KeyCode == Enum.KeyCode.X then scalingDown = true; return end
end)

UIS.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.Z then scalingUp = false end
	if input.KeyCode == Enum.KeyCode.X then scalingDown = false end
end)

UIS.InputChanged:Connect(function(input: InputObject, gp: boolean)
	if gp or not grabbed or isBeingHeld or shopOpen then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		grabDist = math.clamp(
			grabDist + input.Position.Z * CFG.SCROLL_SENSITIVITY,
			CFG.GRAB_MIN_DIST,
			CFG.GRAB_MAX_HOLD_DIST
		)
	end
end)

RS.RenderStepped:Connect(function(dt: number)
	recordMouse()
	enforceFirstPerson()
	if not grabbed or not grabbed.Parent then
		if grabbed then clearGrabState() end
		return
	end

	if rotating then
		local delta = UIS:GetMouseDelta()
		local s = dt * 60
		local yaw = -delta.X * CFG.ROT_SENSITIVITY * s
		local pitch = -delta.Y * CFG.ROT_SENSITIVITY * s
		rotateCF = CFrame.Angles(0, yaw, 0) * rotateCF * CFrame.Angles(pitch, 0, 0)
	end

	if scalingUp or scalingDown then
		local delta = scalingUp and CFG.SCALE_STEP or -CFG.SCALE_STEP
		local newMul = math.clamp(scaleMulti + delta, CFG.SCALE_MIN, CFG.SCALE_MAX)
		if newMul ~= scaleMulti then
			scaleMulti = newMul
			local now = tick()
			if now - lastScaleSend >= 1 / 20 then
				lastScaleSend = now
				rGrabScale:FireServer(scaleMulti)
			end
		end
	end

	local targetPos = rotating and (frozenPos :: Vector3) or (camera.CFrame.Position + camera.CFrame.LookVector * grabDist)
	local targetCF = rotating and (CFrame.new(targetPos) * rotateCF) or (CFrame.new(targetPos) * grabbed.CFrame.Rotation)

	updateVisuals(grabbed)

	if not frozen then
		rGrabMove:FireServer(targetPos, targetCF)
	end
end)

print("[Client] v12 complete system active.")
