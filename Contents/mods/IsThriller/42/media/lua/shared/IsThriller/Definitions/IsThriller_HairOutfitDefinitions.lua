-- GPTNote: Hair definitions paired with IsThriller's XML outfit sets.

require "Definitions/HairOutfitDefinitions"

local definitions = {
    {
        outfit = "ThrillerStageSet",
        femaleHaircut = "KateCurly:100",
        maleHaircut = "ShortAfroCurly:100",
        beard = "None:100",
        haircutColor = "0.05,0.05,0.05:100",
    },
    {
        outfit = "SmoothCriminalStageSet",
        femaleHaircut = "FabianCurly:100",
        maleHaircut = "FabianCurly:100",
        beard = "None:100",
        haircutColor = "0.05,0.05,0.05:100",
    },
    {
        outfit = "BeatItStageSet",
        femaleHaircut = "ShortAfroCurly:100",
        maleHaircut = "ShortAfroCurly:100",
        beard = "None:100",
        haircutColor = "0.05,0.05,0.05:100",
    },

    {
        outfit = "BadStageSet",
        femaleHaircut = "FabianCurly:100",
        maleHaircut = "FabianCurly:100",
        beard = "None:100",
        haircutColor = "0.05,0.05,0.05:100",
    },
    
    {
        outfit = "BillieJeanStageSet",
        femaleHaircut = "ShortAfroCurly:100",
        maleHaircut = "ShortAfroCurly:100",
        beard = "None:100",
        haircutColor = "0.05,0.05,0.05:100",
    },
}

for _, definition in ipairs(definitions) do
    table.insert(HairOutfitDefinitions.haircutOutfitDefinition, definition)
end
