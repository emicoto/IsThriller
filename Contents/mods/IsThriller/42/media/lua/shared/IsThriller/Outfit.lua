--  XML outfit-set catalog; Lua only selects sets and applies values XML cannot express.

local outfit = {
    base = {
        Thriller = "ThrillerStageSet",
        Criminal = "SmoothCriminalStageSet",
        BeatIt = "BeatItStageSet",
        Bad = "BadStageSet",
        BillieJean = "BillieJeanStageSet",
    },

    authZ = {
        Thriller = "AuthenticThriller",
        Criminal = "AuthenticSmoothCriminal",
        BeatIt = "AuthenticThrillerVarsity",
    },

    dancer = {
        "IsThrillerHalloweenDevil",
        "IsThrillerHalloweenMonster",
        "IsThrillerHalloweenPumpkin",
        "IsThrillerHalloweenSkeleton",
        "IsThrillerHalloweenVampire",
        "IsThrillerHalloweenWitch",
    },
    naked = "Naked",
}


local finishes = {
    ThrillerStageSet = {
        skin = "Body04",
        tint = {
            ["Base.Suit_JacketTINT"] = { 0.85, 0.08, 0.10 },
            ["Base.Shirt_FormalTINT"] = { 0.10, 0.10, 0.10 },
            ["Base.Trousers_WhiteTINT"] = { 0.75, 0.06, 0.09 },
        },
    },

    SmoothCriminalStageSet = {
        skin = "Body04",
        tint = {
            ["Base.Trousers_WhiteTINT"] = { 0.95, 0.95, 0.95 },
            ["Base.Gloves_WhiteTINT"] = { 1.00, 1.00, 1.00 },
        },
    },

    BeatItStageSet = {
        skin = "Body04",
        tint = {
            ["Base.Jacket_WhiteTINT"] = { 0.921, 0.164, 0.353 },
        },
    },

    BadStageSet = {
        skin = "Body04",
        tint = {
            ["Base.Tshirt_WhiteTINT"] = { 0.05, 0.05, 0.05 },
        },
    },

    BillieJeanStageSet = {
        skin = "Body04",
        tint = {
            ["Base.Trousers_Suit"] = { 0.05, 0.05, 0.05 },
            ["Base.Tshirt_WhiteTINT"] = { 1.00, 1.00, 1.00 },
        },
    },
}


local function resetModel(zombie)
    local ok = pcall(function() zombie:resetModelNextFrame() end)
    if not ok then
        ok = pcall(function() zombie:resetModel() end)
    end
    if not ok then  print("[LuneModDebug] <IsThriller> : outfit.finish: model reset failed") end
end

local function applySkin(zombie, skin)
    if not skin then return end

    local humanVisual = zombie:getHumanVisual()
    if not humanVisual then return end

    local body = zombie:isFemale() and "Female" or "Male"
    local textureName = body .. skin
    humanVisual:setSkinTextureName(textureName)

end

local function applyTints(zombie, tints)
    if not tints then return end

    print("[LuneModDebug] <IsThriller> : try to apply tints", zombie, tints)

    local visuals = zombie:getItemVisuals()
    if not visuals or (visuals and visuals.size and visuals:size() == 0) then
        print("[LuneModDebug] <IsThriller> : the item visuals is invalid", visuals)
        return
    end

    for i = 0, visuals:size() - 1 do
        local visual = visuals:get(i)
        local fullType = visual:getItemType()

        local rgb = fullType and tints[fullType]
        if rgb then
            local ok = pcall(function()
                visual:setTint(ImmutableColor.new(rgb[1], rgb[2], rgb[3], 1))
            end)
            if not ok then print("[LuneModDebug] <IsThriller> : outfit.finish: tint failed", fullType) end
        end
    end
end

-- XML完成生成；这里只补固定染色与皮肤，Authentic Z自己的套装不再二次处理。
function outfit.set(zombie, outfitID)
    if not zombie then return end

    local finish = finishes[outfitID]
    if not finish then return end

    applyTints(zombie, finish.tint)
    applySkin(zombie, finish.skin)
    resetModel(zombie)
end

-- 按首曲选主演套装; hasAuthZ时优先AZ套装
function outfit.pick(firstSong)
    local az = IsThriller and IsThriller.hasAuthZ

    if firstSong == "BadSong" then
        return outfit.base.Bad

    elseif firstSong == "BillieJeanSong" then
        return outfit.base.BillieJean

    elseif firstSong == "SmoothCriminalSong" then
        return az and outfit.authZ.Criminal or outfit.base.Criminal

    elseif firstSong == "BeatItSong" then
        return az and outfit.authZ.BeatIt or outfit.base.BeatIt
    end

    -- Thriller及一切兜底
    if az then return outfit.authZ.Thriller end
    return outfit.base.Thriller
end

return outfit
