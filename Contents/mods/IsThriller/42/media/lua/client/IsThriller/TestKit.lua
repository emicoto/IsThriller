-- ClaudeNote: IsThriller游戏内测试工具包(ITK) v0.1 — 控制台调用, 用于实测演员实例/坐标/寻路/舞蹈变量。
-- 放置: 42/media/lua/client/IsThriller/ (临时调试文件, 测完即撤, 不随发布)
-- 用法: 游戏内Lua控制台直接敲 ITK.help() 看指令清单。输出全英文(PZ控制台中文乱码)。
-- 依赖: 主MOD已加载(IsThriller全局); 寻路API依据《Claude的丧尸移动控制与pathToLocationF反编译报告》。

ITK = ITK or {}

local function say(...)
    print("[ITK]", ...)
end


function ITK.checkTicks()

    if ITK.gameTick == nil then
        ITK.gameTick = 0
    end
    if ITK.lastMs == nil then
        ITK.lastMs = getTimestampMs()
    end

    local elapse = getTimestampMs() - ITK.lastMs

    if ITK.gameTick > 60 then
        print("LuneModDebug: checkTicks ", ITK.gameTick, "elapse", elapse)
    end

    if elapse > 1000 then
        print("LuneModDebug: ", elapse," ms per ", ITK.gameTick," tick")
        ITK.gameTick = 0
        ITK.lastMs = getTimestampMs()
    end

    ITK.gameTick = ITK.gameTick + 1

end

-- Events.OnTick.Add(ITK.checkTicks)

local function fpos(o)
    if not o then return "nil" end
    local ok, s = pcall(function()
        return string.format("%.2f, %.2f, %.0f", o:getX(), o:getY(), o:getZ())
    end)
    return ok and s or "posErr"
end

local function fdist(a, b)
    if not a or not b then return -1 end
    local ok, d = pcall(function() return a:DistTo(b) end)
    return ok and tonumber(string.format("%.2f", d)) or -1
end

-- 演员遍历: 返回 {label, zombie} 数组 (MJ + 存活伴舞)
local function actors()
    local list = {}
    
    local cell = getPlayer() and getPlayer():getCell()
    if not cell then return list end


    local zblist = cell:getZombieList()
    if not zblist or zblist:size() == 0 then return list end

    local time = getTimestampMs()

    list.dancer = {}
    list.audience = {}
    list.all = {}

    for i = 0, zblist:size() -1 do
        local zb = zblist:get(i)
        if zb then
            if not zb:isDead() then
                if zb:getModData().isThrillerMJ then
                    table.insert(list.all, { "MJ", zb })
                    list.mj = zb
                end
                if zb:getModData().isThrillerDancer then
                    table.insert(list.all, { "DC", zb})
                    table.insert(list.dancer, zb)
                end
                if zb:getModData().isThrillerAudience then
                    table.insert(list.all, {"AD", zb})
                    table.insert(list.audience, zb)
                end
            else
                if zb:getModData().isThrillerMJ then
                    list.mj = nil
                    list.mjDead = true
                end
            end
        end
    end
    
    print("[LuneModDebug] <IsThriller> - time elapse on scan cell zombies:", getTimestampMs() - time)

    return list
end

--==================== 实例与坐标 ====================--

-- 玩家实例(顺带打印坐标)
function ITK.p()
    local pl = getPlayer()
    say("player:", tostring(pl), "pos:", fpos(pl))
    return pl
end

-- MJ实例
function ITK.mj()
    local ac = actors()
    if not ac or not ac.mj then say("MJ = nil, mjDead=", ac and tostring(ac.mjDead)) return nil end
    local z = ac.mj
    say("MJ:", tostring(z), "dead=", tostring(z:isDead()), "hp=", tostring(z:getHealth()))
    say("  pos:", fpos(z), " distToPlayer=", fdist(z, getPlayer()))
    return z
end

-- 伴舞列表(索引取单个: ITK.dc(2))
function ITK.dc(i)
    local ac = actors()
    if not ac then return nil end
    if i then
        local z = ac.dancer[i]
        say("DC" .. i .. ":", tostring(z), z and ("pos: " .. fpos(z)) or "")
        return z
    end
    local mj, pl = ac.mj, getPlayer()
    for idx, z in ipairs(ac.dancer or {}) do
        say(string.format("DC%d dead=%s pos=[%s] dMJ=%s dPl=%s",
            idx, tostring(z:isDead()), fpos(z), tostring(fdist(z, mj)), tostring(fdist(z, pl))))
    end
    say("total dancers:", #(ac.dancer or {}), " roster:", tostring(IsThriller.actor.dancerTotal))
    return ac.dancer
end

-- 任意对象坐标
function ITK.pos(o)
    say("pos:", fpos(o))
    return o and o:getX(), o and o:getY(), o and o:getZ()
end

-- ClaudeNote: 距离语义排查升级 — 一次打印四种口径:
-- DistTo(api)=引擎原样 / euclid=手算直线 / grid(cheby)=建造那种"格数"(斜向1格算1格) / manhattan / dz=楼层差
-- DistTo是2D欧氏直线且无视z, 与"square格数"斜向时必然不等(5格斜角: grid=5, DistTo=7.07)
function ITK.dist(a, b)
    b = b or getPlayer()
    if not a or not b then say("dist: nil") return end
    local dx = math.abs(a:getX() - b:getX())
    local dy = math.abs(a:getY() - b:getY())
    local dz = math.abs(a:getZ() - b:getZ())
    local api = fdist(a, b)
    say(string.format("DistTo(api)=%.2f  euclid=%.2f  grid(cheby)=%d  manhattan=%.1f  dz=%d",
        api, math.sqrt(dx * dx + dy * dy), math.floor(math.max(dx, dy)), dx + dy, math.floor(dz)))
    say(string.format("  dx=%.2f dy=%.2f  A=[%s]  B=[%s]", dx, dy, fpos(a), fpos(b)))
    return api
end

-- ClaudeNote: 距离校准 — 瞬移丧尸到玩家正东n格(格心对齐), DistTo应精确读n;
-- ITK.calib(z, n, true)改斜向45度: DistTo应读n*1.414, 若你要的是建造语义那它"该"读n
function ITK.calib(z, n, diagonal)
    local pl = getPlayer()
    if not z or not pl then say("calib: need zombie") return end
    n = n or 5
    local x = math.floor(pl:getX()) + n + 0.5
    local y = diagonal and (math.floor(pl:getY()) + n + 0.5) or (math.floor(pl:getY()) + 0.5)
    local ok = pcall(function() z:teleportTo(x, y, pl:getZ()) end)
    say("calib tp", ok and "OK" or "FAIL", diagonal and ("diag " .. n) or ("east " .. n),
        string.format(" expect: straight=%d diag-euclid=%.2f diag-grid=%d", n, n * 1.41421, n))
    ITK.dist(z, pl)
end

--==================== 移动控制 ====================--

-- 瞬移 ITK.tp(z, x, y, zl)
function ITK.tp(z, x, y, zl)
    if not z then say("tp: nil target") return end
    local ok, err = pcall(function() z:teleportTo(x, y, zl or 0) end)
    say("tp ->", x, y, zl or 0, ok and "OK" or ("FAIL " .. tostring(err)))
end

-- float寻路 ITK.pathF(z, x, y, zl)
function ITK.pathF(z, x, y, zl)
    if not z then say("pathF: nil target") return end
    local ok, err = pcall(function() z:pathToLocationF(x, y, zl or 0) end)
    say("pathF ->", x, y, zl or 0, ok and "OK" or ("FAIL " .. tostring(err)))
end

-- 寻路到角色 ITK.pathTo(z, chr) chr缺省=玩家
function ITK.pathTo(z, chr)
    if not z then say("pathTo: nil target") return end
    chr = chr or getPlayer()
    local ok, err = pcall(function() z:pathToCharacter(chr) end)
    say("pathTo ->", tostring(chr), ok and "OK" or ("FAIL " .. tostring(err)))
end

-- 声音寻路(最像丧尸) ITK.sound(z, x, y)
function ITK.sound(z, x, y)
    if not z then say("sound: nil target") return end
    local ok, err = pcall(function() z:pathToSound(math.floor(x), math.floor(y), 0) end)
    say("pathToSound ->", x, y, ok and "OK" or ("FAIL " .. tostring(err)))
end

-- 追踪目标 ITK.target(z, chr) / 解除 ITK.target(z, false)
function ITK.target(z, chr)
    if not z then say("target: nil target") return end
    local tgt = chr
    if chr == nil then tgt = getPlayer() end
    if chr == false then tgt = nil end
    local ok, err = pcall(function() z:setTarget(tgt) end)
    say("setTarget ->", tostring(tgt), ok and "OK" or ("FAIL " .. tostring(err)))
end

-- 寻路状态查询
function ITK.path(z)
    if not z then say("path: nil target") return end
    local function q(name)
        local ok, v = pcall(function() return z[name](z) end)
        return ok and tostring(v) or "n/a"
    end
    say("hasPath=", q("hasPath"), " isPathing=", q("isPathing"), " isMoving=", q("isMoving"))
    local ok, tx = pcall(function() return z:getPathTargetX() end)
    if ok then
        local _, ty = pcall(function() return z:getPathTargetY() end)
        say("pathTarget:", tostring(tx), tostring(ty))
    end
    say("bPathfind=", tostring(ITK.getVar(z, "bPathfind", true)))
end

-- 全体伴舞 -> MJ坐标汇合
function ITK.rally()
    local ac = actors()
    if not ac or not ac.mj then say("rally: no MJ") return end
    local mj = ac.mj
    for i, z in ipairs(ac.dancer or {}) do
        if not z:isDead() then
            local ox = (ZombRand(5) - 2) * 0.6   -- 小偏移防叠格
            local oy = (ZombRand(5) - 2) * 0.6
            pcall(function() z:pathToLocationF(mj:getX() + ox, mj:getY() + oy, mj:getZ()) end)
            say("rally DC" .. i, "-> MJ")
        end
    end
end

-- MJ->玩家, 伴舞->MJ, 编队行进
function ITK.march()
    local ac = actors()
    local pl = getPlayer()
    if not ac or not ac.mj or not pl then say("march: missing MJ/player") return end
    pcall(function() ac.mj:pathToCharacter(pl) end)
    say("march: MJ -> player")
    ITK.rally()
end

--==================== 舞蹈与动画变量 ====================--

-- 起舞/收舞: ITK.dance(z, true, "BobTA_Thriller_One") / ITK.dance("all", false)
function ITK.dance(z, on, move)
    move = move or "BobTA_Thriller_One"
    local targets = {}
    if z == "all" then
        for _, e in ipairs(actors()) do table.insert(targets, e) end
    else
        table.insert(targets, { "one", z })
    end
    for _, e in ipairs(targets) do
        local label, zb = e[1], e[2]
        if zb and not zb:isDead() then
            if IsThrillerTAD and IsThrillerTAD.setDance then
                pcall(IsThrillerTAD.setDance, zb, on, move)
                say("dance(TAD)", label, tostring(on), move)
            else
                -- TAD接口不在时直接写变量兜底
                pcall(function()
                    zb:setUseless(on and true or false)
                    zb:setVariable("ThrillerMove", move)
                    zb:setVariable("bThrillerDance", on and true or false)
                end)
                say("dance(raw)", label, tostring(on), move)
            end
        end
    end
end

-- 单独改舞步变量(不动useless): 测moonwalk/引擎自动切换用
function ITK.move(z, move)
    if not z or not move then say("usage: ITK.move(zombie, moveName)") return end
    local ok, err = pcall(function() z:setVariable("ThrillerMove", move) end)
    say("setVariable ThrillerMove =", move, ok and "OK" or ("FAIL " .. tostring(err)))
end

-- 读动画变量: ITK.getVar(z, "ThrillerMove") ; silent=true时只返回不打印
function ITK.getVar(z, name, silent)
    if not z then return nil end
    local ok, v = pcall(function() return z:getVariableString(name) end)
    if not ok then
        ok, v = pcall(function() return z:getVariableBoolean(name) end)
    end
    local out = ok and tostring(v) or "n/a"
    if not silent then say("var", name, "=", out) end
    return out
end

-- 一口气打印关键变量
function ITK.vars(z)
    if not z then say("vars: nil target") return end
    for _, n in ipairs({ "bThrillerDance", "ThrillerMove", "bPathfind", "zombieWalkType" }) do
        ITK.getVar(z, n)
    end
    local ok, u = pcall(function() return z:isUseless() end)
    say("isUseless =", ok and tostring(u) or "n/a")
end

-- 任意setVariable: ITK.setVar(z, "k", v)
function ITK.setVar(z, k, v)
    if not z then say("setVar: nil target") return end
    local ok, err = pcall(function() z:setVariable(k, v) end)
    say("setVariable", k, "=", tostring(v), ok and "OK" or ("FAIL " .. tostring(err)))
end

--==================== 侦察 ====================--

-- 玩家r格内丧尸清单(带标签): ITK.near(10)
function ITK.near(r)
    r = r or 10
    local pl = getPlayer()
    if not pl then return end
    local cell = pl:getCell()
    local zl = cell and cell:getZombieList()
    if not zl then say("no zombie list") return end
    local n = 0
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and fdist(z, pl) <= r then
            n = n + 1
            local md = z:getModData()
            local tag = (md.isThrillerMJ and "MJ") or (md.isThrillerDancer and "DANCER")
                or (md.isThrillerAudience and "AUDIENCE") or "-"
            say(string.format("#%d tag=%s d=%.1f pos=[%s] dance=%s",
                n, tag, fdist(z, pl), fpos(z), ITK.getVar(z, "bThrillerDance", true)))
        end
    end
    say("total in range:", n)
end

-- 查标签
function ITK.tags(z)
    if not z then say("tags: nil target") return end
    local md = z:getModData()
    say("MJ=", tostring(md.isThrillerMJ), " DANCER=", tostring(md.isThrillerDancer),
        " AUDIENCE=", tostring(md.isThrillerAudience))
end

--==================== 持续观测 ====================--

local watchTick = 0
local watchEvery = 60   -- ~1秒

-- 必须具名, 才能Remove(Kahlua匿名函数无法移除)
local function watchLoop()
    watchTick = watchTick + 1
    if watchTick < watchEvery then return end
    watchTick = 0

    local pl = getPlayer()
    local ac = actors()
    if not pl or not ac then return end
    local mj = ac.mj

    local line = "W| "
    if mj then
        line = line .. string.format("MJ[%s] dPl=%.1f path=%s dance=%s | ",
            fpos(mj), fdist(mj, pl),
            tostring(select(2, pcall(function() return mj:isPathing() end))),
            ITK.getVar(mj, "bThrillerDance", true))
    else
        line = line .. "MJ=nil | "
    end
    for i, z in ipairs(ac.dancer or {}) do
        local md = ac.dancer:getModData()
        line = line .. tostring(md.dancerID)..string.format("DC%d dMJ=%s dPl=%.1f dance=%s | ",
            i, tostring(fdist(z, mj)), fdist(z, pl), ITK.getVar(z, "bThrillerDance", true))
    end
    print("[ITK]" .. line)
end

-- 开关观测: ITK.watch(true) / ITK.watch(false) / ITK.watch(true, 2) 每2秒
function ITK.watch(on, sec)
    Events.OnTick.Remove(watchLoop)
    if on then
        watchEvery = math.floor((sec or 1) * 60)
        watchTick = 0
        Events.OnTick.Add(watchLoop)
        say("watch ON, every", (sec or 1), "sec")
    else
        say("watch OFF")
    end
end

--==================== 生成与流程 ====================--

-- 强制生成: ITK.spawn("mj") / ITK.spawn("dc")
function ITK.spawn(what)
    local st = IsThriller
    local pl = getPlayer()
    if not st or not pl then return end
    if what == "mj" then
        pcall(st.actor.mjStandby, pl)
        say("spawn mj -> ", tostring(st.actor.mj))
    elseif what == "dc" then
        pcall(st.actor.dancerStandby, pl)
        say("spawn dancers -> ", st.actor:dancerCount(), " all -> ", st.actor:allDancerNum())
    else
        say("usage: ITK.spawn('mj') or ITK.spawn('dc')")
    end
end

-- 主MOD全量状态
function ITK.dump()
    pcall(IsThriller.util.dump)
end

function ITK.help()
    say("-- instance: p() mj() dc(i?) pos(o) dist(a,b?)")
    say("-- move: tp(z,x,y,z) pathF(z,x,y,z) pathTo(z,chr?) sound(z,x,y) target(z,chr|false) path(z)")
    say("-- group: rally() march()")
    say("-- dance: dance(z|'all',on,move?) move(z,move) vars(z) getVar(z,n) setVar(z,k,v)")
    say("-- scout: near(r?) tags(z) watch(on,sec?) spawn('mj'|'dc') dump()")
end

say("TestKit loaded. ITK.help() for commands.")
