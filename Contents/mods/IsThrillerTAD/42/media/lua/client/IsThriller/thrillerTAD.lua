-- 接通 IsThriller 主流程节拍与 TAD 丧尸舞蹈动画，统一控制主演和既有伴舞。
IsThrillerTAD = IsThrillerTAD or {
    dancing = false,
    moveIdx = 1,
    moveBeat = 0,
    active = {},
    cooldowns = {},
}

local A = IsThrillerTAD
local st, util = IsThriller, IsThriller.util

local Config = {
    danceRange = 4,
    danceExitRange = 7,
    dancerRange = 6,
    beatsPerMove = 10,
}

local Dance_Move = {
    "BobTA_Thriller_One",
    "BobTA_Thriller_Two",
    "BobTA_Thriller_Three",
    "BobTA_Thriller_Four",
}

local function dMsg(...)
    return util.debugMsg(...)
end

-- 通用: DJ和伴舞共用的起舞/收舞
local function setZombieDance(z, on, move)
    if on then
        pcall(function()
            z:setUseless(true)
            z:setVariable("ThrillerMove", move)
            z:setVariable("bThrillerDance", true)
        end)
        dMsg("the dancer just begin dance.")
    else
        pcall(function()
            z:setVariable("bThrillerDance", false)
            z:setUseless(false)
            dMsg("the dancer just stop dance.")
        end)
    end
end

local function stopAllDances()
    local active = A.active
    A.active = {}

    for zombie in pairs(active) do
        setZombieDance(zombie, false)
    end
end

local function currentMove(id)
    return Dance_Move[id]
end

-- 伴舞被打: 退场 + 进入冷却并立刻反击
local function dancerHit(zombie, player)
    for i = #A.dancers, 1, -1 do
        if A.dancers[i] == zombie then
            table.remove(A.dancers, i)
        end
    end

    local md = zombie:getModData()
    md.thriller_stage_cooldown = Config.grudgeBeats
    
    setZombieDance(zombie, false)
    pcall(function() zombie:setTarget(player) end)
end

-- 当周围丧尸数量足够多时，随机招募不在交战区的伴舞进入舞台一起跳。
local function recuitBackup(player)
end

function A.release(st)
    stopAllDances()
    A.dancing = false
    A.moveIdx = 1
    A.moveBeat = 0
    A.mjGrudge = 0
    A.cooldowns = {}
end

