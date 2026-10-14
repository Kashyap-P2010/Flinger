-- init.client.luau
-- beam visual & simple crosshair
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = localPlayer:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("GameRemotes", 10)
local rGrabStart = remotesFolder:WaitForChild("GrabStart") :: RemoteEvent
local rGrabMove = remotesFolder:WaitForChild("GrabMove") :: RemoteEvent
local rGrabRelease = remotesFolder:WaitForChild("GrabRelease") :: RemoteEvent

local GRAB_MAX_DIST = 50
local GRAB_MIN_DIST = 3
local GRAB_MAX_HOLD_DIST = 40
local GRAB_DEFAULT_DIST = 15
local SCROLL_SENSITIVITY = 1.2

local grabbed: BasePart? = nil
local grabDist = GRAB_DEFAULT_DIST

-- hide standard cursor
UIS.MouseIconEnabled = false

-- cheap simple crosshair
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FlingUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local crosshair = Instance.new("Frame")
crosshair.Name = "Crosshair"
crosshair.Size = UDim2.new(0, 16, 0, 16)
crosshair.Position = UDim2.new(0.5, -8, 0.5, -8)
crosshair.BackgroundTransparency = 1
crosshair.Parent = screenGui

local chH = Instance.new("Frame", crosshair)
chH.Size = UDim2.new(1, 0, 0, 2)
chH.Position = UDim2.new(0, 0, 0.5, -1)
chH.BackgroundColor3 = Color3.fromRGB(0, 255, 180)
chH.BorderSizePixel = 0

local chV = Instance.new("Frame", crosshair)
chV.Size = UDim2.new(0, 2, 1, 0)
chV.Position = UDim2.new(0.5, -1, 0, 0)
chV.BackgroundColor3 = Color3.fromRGB(0, 255, 180)
chV.BorderSizePixel = 0

-- beam visual parts
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

local function enforceFirstPerson()
	camera.CameraType = Enum.CameraType.Custom
	localPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	localPlayer.CameraMinZoomDistance = 0.5
	localPlayer.CameraMaxZoomDistance = 0.5
end

local function tryGrab()
	if grabbed then return end
	local char = localPlayer.Character; if not char then return end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {char}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(
		camera.CFrame.Position,
		camera.CFrame.LookVector * GRAB_MAX_DIST,
		params
	)
	if not result then return end
	local hp = result.Instance
	if not hp or not hp:IsA("BasePart") or hp.Anchored then return end

	grabbed = hp
	grabDist = math.clamp(result.Distance, GRAB_MIN_DIST, GRAB_MAX_HOLD_DIST)
	createVisuals(hp)
	rGrabStart:FireServer(hp)
end

local function releaseGrab()
	if not grabbed then return end
	grabbed = nil
	destroyVisuals()
	rGrabRelease:FireServer()
end

UIS.InputBegan:Connect(function(input: InputObject, gp: boolean)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not grabbed then tryGrab() else releaseGrab() end
	end
end)

UIS.InputChanged:Connect(function(input: InputObject, gp: boolean)
	if gp or not grabbed then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		grabDist = math.clamp(
			grabDist + input.Position.Z * SCROLL_SENSITIVITY,
			GRAB_MIN_DIST,
			GRAB_MAX_HOLD_DIST
		)
	end
end)

RS.RenderStepped:Connect(function()
	enforceFirstPerson()
	if not grabbed or not grabbed.Parent then
		if grabbed then releaseGrab() end
		return
	end

	local targetPos = camera.CFrame.Position + camera.CFrame.LookVector * grabDist
	local targetCF = CFrame.new(targetPos) * grabbed.CFrame.Rotation
	updateVisuals(grabbed)
	rGrabMove:FireServer(targetPos, targetCF)
end)

print("[Client] v03 beam & crosshair active.")
