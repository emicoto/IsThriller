-- GPTNote: Hair definitions paired with IsThriller's XML outfit sets.

require "Definitions/HairOutfitDefinitions"

local definitions = {
    {
        outfit = "IsThrillerThriller",
        femaleHaircut = "KateCurly:100",
        maleHaircut = "ShortAfroCurly:100",
        beard = "None:100",
        haircutColor = "0.05,0.05,0.05:100",
    },
    {
        outfit = "IsThrillerSmoothCriminal",
        femaleHaircut = "FabianCurly:100",
        maleHaircut = "FabianCurly:100",
        beard = "None:100",
        haircutColor = "0.05,0.05,0.05:100",
    },
    {
        outfit = "IsThrillerBeatIt",
        femaleHaircut = "ShortAfroCurly:100",
        maleHaircut = "ShortAfroCurly:100",
        beard = "None:100",
        haircutColor = "0.05,0.05,0.05:100",
    },
}

for _, definition in ipairs(definitions) do
    table.insert(HairOutfitDefinitions.haircutOutfitDefinition, definition)
end
