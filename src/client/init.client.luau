-- init.client.luau
-- basic grab client w raycast & 1st person lock
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotesFolder = ReplicatedStorage:WaitForChild("GameRemotes", 10)
local rGrabStart = remotesFolder:WaitForChild("GrabStart") :: RemoteEvent
local rGrabMove = remotesFolder:WaitForChild("GrabMove") :: RemoteEvent
local rGrabRelease = remotesFolder:WaitForChild("GrabRelease") :: RemoteEvent

local GRAB_MAX_DIST = 50
local GRAB_DEFAULT_DIST = 15

local grabbed: BasePart? = nil
local grabDist = GRAB_DEFAULT_DIST

-- lock camera to 1st person
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

	-- cast forward from cam center
	local result = workspace:Raycast(
		camera.CFrame.Position,
		camera.CFrame.LookVector * GRAB_MAX_DIST,
		params
	)
	if not result then return end
	local hp = result.Instance
	if not hp or not hp:IsA("BasePart") or hp.Anchored then return end

	grabbed = hp
	grabDist = math.clamp(result.Distance, 3, 40)
	rGrabStart:FireServer(hp)
end

local function releaseGrab()
	if not grabbed then return end
	grabbed = nil
	rGrabRelease:FireServer()
end

UIS.InputBegan:Connect(function(input: InputObject, gp: boolean)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not grabbed then tryGrab() else releaseGrab() end
	end
end)

RS.RenderStepped:Connect(function()
	enforceFirstPerson()
	if not grabbed or not grabbed.Parent then
		grabbed = nil
		return
	end

	local targetPos = camera.CFrame.Position + camera.CFrame.LookVector * grabDist
	local targetCF = CFrame.new(targetPos) * grabbed.CFrame.Rotation
	rGrabMove:FireServer(targetPos, targetCF)
end)

print("[Client] v01 grab loaded.")
