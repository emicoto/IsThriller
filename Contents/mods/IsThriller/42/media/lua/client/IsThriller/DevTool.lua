-- ClaudeNote: IsThriller Admin测试面板 (DevTool v0.1)
-- 定位: admin工具, 不依赖游戏-debug模式。单机随开; 联机仅管理员(accessLevel=="admin")可用
-- 交互: 唯一快捷键 Home 开关面板; 其余操作全是面板按钮, 面板关着时瞎按键盘不会触发任何调试功能
-- 放置: Contents/mods/IsThriller/42/media/lua/client/IsThriller/Dev.lua

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"

-- ClaudeNote: v0.2修订 — ①面板文字全部改英文(PZ不按UTF-8渲染lua源内中文字符串, 之前全乱码)
-- ②热键经PZAPI.ModOptions注册为可改键项(默认Home), 与其他绑定冲突时可在设置里自行改键
local DEFAULT_KEY = Keyboard.KEY_HOME

local ModOpts
if PZAPI and PZAPI.ModOptions then
    ModOpts = PZAPI.ModOptions:create("IsThrillerDev", "IsThriller Admin Panel")
    ModOpts:addKeyBind("open_panel", "Open Admin Panel", DEFAULT_KEY)
    -- ClaudeNote: 日志开关入驻ModOptions(拍板); 面板上的Toggle Log仍可临时翻转本次会话
    ModOpts:addTickBox("debug_log", "Enable Debug Log", false, "Print IsThriller debug messages to console")

    -- 设置界面点Apply时即时生效
    ModOpts.apply = function(self)
        local opt = self:getOption("debug_log")
        if opt and IsThriller then
            IsThriller.debug = opt:getValue() and true or false
        end
    end
end

-- ClaudeNote: 进游戏时按ModOptions同步日志开关
local function syncDebugFlag()
    if not ModOpts or not IsThriller then return end
    local opt = ModOpts:getOption("debug_log")
    if opt then
        IsThriller.debug = opt:getValue() and true or false
    end
end
Events.OnGameStart.Add(syncDebugFlag)

local function getToggleKey()
    if ModOpts then
        local opt = ModOpts:getOption("open_panel")
        if opt then return opt:getValue() end
    end
    return DEFAULT_KEY
end

local PANEL_W  = 330
local INFO_H   = 300       -- 信息区高度
local BTN_H    = 24
local PAD      = 8
local REFRESH_MS = 300     -- 信息区刷新节流

IsThrillerDevPanel = ISCollapsableWindow:derive("IsThrillerDevPanel")

local instance = nil

--==================== 权限 ====================--

local function isAllowed()
    if not isClient() then return true end  -- 单机/本地不设限
    local player = getPlayer()
    if not player then return false end

    local lvl = ""
    if player.getAccessLevel then
        lvl = player:getAccessLevel() or ""
    elseif getAccessLevel then
        lvl = getAccessLevel() or ""
    end
    return string.lower(lvl) == "admin"    -- 联机: 管理员限定
end

--==================== 面板操作(全部挂按钮, 不做快捷键) ====================--

local Ops = {}

-- 强制触发: 绕过冷却/概率/包围判定, 按当前模式直接开场
function Ops.force()
    local st = IsThriller
    local player = getPlayer()
    if not player or not st:isIdle() then return end

    if st:isMJtime() then
        pcall(st.stage.doStart, st, player)
    else
        pcall(st.pbuff.doStart, st, player)
    end
end

-- 跳到下一段: luring->playing / playing->fading / fading->finish
function Ops.skipSection()
    local st = IsThriller
    local player = getPlayer()
    if not player then return end

    if st:isLuring() then
        -- doStage实装(Phase2)后优先走正规流程, 否则用最小等效: 切状态+开唱
        if st.stage.doStage then
            pcall(st.stage.doStage, st, player)
        else
            st.state = "playing"
            pcall(st.music.start, player)
        end
    elseif st:isPlaying() then
        pcall(st.stage.doFinal, st, player)
    elseif st:isFading() then
        pcall(st.stage.finish, st, player)
    end
end

-- 跳过当前曲/幕间: 正在幕间则立即开下一首; 正在播歌则立刻停声(等效自然播完)
function Ops.skipSong()
    local st = IsThriller
    local player = getPlayer()
    if not player then return end
    local mu = st.music

    if (mu.gapStart or -1) >= 0 then
        mu.gapStart = 0     -- countMin(0)必然超过幕间阈值, 下个检查周期直接开下一首
        return
    end

    if mu.handle then
        local emitter = player:getEmitter()
        if emitter then
            pcall(function() emitter:stopSound(mu.handle) end)
            -- 不清handle: isPlaying=false后由Music.onTick按"自然播完"的正常路径结算
        end
    end
end

-- 硬停: 强制清场, 不记冷却
function Ops.hardStop()
    local st = IsThriller
    pcall(st.stage.hardStop, st, getPlayer())
end

-- 全量状态输出到控制台
function Ops.dump()
    pcall(IsThriller.util.dump)
end

-- 日志开关: 切IsThriller.debug(debugMsg门闩)
function Ops.toggleLog()
    IsThriller.debug = not IsThriller.debug
end

--==================== 信息区 ====================--

local function fmt(v)
    if type(v) == "number" then
        if v == math.floor(v) then return tostring(v) end
        return string.format("%.2f", v)
    end
    return tostring(v)
end

local function buildLines()
    local st = IsThriller
    local util = st.util
    local conf = st.config
    local md = util.getModData()
    local mu, ac = st.music, st.actor
    local lines = {}

    local function add(s) table.insert(lines, s) end

    add(("mode=%s  state=%s  log=%s"):format(st.mode, st.state, st.debug and "ON" or "off"))
    add(("song=%s  played=%s/%s  encored=%s"):format(fmt(mu.current), fmt(mu.played), fmt(util.getSV("MaxWave")), tostring(mu.encored)))
    add(("phase=%s  beat=%s"):format(fmt(st.phase), fmt(st.beat)))

    -- 幕间倒计时
    if (mu.gapStart or -1) >= 0 then
        local remain = util.toGameTime(conf.music.gapRealSec) - util.countMin(mu.gapStart)
        add(("GAP: %s game-min left"):format(fmt(math.max(0, remain))))
    else
        add("GAP: -")
    end

    -- 尾声倒计时
    if st:isFading() then
        local remain = conf.get("finalCountDown") - util.countMin(md.fadeStart or 0)
        add(("FADE: %s game-min left"):format(fmt(math.max(0, remain))))
    else
        add("FADE: -")
    end

    -- 冷却
    local cdLeft = (md.cooldown or -1) - util.getHour()
    add(("cooldown: %s h left"):format((md.cooldown or -1) > 0 and cdLeft > 0 and fmt(cdLeft) or "-"))

    -- 演员
    -- ClaudeNote: 对象池修复 — 显示读死亡账本(mjDead/dancerTotal), 不再信旧引用的isDead
    local mjState = ac.mjDead and "DEAD" or (ac.mj and "alive" or "-")
    add(("MJ=%s hit=%s  hp=%s  dancers=%s/%s  all=%s  grudge=%s"):format(mjState, tostring(ac.mjEverHit), fmt(ac.mjHP), fmt(ac:dancerCount()), fmt(ac.dancerTotal or 0), fmt(ac:allDancerNum()), fmt(ac.grudge or -1)))

    -- 扫描报告
    local player = getPlayer()
    local rp = player and st.report[util.getPID(player)]
    if rp then
        add(("scan: near=%s range=%s safe=%s tgt=%s total=%s"):format(fmt(rp.nearCount), fmt(rp.rangeCount), fmt(rp.safeCount), fmt(rp.targeting), fmt(rp.total)))
    else
        add("scan: no report yet")
    end

    -- 玩家
    if player then
        local pd = util.getData(player)
        add(("lastHit=%s  lastStage=%s  nowMin=%s"):format(fmt(pd.lastHit or -1), fmt(md.lastStage or 0), fmt(util.getMin())))
    end

    return lines
end

--==================== 面板本体 ====================--

function IsThrillerDevPanel:createChildren()
    ISCollapsableWindow.createChildren(self)

    -- ClaudeNote: 标签用英文 — lua源内中文字符串在PZ的UI渲染下是乱码
    local btns = {
        { text = "Force Start",   fn = Ops.force },
        { text = "Skip Section",  fn = Ops.skipSection },
        { text = "Skip Song/Gap", fn = Ops.skipSong },
        { text = "Hard Stop",     fn = Ops.hardStop },
        { text = "Dump Console",  fn = Ops.dump },
        { text = "Toggle Log",    fn = Ops.toggleLog },
    }

    local colW = (PANEL_W - PAD * 3) / 2
    local y0 = self:titleBarHeight() + INFO_H

    for i, def in ipairs(btns) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local btn = ISButton:new(
            PAD + col * (colW + PAD),
            y0 + row * (BTN_H + PAD),
            colW, BTN_H, def.text, self,
            function() def.fn() end)
        btn:initialise()
        self:addChild(btn)
    end
end

function IsThrillerDevPanel:prerender()
    ISCollapsableWindow.prerender(self)

    local now = getTimestampMs()
    if not self.nextRefresh or now >= self.nextRefresh then
        self.nextRefresh = now + REFRESH_MS
        local ok, lines = pcall(buildLines)
        self.lines = ok and lines or { "buildLines error: " .. tostring(lines) }
    end

    local y = self:titleBarHeight() + 6
    for _, line in ipairs(self.lines or {}) do
        self:drawText(line, PAD, y, 0.9, 0.9, 0.7, 1, UIFont.Small)
        y = y + 18
    end
end

--==================== 开关与热键 ====================--

local function togglePanel()
    if instance and instance:getIsVisible() then
        instance:setVisible(false)
        instance:removeFromUIManager()
        return
    end

    if not instance then
        local rows = 3
        local h = 16 + INFO_H + rows * (BTN_H + PAD) + PAD
        instance = IsThrillerDevPanel:new(120, 120, PANEL_W, h)
        instance:initialise()
        instance.title = "IsThriller Admin"
        instance.pin = true
    end

    instance:setVisible(true)
    instance:addToUIManager()
end

-- 唯一快捷键: 默认Home, 可在Mod Options里改键 (面板不在时按其他任何键都不会触发调试功能)
local function onKeyPressed(keynum)
    if keynum ~= getToggleKey() then return end
    if not getPlayer() then return end
    if not isAllowed() then return end
    togglePanel()
end

Events.OnKeyPressed.Add(onKeyPressed)
