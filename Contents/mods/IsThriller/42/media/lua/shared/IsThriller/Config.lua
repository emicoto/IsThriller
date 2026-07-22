local Config = {

    modId = "isThriller",
    version = 2,

    scanTime = 1 ,          -- how many second per zombie scan

    -- raw sandbox var
    sv = {
        Range           = 24,   -- default range to lure zombies
        SprintChance    = 10,   -- 10% chance to sprint
        MaxZombies      = 6,    -- maximum additional zombies per phase
        MaxDancer       = 4,    -- max mini boss will spawn with MJ
        MaxWave         = 5,    -- 最大波次=事件内歌曲上限, 每首歌前奏期每2秒刷一波群演
        MaxFinal        = 30,    -- max zombies when the early final has been triggered
        EventChance     = 25,   -- event rate per in-game min
        EventCooldown   = 2,    -- event cooldown after stage fully finish
 
        JustThriller    = true,
        JustBeatIt      = true,
        JustSmoothCriminal = true,
        NoBodyCanBeatMeInBGM = false,
    },

    --== triggers ==--
    flag = {
        safeRange       = 32,       -- no zombie in this range consider as safe
        nearRange       = 7,        -- how much distance consider as near by player
        fadeMin         = 7,       -- how much time didn't get attention by zombies after stage be wiped, then consider as safe
        safeMinSP       = 20,       -- how much time didn't get attention by zombies consider as safe
        safeMinMP       = 36,
        maxPhase        = 30,       -- max waves of thriller stage per song, soft limitation
        escapeDistance  = 300,      -- how much distance if stay in 30 min consider as transported then consider safe
        minNearZombie   = 8,
        minRangeZombie  = 16,
        minTargetZombie = 6,
        danceRate       = 30,       -- the rate of dancing zombies
        sprinterRateAtRiot = 30,    -- the rate of sprinter zombies during riot
        superSprinterRate  = 10,    -- the rate of super sprinter during riot

        wipeBonus = 3 ,
        rewardBox = "Base.Present_ExtraLarge",
        
        JuiceExchange = 5,          -- FanTicket兑换KingOfPopJuice所需张数
        HealExchange = 8,           -- FanTicket兑换HealTheWorld所需张数(原5)
        AuraExchange = 20,          -- FanTicket兑换GhostTicket(隐身卷)所需张数(原3的幽灵buff升级为隐身卷)ItemBuffMin = 60,           -- 果汁压制期与隐身卷持续时长(游戏分钟)
        ItemBuffMin = 60,           -- 果汁压制期与隐身卷持续时长(游戏分钟)
    },


    --== stage controll ==--
    stage = {
        radius = 40,        -- world sound radius
        minLureSec = 12,    -- lure缓冲时间（真实秒）
        maxLureSec = 36,    -- lure超时(真实秒), 判定时经toGameTime换算游戏分钟
        spawnDist = 18,     -- how faraway from player when actor try to spawn
        grudgeBeats = 30,   -- cooldown when get hit

        -- 舞蹈判定权收归主MOD
        danceExitRange = 12,    -- MJ跳舞中玩家超过此距离则收舞追场(与danceRange构成滞回)
        danceRange = 6,         -- the range consider player can see the dance show
        groupRange = 3,        -- 伴舞锚定MJ的编队/起舞半径
        rallySec = 20,          -- rally超时(真实秒), 到点没齐也强制开拔march

        retreatDistance = 8,    -- retreat when get hit

        finalCountDown = 45, -- fading尾声周期时长(游戏分钟), 到点正式散场
        encoreChance = 60,   -- 播满波次且全员存活时加演recall的概率(%)

        waveSec = 2,         -- 前奏波次间隔(真实秒)
        attendRange = 10,    -- 和平观演考勤半径(格)
        attendRate = 0.5,    -- 考勤达标线(在场分钟/演出总分钟)
    
        maxActiveDancer = 30,
    },


    --== zombies setting ==--
    actor = {
        mjHP = 30,           -- mj zombies health multipler
        djHP = 10,            -- dancer zombies health multipler
        healPer = 0.10,      -- dancer health healing percent while mj regen
    },

    --== music setting ==--
    music = {
        fadeMs = 3000,
        songCheckTicks = 60,
        maxSong = 5,        -- fallback, 沙盒MaxWave优先
        gapRealSec = 20,    -- 歌与歌之间的幕间休息(真实秒, 按日长折算游戏分钟)

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
        fadeStart   = 0,        -- fading尾声周期起点(游戏分钟戳)
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