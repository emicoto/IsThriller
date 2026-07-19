-- ClaudeNote: TAD分支重写(P5a) — 纯执行器。只做三件事: 舞步表管理/按拍轮换/起舞收舞执行。
-- danceRange判定、挨打退舞、冷却复舞、群演招募等全部收归主MOD(Actors.lua), 本文件不做任何判定。
-- 舞步表数据驱动: 编排拍板后用 IsThrillerTAD.setMoves(list) 直接换表。
-- 放置: Contents/mods/IsThrillerTAD/42/media/lua/client/IsThriller/thrillerTAD.lua (整文件替换)

IsThrillerTAD = IsThrillerTAD or {}
local A = IsThrillerTAD

A.active = A.active or {}       -- zombie -> true, 当前在跳的名单
A.moveIdx = A.moveIdx or 1
A.moveBeat = A.moveBeat or 0
A.beatsPerMove = 15             -- 每几拍轮换一段舞(主拍~1秒/拍, 由主MOD runTADBeat驱动)

-- 默认舞步表(占位): 用户实测各TAD动作后重新编舞, setMoves换表
A.moves = {
    "BobTA_Thriller_One",
    "BobTA_Thriller_Two",
    "BobTA_Thriller_Three",
    "BobTA_Thriller_Four",
}

A.walks = {
    "BobTA_MoonWalk_One",
    "BobTA_Moonwalk_Two"
}

local function dMsg(...)
    if IsThriller and IsThriller.util then
        IsThriller.util.debugMsg("[TAD]", ...)
    end
end

-- 换编舞入口: IsThrillerTAD.setMoves({"BobTA_xxx", ...})
function A.setMoves(list)
    if type(list) ~= "table" or #list == 0 then return false end
    A.moves = list
    A.moveIdx = 1
    A.moveBeat = 0
    dMsg("moves replaced, count=", #list)
    return true
end

function A.currentMove()
    return A.moves[A.moveIdx]
end

-- 起舞/收舞执行器(主MOD唯一调用入口)
-- on=true: 站桩+挂舞蹈变量并入active名单; on=false: 解除并移出名单
function A.setDance(zombie, on, move)
    if not zombie then return end
    if on then
        pcall(function()
            -- ClaudeNote: FlickerFix — 起舞前"净身": 清目标+把寻路目的地设为原地(等效取消在途路径,
            -- 反编译报告: 每次pathToLocationF调用都会cancel上一条寻路请求)。
            -- 不净身的话zombie brain带着target/path持续切状态, 舞蹈动画每帧重进=闪烁
            zombie:setTarget(nil)
            zombie:pathToLocationF(zombie:getX(), zombie:getY(), zombie:getZ())
            zombie:setUseless(true)
            zombie:setVariable("ThrillerMove", move or A.currentMove())
            zombie:setVariable("bThrillerDance", true)
        end)
        A.active[zombie] = true
    else
        pcall(function()
            zombie:setVariable("bThrillerDance", false)
            zombie:setUseless(false)
        end)
        A.active[zombie] = nil
    end
end

-- 主MOD每拍调用(Stage.runTADBeat): 只负责按拍轮换舞步并同步给active名单
-- 死亡个体顺带剔除; 谁该跳谁不该跳由主MOD在拍间通过setDance增删
function A.onBeat(mt, player)
    -- ClaudeNote: FlickerFix — 每拍巡查active名单: 目标/寻路被引擎(声音刺激等)重新挂上的,
    -- 当拍掐掉, 保证跳舞中的个体持续"无欲无求"
    for zombie in pairs(A.active) do
        if zombie:isDead() then
            A.active[zombie] = nil
        else
            pcall(function()
                if zombie:getTarget() ~= nil then
                    zombie:setTarget(nil)
                end
            end)
        end
    end

    A.moveBeat = A.moveBeat + 1
    if A.moveBeat < A.beatsPerMove then return end
    A.moveBeat = 0

    A.moveIdx = A.moveIdx % #A.moves + 1
    local move = A.moves[A.moveIdx]

    for zombie in pairs(A.active) do
        pcall(function() zombie:setVariable("ThrillerMove", move) end)
    end
    dMsg("move rotate ->", move)
end

-- 清场: 全员收舞+状态复位(主MOD cleanStat/release时调用)
function A.release(mt)
    local active = A.active
    A.active = {}
    for zombie in pairs(active) do
        pcall(function()
            zombie:setVariable("bThrillerDance", false)
            zombie:setUseless(false)
        end)
    end
    A.moveIdx = 1
    A.moveBeat = 0
    dMsg("released")
end
