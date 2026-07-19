local Config = {

    modId = "isThriller",
    version = 2,

    scanTime = 1 ,          -- how many second per zombie scan

    -- raw sandbox var
    sv = {
        Range           = 15,   -- default range to lure zombies
        SprintChance    = 10,   -- 10% chance to sprint
        MaxZombies      = 6,    -- maximum additional zombies per phase
        MaxDancer       = 2,    -- max mini boss will spawn with MJ
        MaxWave         = 5,    -- ClaudeNote: Q4拍板新增。最大波次=事件内歌曲上限, 每首歌前奏期每2秒刷一波群演
        EventChance     = 15,   -- event rate per in-game min
        EventCooldown   = 2,    -- event cooldown after stage fully finish
 
        JustThriller    = true,
        JustBeatIt      = true,
        JustSmoothCriminal = true,
        NoBodyCanBeatMeInBGM = false,
    },

    --== triggers ==--
    flag = {
        safeRange       = 20,       -- no zombie in this range consider as safe
        nearRange       = 7,        -- how much distance consider as near by player
        safeMinSP       = 10,       -- how much time didn't get attention by zombies consider as safe
        safeMinMP       = 20,
        maxPhase        = 5,        -- max waves count of thriller stage (fallback, 沙盒MaxWave优先)
        escapeDistance  = 300,      -- how much distance if stay in 30 min consider as transported then consider safe
        minNearZombie   = 5,
        minRangeZombie  = 12
    },


    --== stage controll ==--
    stage = {
        radius = 40,        -- world sound radius
        maxLureSec = 25,    -- ClaudeNote: 拍板30→20。lure超时(真实秒), 判定时经toGameTime换算游戏分钟
        spawnDist = 14,     -- how faraway from player when actor try to spawn
        danceRange = 4,     -- the range consider player can see the dance show
        slotArriveDist = 2, -- the range between actors
        grudgeBeats = 30,   -- cooldown when get hit

        -- 舞蹈判定权收归主MOD
        danceExitRange = 15,  -- MJ跳舞中玩家超过此距离则收舞追场(与danceRange构成滞回)
        dancerRange = 8,     -- 伴舞锚定MJ的编队/起舞半径
        rallyDist = 3,       -- 伴舞距MJ小于此视为汇合到位
        rallySec = 20,       -- rally超时(真实秒), 到点没齐也强制开拔march

        spinBeats = 5,       -- spin animation beats(~0.5s/per beat)
        moonwalkBeats = 6,
        retreatDistance = 4, -- retreat when get hit

        finalCountDown = 60, -- ClaudeNote: 语义更新 — fading尾声周期时长(游戏分钟), 到点正式散场
        encoreChance = 60,   -- ClaudeNote: Phase1.1新增 — 播满波次且全员存活时加演recall的概率(%)

        waveSec = 2,         -- 前奏波次间隔(真实秒)
        attendRange = 10,    -- 和平观演考勤半径(格)
        attendRate = 0.4,    -- 考勤达标线(在场分钟/演出总分钟)
    },

    wipeBonus = 3 ,
    rewardBox = "Base.Present_ExtraLarge",

    -- FanTicket兑换HealTheWorld所需张数
    fanTicketExchange = 5,

    --== zombies setting ==--
    actor = {
        mjHP = 30,           -- mj zombies health multipler
        djHP = 10,            -- dancer zombies health multipler
        healPer = 0.10,      -- dancer health healing percent while mj regen
        buffTick = 300,      -- how often do healing buff while regening
    },

    --== music setting ==--
    music = {
        fadeMs = 3000,
        songCheckTicks = 60,
        maxSong = 5,        -- fallback, 沙盒MaxWave优先
        gapRealSec = 30,    -- ClaudeNote: Phase1.1新增 — 歌与歌之间的幕间休息(真实秒, 按日长折算游戏分钟)

        songs = {
            "ThrillerSong", -- Thriller
            "BeatItSong", -- Beat It
            "SmoothCriminalSong", -- Smooth Criminal
        },

        extraSong = {},
    },

    -- ClaudeNote: 警告 — 这些key与同名沙盒布尔项冲突, 经Config.get会被沙盒值遮蔽(返回true而非歌名)。
    -- 取歌名请直接用 conf.songFlag.X
    songFlag = {
        JustThriller = "ThrillerSong",
        JustBeatIt = "BeatItSong",
        JustSmoothCriminal = "SmoothCriminalSong"
    },

    --== global data templer ==--
    data = {
        state       = "idle",   -- current runtime state
        lastStage   =  0,       -- the last stage runs in-game stamp
        cooldown    = -1,       -- stage cooldown hours counter, -1 means the stage triggered, set to 0 start to count
        song        = nil,      -- current playing song, only apply when mj spawn successfuly
        fadeStart   = 0,        -- ClaudeNote: Phase1.1新增 — fading尾声周期起点(游戏分钟戳)
    },
}

if not IsThriller then return Config end

function Config.get(varname)
    local ut = IsThriller.util

    local v = ut.getSV(varname)
    if v ~= nil then return v end

    if Config.flag[varname] then return Config.flag[varname] end
    if Config.stage[varname] then return Config.stage[varname] end
    if Config.actor[varname] then return Config.actor[varname] end
    if Config.songFlag[varname] then return Config.songFlag[varname] end
    
    return Config[varname]
end

return Config