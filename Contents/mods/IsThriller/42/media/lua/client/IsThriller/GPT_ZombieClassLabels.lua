-- GPTNote: Temporary IsThriller zombie-class labels driven only by actor ModData flags.

local LABEL_FONT = UIFont.Small
local LABEL_HEIGHT = 115

local drawObjects = setmetatable({}, { __mode = "k" })

local classColors = {
    mj       = { 1.00, 0.25, 0.25 },
    dancer   = { 1.00, 0.45, 0.90 },
    sprinter = { 1.00, 0.70, 0.20 },
    shambler = { 0.30, 0.90, 1.00 },
}

local function getAudienceClass(zombie)
    local speedType
    local ok = pcall(function()
        speedType = zombie:getSpeedType()
    end)

    if ok and speedType == 1 then
        return "sprinter"
    end
    return "shambler"
end

local function getClassName(zombie)
    local modData = zombie:getModData()
    if not modData then return nil end

    if modData.IsThrillerMJ then
        return "mj"
    end
    if modData.IsThrillerDancer then
        return "dancer"
    end
    if modData.IsThrillerAudience then
        return getAudienceClass(zombie)
    end
    return nil
end

local function getScreenPosition(zombie)
    local sx = IsoUtils.XToScreen(zombie:getX(), zombie:getY(), zombie:getZ(), 0)
    local sy = IsoUtils.YToScreen(zombie:getX(), zombie:getY(), zombie:getZ(), 0)

    sx = sx - IsoCamera.getOffX() - zombie:getOffsetX()
    sy = sy - IsoCamera.getOffY() - zombie:getOffsetY() - LABEL_HEIGHT

    local zoom = getCore():getZoom(0)
    return sx / zoom, sy / zoom
end

local function drawLabel(zombie, className, player)
    if not player:CanSee(zombie) then return end

    local text = drawObjects[zombie]
    if not text then
        text = TextDrawObject.new()
        drawObjects[zombie] = text
    end

    local color = classColors[className]
    text:setDefaultColors(color[1], color[2], color[3], 1.00)
    text:setOutlineColors(0.00, 0.00, 0.00, 1.00)
    text:ReadString(LABEL_FONT, className, -1)

    local sx, sy = getScreenPosition(zombie)
    text:AddBatchedDraw(sx, sy - text:getHeight(), true)
end

local function onTick()
    local player = getPlayer()
    local cell = player and player:getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then return end

    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie and zombie:isAlive() then
            local className = getClassName(zombie)
            if className then
                pcall(drawLabel, zombie, className, player)
            end
        end
    end
end

Events.OnTick.Add(onTick)
