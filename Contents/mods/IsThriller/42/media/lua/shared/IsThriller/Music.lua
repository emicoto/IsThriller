
if not IsThriller then return end

local util, conf = IsThriller.util, IsThriller.config

local Music = {
    handle = nil,               -- playSound 返回的long句柄, 用于isPlaying/setVolume/stopSound
    savedVol = nil,             -- saved original bgm volume
    list = {},                  -- song list for play
    fadeTimer = 0,              -- fade in/out timer
    fade = -1,                  -- fade tick
    tick = -1,                  -- music manage tick
    played = 0,                 -- played song counter

    gapStart = -1,              -- 幕间休息起点(游戏分钟戳), -1=不在幕间
    encored = false,            -- 本场是否已加演过recall
}

-- simulate (()=>{})() js auto invoked function expression
local function lfuncMusic()
    print("[LuneModDebug] shared.IsThriller.Music loaded...")

    local function buildSongList()
        -- ClaudeNote: 修复"歌单全是true"事故 — conf.get()先查沙盒变量,
        -- JustThriller等恰好是同名沙盒布尔项, 会把songFlag里的歌名遮蔽掉。
        -- 取歌名必须直接走 conf.songFlag, 不能经过 conf.get
        local songs = {}
        if util.getSV("JustThriller") then
            table.insert(songs, conf.songFlag.JustThriller)
        end
        if util.getSV("JustBeatIt") then
            table.insert(songs, conf.songFlag.JustBeatIt)
        end
        if util.getSV("JustSmoothCriminal") then
            table.insert(songs, conf.songFlag.JustSmoothCriminal)
        end

        -- if has extra songs from other mod then put then all in song list
        songs = Music.loadSong(songs)

        if #songs == 0 then
            for _, song in ipairs(conf.music.songs) do
                table.insert(songs, song)
            end
            util.debugMsg("buildSongList: empty selection, fallback to default full list")
        end

        return songs
    end
    
    ---@param soundId string
    function Music.addSong(soundId)
        table.insert(conf.music.extraSong, soundId)
    end

    ---@param songs table
    ---@return table
    function Music.loadSong(songs)
        if #conf.music.extraSong == 0 then return songs end

        for _, song in ipairs(conf.music.extraSong) do
            table.insert(songs, song)
        end
        return songs
    end


    function Music.init()
        Music.list = buildSongList()
        for _, song in ipairs(conf.music.songs) do
            getSoundManager():CacheSound(song)
        end
    end

    function Music.duckBgm()
        if Music.savedVol ~= nil then return end

        pcall(function() 
            Music.savedVol = getSoundManager():getMusicVolume()
            getSoundManager():setMusicVolume(0.1)
        end)
    end

    function Music.resBGM(frac)
        if Music.savedVol == nil then return end

        local vol = Music.savedVol * (frac or 1)
        pcall(function () getSoundManager():setMusicVolume(vol) end)
        if not frac or frac >= 1 then
            Music.savedVol = nil
        end
    end

    function Music.pick()
        local songs = Music.list
        if #songs == 0 then return end
        Music.current = songs[ZombRand(1, #songs + 1)]
        return true
    end

    function Music.play(player)
        local emitter = player and player:getEmitter()
        if not emitter or not Music.current then return false end

        if type(Music.current) ~= "string" then
            util.debugMsg("music.play: invalid song id", tostring(Music.current))
            return false
        end

        Music.handle = emitter:playSound(Music.current)
        if not Music.handle then return false end

        emitter:setVolume(Music.handle, 1.0)

        Music.duckBgm()
        Music.tick = 0
        Music.played = Music.played + 1

        -- 每首歌开播即进入新一轮前奏phase, 重置波次计数供Stage/Actor刷群演
        IsThriller.phase = 0

        util.debugMsg("music.play", "song=", tostring(Music.current), "played=", Music.played)
        return true
    end

    function Music.start(player)
        if not Music.current then
            if not Music.pick() then return false end
        end
        return Music.play(player)
    end

    function Music.beginFade()
        -- ClaudeNote: 返回bool供doFinal判断有无声可淡(B7配套)
        if not Music.handle then return false end
        Music.fadeTimer = getTimestampMs()
        Music.fade = 0
        util.debugMsg("music.beginFade", "current=", tostring(Music.current))
        return true
    end

    function Music.reset()
        Music.handle = nil
        Music.fadeTimer = 0
        Music.current = nil
        Music.fade = 0
        Music.played = 0
        Music.gapStart = -1 
        Music.encored = false 
    end

    function Music.stop(player)
        local emitter = player and player:getEmitter()
        if emitter and Music.handle  then
            emitter:stopSound(Music.handle)
        end

        Music.reset()
        Music.resBGM()
    end

    -- if state of the fading is done or should force stop. should reset the state on Main cycle.
    function Music.onTick(st, player)
        -- if call at outside
        if not player then return "hardstop" end

        local emitter = player:getEmitter()

        -- if fading
        if st:isFading() then
            -- 舞台层面的60游戏分钟尾声由Stage.checkFade负责, 不能再hardstop把舞台掐掉
            if not Music.handle then return false end

            -- still fading, tick cycle
            Music.fade = Music.fade + 1
            if Music.fade < 10 then return false end
            Music.fade = 0

            -- if something wrent wrong
            if not emitter then
                Music.stop(player)
                return "hardstop"
            end

            -- fading process stop
            local frac = (getTimestampMs() - Music.fadeTimer) / conf.music.fadeMs
            if frac >= 1 then
                Music.stop(player)
                return "finalstop"
            end

            emitter:setVolume(Music.handle, 1 - frac)
            Music.resBGM(frac)
            return false
        end

        if not st:isPlaying() then return false end

        -- tick cycle
        Music.tick = Music.tick + 1
        if Music.tick < conf.music.songCheckTicks then return false end
        Music.tick = 0

        if not emitter then return false end

        -- 幕间休息中: 歌与歌之间隔gapRealSec(60真实秒)对应的游戏时间。
        -- 全部按游戏时间计算(countMin/toGameTime), 单机加速时不会错拍
        if Music.gapStart >= 0 then
            local elapsed = util.countMin(Music.gapStart)
            if elapsed < util.toGameTime(conf.music.gapRealSec) then return false end

            Music.gapStart = -1
            if Music.pick() then
                Music.play(player)
            end
            return false
        end

        if not Music.handle then return false end

        local playing = emitter:isPlaying(Music.handle)
        if playing then return false end

        -- 一首播完了
        Music.handle = nil

        -- myBgm单曲播完即自然结束, 不续播不淡出
        if st:isMyBgm() then
            return "bgmdone"
        end

        -- 播满MaxWave(沙盒)首歌交给Stage.onSongLimit
        -- 决定加演recall还是进入尾声, 不再由Music直接判死
        if Music.played >= util.getSV("MaxWave") then
            return "songlimit"
        end

        -- 进入幕间: 先恢复原版BGM氛围, 下一首开播时再压
        Music.gapStart = util.getMin()
        Music.resBGM()
        util.debugMsg("music gap start", "gapStart=", Music.gapStart)

        return false
    end

end

pcall(lfuncMusic)

return Music