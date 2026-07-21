-- GPTNote: 按音乐模组ID维护完整专辑，并在模组初始化时汇总已激活的JacketFull。
local Drop = {
    totalRewardItems = 5,
    
    pickRate = {        -- total should be 1000
        ammos = 140,
        bombs = 220,
        weapons = 220,
        medic = 120,
        other  = 300,
    }
}

Drop.growSticks = {
    "AuthenticZClothing.AuthenticGlowstick_Red",
    "AuthenticZClothing.AuthenticGlowstick_Blue",
    "AuthenticZClothing.AuthenticGlowstick_Green",
    "AuthenticZClothing.AuthenticGlowstick_Orange",
    "AuthenticZClothing.AuthenticGlowstick_Pink",
    "AuthenticZClothing.AuthenticGlowstick_Purple",
    "AuthenticZClothing.AuthenticGlowstick_Yellow",
    "AuthenticZClothing.AuthenticGlowstick_White",
}

Drop.itemList = {
    -- full type list
    ammos = {
        "Base.Bullets9mmBox", "Base.Bullets38Box", "Base.Bullets44Box", "Base.223Box", 
        "Base.308Box", "Base.ShotgunShellsBox", "Base.Bullets45Box", "Base.556Box"
    },
    
    bombs = {
        "Base.SmokeBomb", "Base.Molotov", "Base.Aerosolbomb", "Base.FlameTrap",
        "Base.PipeBomb", "Base.AerosolbombRemote"
    },
    
    weapons = {
        "Base.Axe", "Base.HandAxeForged", "Base.IceAxe", "Base.JawboneBovide_Axe",
        "Base.LongHandle_Sawblade", "Base.StoneAxeLarge", "Base.BaseballBat_Metal_Sawblade",
        "Base.PickAxeForged", "Base.Axe_Sawblade", "Base.Axe_ScrapCleaver",
        "Base.WoodAxeForged", "Base.CrowbarForged", "Base.BaseballBat_Metal_Bolts",
        "Base.Sledgehammer", "Base.Katana", "Base.Sword"
    },
    
    medic = {
        "Base.Antibiotics", "Base.PillsAntiDep", "Base.PillsBeta", "Base.PillsVitamins"
    },

    other = {
        "Base.PigIronIngot", "Base.BrassIngot", "Base.CopperIngot", "Base.SteelIngot",
        "Base.MetalBar", "Base.MetalCup", "Base.MetalDrum", "Base.MetalPipe",
        "Base.CannedBellPepper", "Base.CannedBolognese", "Base.CannedBroccoli",
        "Base.CannedCabbage", "Base.CannedCarrots", "Base.CannedChili",
        "Base.CannedCorn", "Base.CannedCornedBeef", "Base.CannedEggplant",
        "Base.CannedFruitBeverage", "Base.CannedFruitCocktail", "Base.CannedLeek",
        "Base.CannedMilk", "Base.CannedMushroomSoup", "Base.CannedPeaches",
        "Base.CannedPeas", "Base.CannedPineapple", "Base.CannedPotato",
        "Base.CannedRedRadish", "Base.CannedRoe", "Base.CannedSardines",
        "Base.CannedTomato"
    }
}

Drop.specialItem = "IsThriller.HealTheWorld"
Drop.fanTicket = "IsThriller.FanTicket"

Drop.special = {
    fullList = {},

    MichaelJackson1 = {
        "MichaelJackson1.XscapeJacketFull",
    },

    MichaelJackson3 = {
        "MichaelJackson3.InvicibleJacketFull",
    },

    NewMusicMJD = {
        "NewMusicMJD.DangerousJacketFull",
    },

    NMBJMJ = {
        "NMBJMJ.MichaelJacksonOffTheWall79JacketFull",
        "NMBJMJ.MichaelJacksonThriller82JacketFull",
        "NMBJMJ.MichaelJacksonBad87JacketFull",
        "NMBJMJ.MichaelJacksonDangerous91JacketFull",
        "NMBJMJ.MichaelJacksonMotownMixJacketFull",
    },
}

function Drop.initSpecial()
    local fullList = {}
    Drop.special.fullList = fullList

    local activeMods = getActivatedMods and getActivatedMods()
    local manager = getScriptManager and getScriptManager()
    if not activeMods then return fullList end

    for modId, items in pairs(Drop.special) do
        if modId ~= "fullList" and activeMods:contains(modId) then
            for _, fullType in ipairs(items) do
                local exists = manager == nil
                if manager then
                    pcall(function()
                        exists = manager:FindItem(fullType) ~= nil
                    end)
                end
                if exists then
                    fullList[#fullList + 1] = fullType
                end
            end
        end
    end

    if IsThriller and IsThriller.util then
        IsThriller.util.debugMsg("special album list initialized", "count=", #fullList)
    end
    return fullList
end

function Drop.pickSticks()
    local id = ZombRand(#Drop.growSticks + 1)
    return Drop.growSticks[id]
end

return Drop
