Zombas = Zombas or {}
Zombas.VERSION = "0.1.0"

-- Default config — runtime values come from Zombas.Options.get(key)
Zombas.Config = {
    -- Feature toggles
    EnableStakePit      = true,
    EnableHoleTrap      = true,
    EnableStakeFence    = true,

    -- Stake Pit
    MAX_STAKES          = 4,
    DAMAGE_MIN          = 3,
    DAMAGE_MAX          = 10,
    CRIT_CHANCE         = 12,   -- percent (0-100)
    CRIT_MULT           = 2.5,
    IMMOBILIZE_CHANCE   = 30,   -- percent
    IMMOBILIZE_TIME     = 600,  -- ticks
    COOLDOWN_TICKS      = 120,
    STAKE_BREAK_CHANCE  = 15,   -- percent, per stake per trigger

    -- Vehicle damage (stake pit)
    VEH_DAMAGE_MIN      = 10,
    VEH_DAMAGE_MAX      = 30,
    VEH_CRIT_CHANCE     = 15,   -- percent

    -- Hole Trap
    MaxHoleZombies      = 6,    -- 0 = unlimited
    HOLE_STRENGTH_REQ   = 4,

    -- Stake Fence
    FENCE_DAMAGE_MIN    = 2,
    FENCE_DAMAGE_MAX    = 8,
    FENCE_CRIT_CHANCE   = 10,   -- percent
    FENCE_BREAK_CHANCE  = 15,   -- percent, per stake per trigger
    MAX_FENCE_STAKES    = 5,
}

-- Moddata keys stored on IsoSquare
Zombas.MD = {
    -- Stake Pit
    HAS_PIT         = "Zombas.hasPit",
    STAKES          = "Zombas.stakes",
    CONCEALED       = "Zombas.concealed",
    COOLDOWN        = "Zombas.cooldown",
    ORIGINAL_FLOOR  = "Zombas.originalFloor",

    -- Hole Trap
    HAS_HOLE        = "Zombas.hasHole",
    HOLE_GENERATED  = "Zombas.holeGenerated",

    -- Stake Fence
    HAS_FENCE       = "Zombas.hasFence",
    FENCE_DIR       = "Zombas.fenceDir",
    FENCE_STAKES    = "Zombas.fenceStakes",
    FENCE_COOLDOWN  = "Zombas.fenceCooldown",
}

-- Custom mod sprites (registered via media/newtiledefinitions.tiles).
-- Each single-PNG tileset produces sprite name = filename + "_0".
Zombas.Sprites = {
    PIT_EMPTY   = "Zombas_SpikePit_0_0",
    PIT_STAKE_1 = "Zombas_SpikePit_1_0",
    PIT_STAKE_2 = "Zombas_SpikePit_2_0",
    PIT_STAKE_3 = "Zombas_SpikePit_3_0",
    PIT_STAKE_4 = "Zombas_SpikePit_4_0",
    FENCE_N     = "fencing_01_0",
    FENCE_W     = "fencing_01_1",
    HOLE        = "Zombas_Hole_0_0",
}

-- Floor tile prefixes/patterns valid for digging (dirt, grass, sand)
Zombas.ValidDigSurfaces = {
    "blends_natural",
    "vegetation",
    "dirt",
    "sand",
    "grass",
    "gravel",
}

-- Read a config value: SandboxVars first, then built-in default.
-- SandboxVars is populated by the game before any Lua runs (client and server).
function Zombas.get(key)
    local v = SandboxVars["RealTrapZ_" .. key]
    if v ~= nil then return v end
    return Zombas.Config[key]
end

-- Check if a floor tile name matches a valid dig surface
function Zombas.isDiggableSurface(square)
    if not square then return false end
    local floor = square:getFloor()
    if not floor then return false end
    local sprite = floor:getSprite()
    if not sprite then return false end
    local name = tostring(sprite:getName() or ""):lower()
    for _, pattern in ipairs(Zombas.ValidDigSurfaces) do
        if name:find(pattern, 1, true) then return true end
    end
    return false
end

-- Stake Pit helpers
function Zombas.hasPit(square)
    if not square then return false end
    return square:getModData()[Zombas.MD.HAS_PIT] == true
end

function Zombas.isArmed(square)
    if not square then return false end
    return (square:getModData()[Zombas.MD.STAKES] or 0) > 0
end

function Zombas.isConcealed(square)
    if not square then return false end
    return square:getModData()[Zombas.MD.CONCEALED] == true
end

-- Hole Trap helpers
function Zombas.hasHole(square)
    if not square then return false end
    return square:getModData()[Zombas.MD.HAS_HOLE] == true
end

function Zombas.countZombiesInHole(square)
    local below = getCell():getGridSquare(
        square:getX(), square:getY(), square:getZ() - 1)
    if not below then return 0 end
    local objs = below:getMovingObjects()
    if not objs then return 0 end
    local count = 0
    for i = 0, objs:size() - 1 do
        if instanceof(objs:get(i), "IsoZombie") then
            count = count + 1
        end
    end
    return count
end

-- Stake Fence helpers
function Zombas.hasFence(square)
    if not square then return false end
    return square:getModData()[Zombas.MD.HAS_FENCE] == true
end

function Zombas.getFenceDir(square)
    return square:getModData()[Zombas.MD.FENCE_DIR]
end

-- Find the Zombas IsoObject on a square by internal tag
function Zombas.getTrapObject(square, tag)
    local objs = square:getSpecialObjects()
    if not objs then return nil end
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        if obj and obj:getModData()["Zombas.tag"] == tag then
            return obj
        end
    end
    return nil
end

-- Dig-tool helper (shovel or garden trowel)
function Zombas.hasDigTool(inv)
    return inv:containsTypeRecurse("Base.Shovel")
        or inv:containsTypeRecurse("Base.ShovelGardenTrowel")
end

-- Spear helpers — detect by type name ("Spear" in the ID) since
-- getSubCategory() is not available on InventoryItem in B42 Kahlua.
function Zombas.isSpear(item)
    if not item then return false end
    local t = item:getType()
    if not t then return false end
    -- Use Java String method since getType() returns a Java String in Kahlua
    return t:contains("Spear") or t:contains("spear")
end

function Zombas.countSpears(inv)
    local items = inv:getItems()
    local count = 0
    for i = 0, items:size() - 1 do
        if Zombas.isSpear(items:get(i)) then count = count + 1 end
    end
    return count
end

function Zombas.removeSpears(inv, count)
    local items = inv:getItems()
    local toRemove = {}
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if Zombas.isSpear(item) then
            toRemove[#toRemove + 1] = item
            if #toRemove >= count then break end
        end
    end
    for _, item in ipairs(toRemove) do
        inv:Remove(item)
    end
end

-- Update the pit floor tile to reflect current stake count.
-- Called after adding a stake or revealing a concealed pit.
function Zombas.updatePitSprite(square)
    local md = square:getModData()
    if md[Zombas.MD.CONCEALED] then return end
    local floor = square:getFloor()
    if not floor then return end
    local stakes = md[Zombas.MD.STAKES] or 0
    local spriteName
    if     stakes == 0 then spriteName = Zombas.Sprites.PIT_EMPTY
    elseif stakes == 1 then spriteName = Zombas.Sprites.PIT_STAKE_1
    elseif stakes == 2 then spriteName = Zombas.Sprites.PIT_STAKE_2
    elseif stakes == 3 then spriteName = Zombas.Sprites.PIT_STAKE_3
    else                     spriteName = Zombas.Sprites.PIT_STAKE_4
    end
    local sprite = getSprite(spriteName)
    if sprite then floor:setSprite(sprite) end
end
