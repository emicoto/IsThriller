-- GPTNote: IsThriller DevTool v1.1 keeps the full TestKit in a compact 420x560 paged panel with wrapped text and a two-line auto-width summary mode.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"

local DEFAULT_KEY = Keyboard.KEY_HOME
local PANEL_W = 420
local PANEL_H = 560
local COMPACT_MIN_H = 82
local PAD = 8
local REFRESH_MS = 500
local ROW_H = 22
local SUMMARY_LINE_GAP = 3
local DEFAULT_OPACITY = 80

local ModOpts
local instance

local function getPanelOpacity()
    if ModOpts then
        local option = ModOpts:getOption("panel_opacity")
        if option then return math.max(20, math.min(100, tonumber(option:getValue()) or DEFAULT_OPACITY)) / 100 end
    end
    return DEFAULT_OPACITY / 100
end

if PZAPI and PZAPI.ModOptions then
    ModOpts = PZAPI.ModOptions:create("IsThrillerDev", "IsThriller Admin Panel")
    ModOpts:addKeyBind("open_panel", "Open Admin Panel", DEFAULT_KEY)
    ModOpts:addTickBox("debug_log", "Enable Debug Log", false, "Print IsThriller debug messages to console")
    ModOpts:addSlider("panel_opacity", "Panel Opacity (%)", 20, 100, 5, DEFAULT_OPACITY, "Transparency of the DevTool panel")
    ModOpts.apply = function(self)
        local option = self:getOption("debug_log")
        if option and IsThriller then IsThriller.debug = option:getValue() and true or false end
        if instance and instance.applyOpacity then instance:applyOpacity() end
    end
end

local function syncModOptions()
    if ModOpts and IsThriller then
        local option = ModOpts:getOption("debug_log")
        if option then IsThriller.debug = option:getValue() and true or false end
    end
    if instance and instance.applyOpacity then instance:applyOpacity() end
end
Events.OnGameStart.Add(syncModOptions)

local function getToggleKey()
    if ModOpts then
        local option = ModOpts:getOption("open_panel")
        if option then return option:getValue() end
    end
    return DEFAULT_KEY
end

local function isAllowed()
    if not isClient() then return true end
    local player = getPlayer()
    if not player then return false end
    local level = ""
    if player.getAccessLevel then
        level = player:getAccessLevel() or ""
    elseif getAccessLevel then
        level = getAccessLevel() or ""
    end
    return string.lower(level) == "admin"
end

local function fmt(value)
    if value == nil then return "-" end
    if type(value) == "number" then
        if value == math.floor(value) then return tostring(value) end
        return string.format("%.2f", value)
    end
    return tostring(value)
end

local function safe(object, method, fallback)
    if not object then return fallback end
    local ok, value = pcall(function()
        local fn = object[method]
        if not fn then return fallback end
        return fn(object)
    end)
    if ok then return value end
    return fallback
end

local function tableCount(source)
    local count = 0
    for _ in pairs(source or {}) do count = count + 1 end
    return count
end

local function sortedAliveIDs(source)
    local ids = {}
    for id, zombie in pairs(source or {}) do
        if zombie and not safe(zombie, "isDead", true) then table.insert(ids, id) end
    end
    table.sort(ids, function(a, b)
        if type(a) == "number" and type(b) == "number" then return a < b end
        return tostring(a) < tostring(b)
    end)
    local display = {}
    for _, id in ipairs(ids) do table.insert(display, tostring(id)) end
    return ids, display
end

local function boolText(value)
    return value and "YES" or "no"
end

local Ops = {}

function Ops.force()
    local state = IsThriller
    local player = getPlayer()
    if not state or not player then return "missing mod/player" end
    if state.isIdle and not state:isIdle() then return "ignored: stage is not idle" end
    if state:isMJtime() then
        state.stage.doStart(state, player)
        return "forced MJ stage start"
    end
    state.pbuff.doStart(state, player)
    return "forced player-buff start"
end

function Ops.skipSection()
    local state = IsThriller
    local player = getPlayer()
    if not state or not player then return "missing mod/player" end
    if state:isLuring() then
        state.stage.doStage(state, player)
        return "luring -> playing"
    elseif state:isPlaying() then
        state.stage.doFinal(state, player)
        return "playing -> fading"
    elseif state:isFading() then
        state.stage.finish(state, player)
        return "fading -> finish"
    end
    return "ignored: no active section"
end

function Ops.skipSong()
    local state = IsThriller
    local player = getPlayer()
    if not state or not player then return "missing mod/player" end
    local music = state.music
    if (music.gapStart or -1) >= 0 then
        music.gapStart = 0
        return "gap marked complete"
    end
    if music.handle then
        local emitter = player:getEmitter()
        if emitter then emitter:stopSound(music.handle) return "current song stopped" end
    end
    return "ignored: no song/gap"
end

function Ops.hardStop()
    IsThriller.stage.hardStop(IsThriller, getPlayer())
    return "hard stop complete"
end

function Ops.toggleLog()
    IsThriller.debug = not IsThriller.debug
    return "debug log " .. (IsThriller.debug and "ON" or "OFF")
end

function Ops.dump()
    IsThriller.util.dump()
    return "mod state dumped to console"
end

local function requireITK()
    if not ITK then error("TestKit backend (ITK) is not loaded") end
    return ITK
end

local function selectDancerAction(id)
    return function() return requireITK().dancerByID(id) end
end

local function makeAction(id, title, fn, tooltip)
    return { kind = "action", id = id, title = title, run = fn, tooltip = tooltip }
end

local function buildSections()
    local sections = {
        {
            id = "stage", title = "Stage Control", actions = {
                makeAction("force", "Force Start", Ops.force),
                makeAction("skip_section", "Skip Section", Ops.skipSection),
                makeAction("skip_song", "Skip Song / Gap", Ops.skipSong),
                makeAction("hard_stop", "Hard Stop", Ops.hardStop),
            }
        },
        {
            id = "actors", title = "Actor Registry", actions = {
                makeAction("select_mj", "Select MJ Instance", function() return requireITK().mj() end),
                makeAction("fixed_ids", "Print Fixed Dancer IDs", function() return requireITK().dancerIDs() end),
                makeAction("all_ids", "Print All Dancer IDs", function() return requireITK().allDancerIDs() end),
            }
        },
        {
            id = "inspect", title = "Selected: Inspect", actions = {
                makeAction("pos", "Print Position", function() return requireITK().pos() end),
                makeAction("distance", "Print Distance Metrics", function() return requireITK().dist() end),
                makeAction("tags", "Print Tags / Absolute ID", function() return requireITK().tags() end),
                makeAction("vars", "Print Animation Variables", function() return requireITK().vars() end),
                makeAction("path", "Print Path State", function() return requireITK().path() end),
            }
        },
        {
            id = "movement", title = "Selected: Movement", actions = {
                makeAction("path_player", "Path To Player", function() return requireITK().pathTo() end),
                makeAction("sound_player", "Path To Player Sound", function() return requireITK().sound() end),
                makeAction("target_player", "Set Target = Player", function() return requireITK().target() end),
                makeAction("clear_target", "Clear Target", function() return requireITK().target(nil, false) end),
                makeAction("tp_player", "Teleport Beside Player", function() return requireITK().tpNearPlayer() end),
                makeAction("calib_east", "Calibrate 5 Tiles East", function() return requireITK().calib(nil, 5, false) end),
                makeAction("calib_diag", "Calibrate 5 Tiles Diagonal", function() return requireITK().calib(nil, 5, true) end),
            }
        },
        {
            id = "animation", title = "Selected: Animation", actions = {
                makeAction("dance", "Stationary Dance", function() return requireITK().dance(nil, true) end),
                makeAction("walk", "Walk Dance + Path", function()
                    requireITK().dance(nil, true, "walk")
                    return requireITK().pathTo()
                end),
                makeAction("spin", "One-Shot Spin", function() return requireITK().spin() end),
                makeAction("stop_dance", "Stop Dance", function() return requireITK().dance(nil, false) end),
                makeAction("dance_all", "Stationary Dance: All", function() return requireITK().dance("all", true) end),
                makeAction("walk_all", "Walk Dance: All", function() return requireITK().dance("all", true, "walk") end),
                makeAction("stop_all", "Stop Dance: All", function() return requireITK().dance("all", false) end),
            }
        },
        {
            id = "group", title = "Group / Spawn / Scout", actions = {
                makeAction("rally", "Rally Fixed Dancers To MJ", function() return requireITK().rally() end),
                makeAction("march", "March Group To Player", function() return requireITK().march() end),
                makeAction("spawn_mj", "Spawn / Standby MJ", function() return requireITK().spawn("mj") end),
                makeAction("spawn_dc", "Spawn / Standby Dancers", function() return requireITK().spawn("dc") end),
                makeAction("near", "Scan Zombies Within 10", function() return requireITK().near(10) end),
                makeAction("watch", "Toggle Console Watch", function()
                    local itk = requireITK()
                    return itk.watch(not itk.watching, 1)
                end),
            }
        },
        {
            id = "debug", title = "Logging", actions = {
                makeAction("dump", "Dump Mod State", Ops.dump),
                makeAction("toggle_log", "Toggle Debug Log", Ops.toggleLog),
            }
        },
    }

    local actorSection = sections[2]
    local rows = ITK and ITK.dancerRows and ITK.dancerRows() or {}
    for _, row in ipairs(rows) do
        table.insert(actorSection.actions, makeAction(
            "dancer_" .. tostring(row.id),
            "Dancer [" .. tostring(row.id) .. "]",
            selectDancerAction(row.id),
            "Select exact IsoZombie instance by absolute ID"
        ))
    end
    return sections
end

IsThrillerDevPanel = ISCollapsableWindow:derive("IsThrillerDevPanel")

-- GPTNote: Pixel-based wrapping keeps long state values readable inside the compact single-column layout.
local function splitLongWord(word, maxWidth, font)
    local pieces = {}
    local current = ""
    for i = 1, #word do
        local char = word:sub(i, i)
        local candidate = current .. char
        if current ~= "" and getTextManager():MeasureStringX(font, candidate) > maxWidth then
            table.insert(pieces, current)
            current = char
        else
            current = candidate
        end
    end
    if current ~= "" then table.insert(pieces, current) end
    return pieces
end

local function wrapText(text, maxWidth, font)
    local lines = {}
    for paragraph in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local current = ""
        for word in paragraph:gmatch("%S+") do
            local candidate = current == "" and word or (current .. " " .. word)
            if getTextManager():MeasureStringX(font, candidate) <= maxWidth then
                current = candidate
            else
                if current ~= "" then table.insert(lines, current) end
                if getTextManager():MeasureStringX(font, word) <= maxWidth then
                    current = word
                else
                    local pieces = splitLongWord(word, maxWidth, font)
                    current = ""
                    for i, piece in ipairs(pieces) do
                        if i < #pieces then table.insert(lines, piece) else current = piece end
                    end
                end
            end
        end
        if current ~= "" then table.insert(lines, current) end
        if paragraph == "" then table.insert(lines, "") end
    end
    if #lines == 0 then table.insert(lines, "") end
    return lines
end

local function summaryTexts()
    local state = IsThriller
    if not state or not state.util then
        return "near - / range - / safe - / tar - / total -",
            'state "nil" / music nil / MJ nil not-hit / dancers 0 / all 0 / song nil / songs 0/-'
    end

    local player = getPlayer()
    local report = player and state.report and state.report[state.util.getPID(player)] or nil
    local reportText = "sight"..fmt(report and report.sightCount)
        .."/ near " .. fmt(report and report.nearCount)
        .. " / tar " .. fmt(report and report.targeting)
        .. " / area " .. fmt(report and report.areaCount)
        .. " / safe " .. fmt(report and report.safeCount)
        .. " / field " .. fmt(report and report.rangeCount)
        .. " / total " .. fmt(report and report.total)

    local actor = state.actor or {}
    local music = state.music or {}
    local _, fixedIDs = sortedAliveIDs(actor.dancers)
    local _, allIDs = sortedAliveIDs(actor.allDancer)
    local mjText = actor.mj and "alive" or (actor.mjDead and "dead" or "nil")
    local stateText = 'state "' .. fmt(state.state) .. '"'
        .. " / phase "..tostring(state.phase)
        .. " / music " .. tostring(music.current)
        .. " / MJ " .. mjText .. " " .. (actor.mjEverHit and "hit" or "safe")
        .. " / dancers " .. tostring(#fixedIDs)
        .. " / all " .. tostring(#allIDs)
        .. " / song " .. fmt(music.played or 0) .. "/" .. fmt(state.util.getSV("MaxWave"))
    return reportText, stateText
end

function IsThrillerDevPanel:applyOpacity()
    local alpha = getPanelOpacity()
    self.backgroundColor.a = alpha
    if self.content then self.content.backgroundColor.a = alpha end
    if self.pagePicker then self.pagePicker.backgroundColor.a = alpha end
end

function IsThrillerDevPanel:positionTitleButtons()
    if not self.closeButton then return end
    local buttonW = self.closeButton:getWidth()
    self.closeButton:setX(self.width - buttonW - 1)
    if self.summaryButton then self.summaryButton:setX(self.width - buttonW * 2 - 2) end
end

function IsThrillerDevPanel:layoutChildren()
    if not self.content or not self.pagePicker then return end
    local lineH = getTextManager():getFontHeight(UIFont.Small)
    if self.compact then
        self.pagePicker:setVisible(false)
        self.content:setVisible(false)
        local reportText, stateText = summaryTexts()
        local compactWidth = math.max(
            PANEL_W,
            getTextManager():MeasureStringX(UIFont.Small, reportText) + PAD * 2,
            getTextManager():MeasureStringX(UIFont.Small, stateText) + PAD * 2
        )
        self:setWidth(compactWidth)
        self:setHeight(COMPACT_MIN_H)
        self.reportLines = { reportText }
        self.stateLines = { stateText }
        self:positionTitleButtons()
        return
    end

    local reportText, stateText = summaryTexts()
    self.reportLines = wrapText(reportText, self.width - PAD * 2, UIFont.Small)
    self.stateLines = wrapText(stateText, self.width - PAD * 2, UIFont.Small)
    local y = self:titleBarHeight() + PAD
    y = y + lineH + SUMMARY_LINE_GAP + (#self.reportLines * lineH) + PAD
    y = y + lineH + SUMMARY_LINE_GAP + (#self.stateLines * lineH) + PAD
    self.activePageLabelY = y
    self.pagePicker:setX(PAD)
    self.pagePicker:setY(y + lineH + SUMMARY_LINE_GAP)
    self.pagePicker:setWidth(self.width - PAD * 2)
    self.pagePicker:setHeight(ROW_H)
    local contentY = self.pagePicker:getY() + self.pagePicker:getHeight() + PAD
    self.content:setX(PAD)
    self.content:setY(contentY)
    self.content:setWidth(self.width - PAD * 2)
    self.content:setHeight(self.height - contentY - PAD)
    self.content.vscroll:setHeight(self.content.height)
    self.pagePicker:setVisible(true)
    self.content:setVisible(true)
end

function IsThrillerDevPanel:createChildren()
    ISCollapsableWindow.createChildren(self)

    -- GPTNote: Use a dedicated button for summary mode; the stock collapse button owns a separate hover-collapse state machine.
    self.closeButton.anchorLeft = false
    self.closeButton.anchorRight = true
    self.collapseButton:setVisible(false)
    self.pinButton:setVisible(false)

    local buttonW = self.closeButton:getWidth()
    self.summaryButton = ISButton:new(0, 1, buttonW, buttonW, "", self, function(target)
        target:onToggleCompact()
    end)
    self.summaryButton:initialise()
    self.summaryButton.anchorLeft = false
    self.summaryButton.anchorRight = true
    self.summaryButton.borderColor.a = 0
    self.summaryButton.backgroundColor.a = 0
    self.summaryButton.backgroundColorMouseOver.a = 0.35
    self.summaryButton:setImage(self.collapseButtonTexture)
    self.summaryButton.tooltip = "Collapse to report / stage summary"
    self:addChild(self.summaryButton)
    self:positionTitleButtons()

    self.pagePicker = ISComboBox:new(PAD, 0, self.width - PAD * 2, ROW_H, self, IsThrillerDevPanel.onPageChanged)
    self.pagePicker:initialise()
    self:addChild(self.pagePicker)

    self.content = ISScrollingListBox:new(PAD, 0, self.width - PAD * 2, 100)
    self.content:initialise()
    self.content:instantiate()
    self.content.itemheight = ROW_H
    self.content.font = UIFont.Small
    self.content.fontHgt = getTextManager():getFontHeight(UIFont.Small)
    self.content.drawBorder = true
    self.content.doDrawItem = self.drawContentItem
    self.content:setOnMouseDownFunction(self, IsThrillerDevPanel.onContentItem)
    self:addChild(self.content)

    self:rebuildPagePicker("live")
    self:layoutChildren()
    self:applyOpacity()
    self:refreshStatus(true)
end

function IsThrillerDevPanel:rosterSignature()
    local ids = {}
    if ITK and ITK.dancerRows then
        for _, row in ipairs(ITK.dancerRows()) do table.insert(ids, tostring(row.id)) end
    end
    return table.concat(ids, "|")
end

function IsThrillerDevPanel:rebuildPagePicker(preferredID)
    if not self.pagePicker then return end
    preferredID = preferredID or self.activePageID or "live"
    self.pages = buildSections()
    self.pageByID = { live = { id = "live", title = "Live Mod State" } }
    self.pagePicker.options = {}
    self.pagePicker.selected = 0
    self.pagePicker:addOptionWithData("Live Mod State", self.pageByID.live)
    for _, page in ipairs(self.pages) do
        self.pageByID[page.id] = page
        self.pagePicker:addOptionWithData(page.title, page)
    end
    self.activePageID = self.pageByID[preferredID] and preferredID or "live"
    self.pagePicker:selectData(self.pageByID[self.activePageID])
    self.lastRosterSignature = self:rosterSignature()
end

function IsThrillerDevPanel:onPageChanged(combo)
    local page = combo:getOptionData(combo.selected)
    if not page then return end
    self.activePageID = page.id
    self:rebuildContent(false)
end

function IsThrillerDevPanel:addContentRow(data)
    local prefix = data.kind == "action" and "> " or ""
    data.lines = wrapText(prefix .. tostring(data.text or data.title or ""), self.content.width - 24, UIFont.Small)
    local height = math.max(ROW_H, #data.lines * self.content.fontHgt + 8)
    local item = self.content:addItem(data.text or data.title or "", data, data.tooltip)
    item.height = height
    return height
end

function IsThrillerDevPanel:drawContentItem(y, item, alt)
    local data = item.item or {}
    if item.height <= 0 then return y + item.height end
    if data.kind == "action" and self.selected == item.index then
        self:drawSelection(0, y, self:getWidth(), item.height - 1)
    elseif data.kind == "section" then
        self:drawRect(0, y, self:getWidth(), item.height - 1, 0.65, 0.08, 0.16, 0.20)
    end

    local r, g, b = 0.88, 0.88, 0.80
    if data.kind == "section" then r, g, b = 0.45, 0.82, 0.95 end
    if data.kind == "action" then r, g, b = 0.95, 0.76, 0.35 end
    if data.kind == "warn" then r, g, b = 1.0, 0.55, 0.35 end
    local textY = y + 4
    for _, line in ipairs(data.lines or { tostring(data.text or "") }) do
        self:drawText(line, 8, textY, r, g, b, 1, UIFont.Small)
        textY = textY + self.fontHgt
    end
    return y + item.height
end

function IsThrillerDevPanel:rebuildContent(preserveScroll)
    if not self.content then return end
    local oldScroll = preserveScroll and self.content:getYScroll() or 0
    self.content:clear()
    self.content:setScrollHeight(0)
    local totalHeight = 0
    if self.activePageID == "live" then
        local ok, rows = pcall(function() return self:buildStatusRows() end)
        if not ok then rows = { { kind = "warn", text = "Status refresh error: " .. tostring(rows) } } end
        for _, row in ipairs(rows) do totalHeight = totalHeight + self:addContentRow(row) end
    else
        local page = self.pageByID and self.pageByID[self.activePageID]
        if page then
            totalHeight = totalHeight + self:addContentRow({ kind = "section", text = page.title })
            for _, action in ipairs(page.actions or {}) do totalHeight = totalHeight + self:addContentRow(action) end
            totalHeight = totalHeight + self:addContentRow({ kind = "section", text = "LAST ACTION" })
            totalHeight = totalHeight + self:addContentRow({ kind = "kv", text = self.lastAction or (ITK and ITK.lastResult) or "-" })
        end
    end
    self.content:setScrollHeight(totalHeight)
    self.content:setYScroll(oldScroll)
end

function IsThrillerDevPanel:onContentItem(item)
    if not item then return end
    if item.kind ~= "action" or not item.run then return end
    local ok, value = pcall(item.run)
    if ok then
        local text = value
        if type(value) == "table" then text = "table result; see status/console" end
        self.lastAction = item.title .. ": " .. tostring(text or "OK")
    else
        self.lastAction = item.title .. " ERROR: " .. tostring(value)
        print("[IsThriller DevTool]", self.lastAction)
    end
    self:refreshStatus(true)
end

function IsThrillerDevPanel:onToggleCompact()
    self.compact = not self.compact
    self.title = self.compact and "" or self.fullTitle
    self.summaryButton:setImage(self.compact and self.expandSummaryTexture or self.collapseButtonTexture)
    self.summaryButton.tooltip = self.compact and "Expand DevTool" or "Collapse to report / stage summary"
    if not self.compact then
        self:setWidth(PANEL_W)
        self:setHeight(PANEL_H)
        self:positionTitleButtons()
    end
    self:layoutChildren()
    self:refreshStatus(true)
end

local function statusAdd(rows, kind, text)
    table.insert(rows, { kind = kind, text = text })
end

local function statusKV(rows, key, value)
    statusAdd(rows, "kv", key .. " = " .. fmt(value))
end

local function position(object)
    if not object then return "-" end
    local ok, text = pcall(function() return string.format("%.2f, %.2f, %.0f", object:getX(), object:getY(), object:getZ()) end)
    return ok and text or "error"
end

local function distance(a, b)
    if not a or not b then return -1 end
    local ok, value = pcall(function() return a:DistTo(b) end)
    return ok and value or -1
end

function IsThrillerDevPanel:buildStatusRows()
    local rows = {}
    local state = IsThriller
    if not state then
        statusAdd(rows, "warn", "IsThriller global is unavailable")
        return rows
    end
    local util = state.util
    local config = state.config
    local music = state.music or {}
    local actor = state.actor or {}
    local modData = util.getModData()
    local player = getPlayer()

    statusAdd(rows, "section", "CORE  (auto refresh: 0.5 sec)")
    statusKV(rows, "mode / state", fmt(state.mode) .. " / " .. fmt(state.state))
    statusKV(rows, "phase / beat", fmt(state.phase) .. " / " .. fmt(state.beat))
    statusKV(rows, "debug / TAD / AuthZ", boolText(state.debug) .. " / " .. boolText(state.hasTAD) .. " / " .. boolText(state.hasAuthZ))
    statusKV(rows, "lastTick", state.lastTick)

    statusAdd(rows, "section", "TIME / FLOW")
    statusKV(rows, "world hour / minute stamp", fmt(util.getHour()) .. " / " .. fmt(util.getMin()))
    local cooldownLeft = (modData.cooldown or -1) - util.getHour()
    statusKV(rows, "cooldown left (hours)", cooldownLeft > 0 and cooldownLeft or "-")
    statusKV(rows, "lastStage / fadeStart", fmt(modData.lastStage) .. " / " .. fmt(modData.fadeStart))
    if (music.gapStart or -1) >= 0 then
        local remain = util.toGameTime(config.music.gapRealSec) - util.countMin(music.gapStart)
        statusKV(rows, "gap left (game min)", math.max(0, remain))
    else
        statusKV(rows, "gap left", "-")
    end
    if state.isFading and state:isFading() then
        statusKV(rows, "fade left (game min)", math.max(0, config.get("finalCountDown") - util.countMin(modData.fadeStart or 0)))
    end

    statusAdd(rows, "section", "MUSIC / TAD")
    statusKV(rows, "song / handle", fmt(music.current) .. " / " .. fmt(music.handle))
    statusKV(rows, "played / max / encore", fmt(music.played) .. " / " .. fmt(util.getSV("MaxWave")) .. " / " .. boolText(music.encored))
    statusKV(rows, "playlist size", music.list and #music.list or 0)
    if IsThrillerTAD then
        statusKV(rows, "move / walk index", fmt(IsThrillerTAD.moveIdx) .. " / " .. fmt(IsThrillerTAD.walkIdx))
        statusKV(rows, "current move / walk", fmt(IsThrillerTAD.currentMove and IsThrillerTAD.currentMove()) .. " / " .. fmt(IsThrillerTAD.currentwalks and IsThrillerTAD.currentwalks()))
        statusKV(rows, "active / chaser / spin", fmt(tableCount(IsThrillerTAD.active)) .. " / " .. fmt(tableCount(IsThrillerTAD.chaser)) .. " / " .. fmt(tableCount(IsThrillerTAD.spiner)))
    else
        statusAdd(rows, "warn", "TAD runtime unavailable")
    end

    statusAdd(rows, "section", "ACTOR REGISTRY")
    local mjState = actor.mjDead and "DEAD" or (actor.mj and "alive" or "-")
    statusKV(rows, "MJ / ref", mjState .. " / " .. tostring(actor.mj))
    statusKV(rows, "MJ hp base / current", fmt(actor.mjHP) .. " / " .. fmt(safe(actor.mj, "getHealth", "-")))
    statusKV(rows, "MJ hit / group", boolText(actor.mjEverHit) .. " / " .. fmt(actor.groupState))
    local _, fixedIDs = sortedAliveIDs(actor.dancers)
    local _, allIDs = sortedAliveIDs(actor.allDancer)
    statusKV(rows, "fixed alive / roster", fmt(#fixedIDs) .. " / " .. fmt(actor.dancerTotal))
    statusKV(rows, "all registered alive", #allIDs)
    statusKV(rows, "grudge / ctrlTick / healTick", fmt(actor.grudge) .. " / " .. fmt(actor.ctrlTick) .. " / " .. fmt(actor.healTick))
    statusKV(rows, "fixed absolute IDs", #fixedIDs > 0 and table.concat(fixedIDs, ", ") or "-")
    statusKV(rows, "all dancer absolute IDs", #allIDs > 0 and table.concat(allIDs, ", ") or "-")

    statusAdd(rows, "section", "SELECTED ZOMBIE")
    local zombie = ITK and ITK.getSelected and ITK.getSelected() or nil
    if zombie then
        local target = safe(zombie, "getTarget", nil)
        statusKV(rows, "label / absolute ID", fmt(ITK.selectedLabel) .. " / " .. fmt(ITK.selectedID))
        statusKV(rows, "object ref", tostring(zombie))
        statusKV(rows, "position / dPlayer", position(zombie) .. " / " .. fmt(distance(zombie, player)))
        statusKV(rows, "health / dead", fmt(safe(zombie, "getHealth", "-")) .. " / " .. boolText(safe(zombie, "isDead", false)))
        statusKV(rows, "moving / pathing / hasPath", boolText(safe(zombie, "isMoving", false)) .. " / " .. boolText(safe(zombie, "isPathing", false)) .. " / " .. boolText(safe(zombie, "hasPath", false)))
        statusKV(rows, "useless / onFloor / knocked", boolText(safe(zombie, "isUseless", false)) .. " / " .. boolText(safe(zombie, "isOnFloor", false)) .. " / " .. boolText(safe(zombie, "isKnockedDown", false)))
        statusKV(rows, "target", tostring(target))
        statusKV(rows, "bThrillerDance", ITK.getVar(zombie, "bThrillerDance", true))
        statusKV(rows, "ThrillerAnim", ITK.getVar(zombie, "ThrillerAnim", true))
        statusKV(rows, "bPathfind / walkType", fmt(ITK.getVar(zombie, "bPathfind", true)) .. " / " .. fmt(ITK.getVar(zombie, "zombieWalkType", true)))
    else
        statusAdd(rows, "warn", "No selected zombie. Expand Actor Registry and click an ID.")
    end

    statusAdd(rows, "section", "PLAYER / SCAN")
    if player then
        statusKV(rows, "player / position", tostring(player) .. " / " .. position(player))
        statusKV(rows, "player ID", util.getPID(player))
        statusKV(rows, "player health / dead", fmt(safe(player, "getHealth", "-")) .. " / " .. boolText(safe(player, "isDead", false)))
        local report = state.report and state.report[util.getPID(player)]
        if report then
            statusKV(rows, "sight/ near/ tar", fmt(report.sightCount) .. " / " .. fmt(report.nearCount) .. " / " .. fmt(report.targeting))
            statusKV(rows, "area / safe / range", fmt(report.areaCount) .. " / " .. fmt(report.safeCount) .. " / " .. fmt(report.rangeCount))
            statusKV(rows, "total ", fmt(report.total))
            statusKV(rows, "areaThreat"..fmt((report.rangeCount - report.areaCount) * 0.25 + report.areaCount * 0.75))
        else
            statusKV(rows, "scan report", "not available yet")
        end
    end

    statusAdd(rows, "section", "IMPORTANT CONFIG")
    statusKV(rows, "MaxZombies / MaxWave", fmt(util.getSV("MaxZombies")) .. " / " .. fmt(util.getSV("MaxWave")))
    statusKV(rows, "EventCooldown", util.getSV("EventCooldown"))
    statusKV(rows, "danceRate / maxActiveDancer", fmt(config.get("danceRate")) .. " / " .. fmt(config.get("maxActiveDancer")))
    statusKV(rows, "finalCountDown / grudgeBeats", fmt(config.get("finalCountDown")) .. " / " .. fmt(config.get("grudgeBeats")))

    statusAdd(rows, "section", "LAST ACTION")
    statusAdd(rows, "kv", self.lastAction or (ITK and ITK.lastResult) or "-")
    return rows
end

function IsThrillerDevPanel:refreshStatus(force)
    if not self.content then return end
    local now = getTimestampMs()
    if not force and self.nextRefresh and now < self.nextRefresh then return end
    self.nextRefresh = now + REFRESH_MS

    local signature = self:rosterSignature()
    if signature ~= self.lastRosterSignature then
        self:rebuildPagePicker(self.activePageID)
        force = true
    end

    local reportText, stateText = summaryTexts()
    self.reportLines = wrapText(reportText, self.width - PAD * 2, UIFont.Small)
    self.stateLines = wrapText(stateText, self.width - PAD * 2, UIFont.Small)
    self:layoutChildren()
    if self.activePageID == "live" or force then self:rebuildContent(not force) end
end

-- GPTNote: The stock window draws an opaque title texture, so draw the compact frame here to make the opacity option affect the whole panel.
function IsThrillerDevPanel:prerenderFrame()
    local th = self:titleBarHeight()
    local alpha = getPanelOpacity()
    if self.drawFrame then
        self:drawRect(0, 0, self.width, th, alpha, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
        self:drawTextureScaled(self.titlebarbkg, 2, 1, self.width - 4, th - 2, alpha, 1, 1, 1)
        self:drawRectBorder(0, 0, self.width, th, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    end
    if self.background then
        self:drawRect(0, th, self.width, self.height - th, alpha, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b)
    end
    if self.clearStentil then self:setStencilRect(0, 0, self.width, self.height) end
    if self.title and self.title ~= "" and self.drawFrame then
        self:drawTextCentre(self.title, self.width / 2, 1, 1, 1, 1, 1, self.titleBarFont)
    end
end

function IsThrillerDevPanel:prerender()
    self:refreshStatus(false)
    self:prerenderFrame()
    local lineH = getTextManager():getFontHeight(UIFont.Small)
    local reportText, stateText = summaryTexts()
    if self.compact then
        local textY = self:titleBarHeight() + 5
        for _, line in ipairs(self.reportLines or { reportText }) do
            self:drawText(line, PAD, textY, 0.88, 0.88, 0.88, 1, UIFont.Small)
            textY = textY + lineH
        end
        textY = textY + 10
        for _, line in ipairs(self.stateLines or { stateText }) do
            self:drawText(line, PAD, textY, 0.88, 0.88, 0.88, 1, UIFont.Small)
            textY = textY + lineH
        end
        return
    end

    local y = self:titleBarHeight() + PAD
    self:drawText("Audition Report", PAD, y, 0.78, 0.84, 0.90, 1, UIFont.Small)
    y = y + lineH + SUMMARY_LINE_GAP
    for _, line in ipairs(self.reportLines or { reportText }) do
        self:drawText(line, PAD, y, 0.88, 0.88, 0.88, 1, UIFont.Small)
        y = y + lineH
    end
    y = y + PAD - 3
    self:drawRect(PAD, y, self.width - PAD * 2, 1, 0.45, 0.65, 0.65, 0.65)
    y = y + 3
    self:drawText("Stage", PAD, y, 0.78, 0.84, 0.90, 1, UIFont.Small)
    y = y + lineH + SUMMARY_LINE_GAP
    for _, line in ipairs(self.stateLines or { stateText }) do
        self:drawText(line, PAD, y, 0.88, 0.88, 0.88, 1, UIFont.Small)
        y = y + lineH
    end
    y = y + PAD - 3
    self:drawRect(PAD, y, self.width - PAD * 2, 1, 0.45, 0.65, 0.65, 0.65)
    self:drawText("Active Page:", PAD, self.activePageLabelY, 0.78, 0.84, 0.90, 1, UIFont.Small)
end

function IsThrillerDevPanel:new(x, y, width, height)
    local panel = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.fullTitle = "IsThriller DevTool"
    panel.title = panel.fullTitle
    panel.expandSummaryTexture = getTexture("media/ui/ArrowDown.png")
    panel.pin = true
    panel:setResizable(false)
    panel.compact = false
    panel.activePageID = "live"
    panel.lastAction = "Panel opened"
    return panel
end

local function togglePanel()
    if instance and instance:getIsVisible() then
        instance:setVisible(false)
        instance:removeFromUIManager()
        return
    end
    if not instance then
        instance = IsThrillerDevPanel:new(100, 80, PANEL_W, PANEL_H)
        instance:initialise()
    end
    instance:setVisible(true)
    instance:addToUIManager()
    instance:refreshStatus(true)
end

local function onKeyPressed(keynum)
    if keynum ~= getToggleKey() or not getPlayer() or not isAllowed() then return end
    togglePanel()
end
Events.OnKeyPressed.Add(onKeyPressed)
