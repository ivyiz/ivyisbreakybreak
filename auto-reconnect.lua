-- Madium Auto Reconnect
-- Rejoins the same place/job when the client gets disconnected.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")

local placeId = game.PlaceId
local jobId = game.JobId
local player = Players.LocalPlayer
local lastAttempt = 0

local function notify(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Auto Reconnect",
            Text = text,
            Duration = 5,
        })
    end)
end

local function rejoin(reason)
    if os.clock() - lastAttempt < 10 then
        return
    end
    lastAttempt = os.clock()
    notify(reason or "Disconnected - rejoining...")

    if jobId and jobId ~= "" then
        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(placeId, jobId, player)
        end)
        if ok then
            return
        end
    end

    pcall(function()
        TeleportService:TeleportAsync(placeId, { player })
    end)
end

pcall(function()
    GuiService.ErrorMessageChanged:Connect(function()
        local message = ""
        pcall(function()
            message = GuiService:GetErrorMessage()
        end)
        if message ~= "" then
            rejoin("Disconnected - rejoining...")
        else
            rejoin("Reconnecting...")
        end
    end)
end)

if player then
    player.AncestryChanged:Connect(function(_, parent)
        if not parent then
            rejoin("Lost connection - rejoining...")
        end
    end)
end

pcall(function()
    Players.PlayerRemoving:Connect(function(removing)
        if removing == Players.LocalPlayer then
            rejoin("Disconnected - rejoining...")
        end
    end)
end)

task.spawn(function()
    while true do
        task.wait(5)
        local current = Players.LocalPlayer
        if not current or not current:IsDescendantOf(game) then
            rejoin("Lost connection - rejoining...")
        end
    end
end)
