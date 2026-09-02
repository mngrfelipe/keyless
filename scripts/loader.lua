if not game:IsLoaded() then
    game.Loaded:Wait()
end

if identifyexecutor then
    local execName = identifyexecutor():lower()
    if execName:find("solara") or execName:find("xeno") then
        game:GetService("Players").LocalPlayer:Kick("EXECUTOR NOT SUPPORTED[PLEASE DON'T GET MAD THIS IS SOLARA/XENO'S FAULT]")
        return
    end
end

local BASE = 'https://raw.githubusercontent.com/mngrfelipe/keyless/master/scripts/'

local games = {
    {
        display = "Kaizen",
        script = "kaizen.lua",
        find = { universe = 6048923315 }
    },
    {
        display = "Steal An Egg",
        script = "sag.lua",
        find = { universe = 10563114921 }
    },
        {
        display = "Dungeon Lootr",
        script = "lootr.lua",
        find = { universe = 9656201728 }
    },
     {
        display = "Arcane Lineage",
        script = "ArcaneLineage.lua",
        find = { universe = 3846592040 }
    },
}

local place = game.PlaceId
local universe = game.GameId

local function list(v)
    return type(v) == "table" and v or { v }
end

local marketName = nil
pcall(function()
    local info = game:GetService("MarketplaceService"):GetProductInfo(place)
    if info and info.Name then
        marketName = info.Name:lower()
    end
end)

local selected = nil
for _, g in ipairs(games) do
    local f = g.find
    if f.universe and table.find(list(f.universe), universe) then
        selected = g
        break
    end
    if f.place and table.find(list(f.place), place) then
        selected = g
        break
    end
    if f.name and marketName and marketName:find(f.name:lower()) then
        selected = g
        break
    end
end

if selected then
    local url = BASE .. selected.script
    pcall(function()
        loadstring(game:HttpGet(url))()
    end)
end
