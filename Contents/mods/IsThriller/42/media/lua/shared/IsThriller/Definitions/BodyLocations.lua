ThrillerBodyLocations = {}
ThrillerBodyLocations.Aura = ItemBodyLocation.register("thriller:aura")

local group = BodyLocations.getGroup("Human")
local auraLocation = ItemBodyLocation.get(ResourceLocation.of("thriller:aura"))
if auraLocation then
    group:getOrCreateLocation(auraLocation)
else
    print("WARNING: isThriller - Could not get body location - ItemBodyLocation.get() returned nil")
end