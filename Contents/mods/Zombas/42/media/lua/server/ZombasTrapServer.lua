-- Server-side trap logic: placement, trigger checks, damage, vehicle handling,
-- hole chamber generation, stake fence crossing detection.

-- Forward declarations required because these are used before their definitions
local registerSquare, unregisterSquare

-- ─── Utilities ───────────────────────────────────────────────────────────────

local function getSquare(x, y, z)
    return getCell():getGridSquare(x, y, z)
end

local function tableIsEmpty(t)
    for _ in pairs(t) do return false end
    return true
end

local function addTrapObject(square, spriteName, tag)
    -- TODO: visual placement pending correct B42 IsoThumpable API signature.
    -- Trap state lives in square moddata; mechanics work without a visual object.
    return nil
end

local function removeTrapObject(square, tag)
    local obj = Zombas.getTrapObject(square, tag)
    if not obj then return end
    square:RemoveSpecialObject(obj)
    square:RecalcProperties()
    square:RecalcAllWithNeighbours(true)
end

local function giveItem(character, fullType)
    if not character then return end
    local inv = character:getInventory()
    if inv.AddItem then
        local ok, item = pcall(function() return inv:AddItem(fullType) end)
        if ok and item then return end
    end
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        local item = InventoryItemFactory.CreateItem(fullType)
        if item then inv:AddItem(item) end
    end
end

-- ─── Valid dig surface list (mirrors Zombas.ValidDigSurfaces) ────────────────

local function isDiggable(square)
    return Zombas.isDiggableSurface(square)
end

-- ─── Stake Pit ───────────────────────────────────────────────────────────────

local function placePit(square)
    local md    = square:getModData()
    local floor = square:getFloor()
    -- Save original ground tile so disarm can restore it
    if floor then
        local spr = floor:getSprite()
        if spr then md[Zombas.MD.ORIGINAL_FLOOR] = tostring(spr:getName()) end
    end
    md[Zombas.MD.HAS_PIT]   = true
    md[Zombas.MD.STAKES]     = 0
    md[Zombas.MD.CONCEALED]  = false
    md[Zombas.MD.COOLDOWN]   = 0
    -- Visual: replace floor tile with empty pit sprite
    local pitSpr = getSprite(Zombas.Sprites.PIT_EMPTY)
    if pitSpr and floor then floor:setSprite(pitSpr) end
    registerSquare(square)
end

local function concealPit(square)
    local md    = square:getModData()
    local floor = square:getFloor()
    md[Zombas.MD.CONCEALED] = true
    local haySprite = getSprite("floors_interior_tilesandstone2_8")
    if haySprite and floor then floor:setSprite(haySprite) end
end

local function revealPit(square)
    local md = square:getModData()
    md[Zombas.MD.CONCEALED] = false
    Zombas.updatePitSprite(square)
end

local function disarmPit(character, square)
    local md     = square:getModData()
    local stakes = md[Zombas.MD.STAKES] or 0
    for _ = 1, stakes do giveItem(character, "Base.SpearCrafted") end
    -- Restore original ground floor (saved at placePit time)
    local floor = square:getFloor()
    if floor and md[Zombas.MD.ORIGINAL_FLOOR] then
        local groundSpr = getSprite(md[Zombas.MD.ORIGINAL_FLOOR])
        if groundSpr then floor:setSprite(groundSpr) end
    end
    md[Zombas.MD.HAS_PIT]       = nil
    md[Zombas.MD.STAKES]         = nil
    md[Zombas.MD.CONCEALED]      = nil
    md[Zombas.MD.COOLDOWN]       = nil
    md[Zombas.MD.ORIGINAL_FLOOR] = nil
    unregisterSquare(square)
end

local function breakStakes(square)
    local md     = square:getModData()
    local stakes = md[Zombas.MD.STAKES] or 0
    local chance = Zombas.get("STAKE_BREAK_CHANCE")
    local broken = 0
    for _ = 1, stakes do
        if ZombRand(100) < chance then broken = broken + 1 end
    end
    if broken > 0 then
        md[Zombas.MD.STAKES] = math.max(0, stakes - broken)
        Zombas.updatePitSprite(square)

    end
end

local function triggerPit(square, entity)
    local md = square:getModData()
    if not md[Zombas.MD.HAS_PIT] then return end
    local stakes = md[Zombas.MD.STAKES] or 0
    if stakes == 0 then return end

    local now = getTimestamp()
    if now < (md[Zombas.MD.COOLDOWN] or 0) then return end

    local dMin  = Zombas.get("DAMAGE_MIN")
    local dMax  = Zombas.get("DAMAGE_MAX")
    local scale = stakes / Zombas.get("MAX_STAKES")
    local dmg   = (dMin + ZombRand(dMax - dMin + 1)) * scale

    local isCrit = ZombRand(100) < Zombas.get("CRIT_CHANCE")
    if isCrit then dmg = dmg * Zombas.get("CRIT_MULT") end

    if instanceof(entity, "IsoZombie") then
        local bd = entity:getBodyDamage()
        bd:SetOverallBodyHealth(bd:getOverallBodyHealth() - dmg)
        if ZombRand(100) < Zombas.get("IMMOBILIZE_CHANCE") then
            entity:knockDown(true)
        end
    elseif instanceof(entity, "IsoPlayer") then
        local bd = entity:getBodyDamage()
        bd:AddDamage(BodyPartType.FootL, dmg * 0.5)
        bd:AddDamage(BodyPartType.FootR, dmg * 0.5)
        if isCrit then
            bd:AddDamage(BodyPartType.LowerLegL, dmg * 0.3)
        end
    end

    -- Reveal if concealed
    if md[Zombas.MD.CONCEALED] then revealPit(square) end

    breakStakes(square)
    md[Zombas.MD.COOLDOWN] = now + Zombas.get("COOLDOWN_TICKS")

end

-- ─── Vehicle damage (Stake Pit) ──────────────────────────────────────────────

local TIRE_PARTS = { "TireFL", "TireFR", "TireRL", "TireRR" }

local function closestTire(vehicle, sq)
    local tx = sq:getX() + 0.5
    local ty = sq:getY() + 0.5
    local best, bestDist = nil, math.huge
    for _, partId in ipairs(TIRE_PARTS) do
        local part = vehicle:getPartById(partId)
        if part then
            -- Approximate tire world position from vehicle center + offset by angle
            local angle  = vehicle:getAngle() or 0
            local rad    = math.rad(angle)
            local offX, offY = 0, 0
            if partId == "TireFL" then offX, offY =  0.7, -1.2
            elseif partId == "TireFR" then offX, offY = -0.7, -1.2
            elseif partId == "TireRL" then offX, offY =  0.7,  1.2
            else                           offX, offY = -0.7,  1.2
            end
            local wx = vehicle:getX() + offX * math.cos(rad) - offY * math.sin(rad)
            local wy = vehicle:getY() + offX * math.sin(rad) + offY * math.cos(rad)
            local d  = (wx - tx)^2 + (wy - ty)^2
            if d < bestDist then best, bestDist = part, d end
        end
    end
    return best
end

local function triggerVehicle(square, vehicle)
    local md = square:getModData()
    if not md[Zombas.MD.HAS_PIT] then return end
    local stakes = md[Zombas.MD.STAKES] or 0
    if stakes == 0 then return end

    local now = getTimestamp()
    if now < (md[Zombas.MD.COOLDOWN] or 0) then return end

    local tire = closestTire(vehicle, square)
    if not tire then return end

    local scale  = stakes / Zombas.get("MAX_STAKES")
    local dmg    = (Zombas.get("VEH_DAMAGE_MIN") + ZombRand(
        Zombas.get("VEH_DAMAGE_MAX") - Zombas.get("VEH_DAMAGE_MIN") + 1)) * scale
    local isCrit = ZombRand(100) < Zombas.get("VEH_CRIT_CHANCE")

    if isCrit then
        tire:setCondition(0)   -- blowout
    else
        local cur = tire:getCondition()
        tire:setCondition(math.max(0, cur - dmg))
    end

    if md[Zombas.MD.CONCEALED] then revealPit(square) end
    breakStakes(square)
    md[Zombas.MD.COOLDOWN] = now + Zombas.get("COOLDOWN_TICKS")

end

-- ─── Hole Trap ───────────────────────────────────────────────────────────────

local DIRT_WALL_SPRITE = "walls_exterior_house_01_0"
local DIRT_FLOOR_SPRITE = "floors_exterior_tilesandstone2_0"

local function generateChamber(x, y, z)
    local below = getSquare(x, y, z)
    if not below then return end

    -- Place floor
    local floorSpr = getSprite(DIRT_FLOOR_SPRITE)
    if floorSpr then
        local f = below:getFloor()
        if f then f:setSprite(floorSpr) end
    end

    -- Place walls on each cardinal side only if no wall exists there
    local neighbours = {
        { sq = getSquare(x,   y-1, z), face = "S" },
        { sq = getSquare(x,   y+1, z), face = "N" },
        { sq = getSquare(x-1, y,   z), face = "E" },
        { sq = getSquare(x+1, y,   z), face = "W" },
    }
    local wallSpr = getSprite(DIRT_WALL_SPRITE)
    for _, n in ipairs(neighbours) do
        if n.sq and wallSpr then
            -- Only add wall if the adjacent square has no existing building wall
            local hasWall = n.sq:getNorth() ~= nil or n.sq:getWest() ~= nil
            if not hasWall and IsoObject and IsoObject.new then
                local ok, wall = pcall(function()
                    return IsoObject.new(n.sq:getCell(), n.sq, wallSpr)
                end)
                if ok and wall then
                    wall:setSolid(true)
                    wall:getModData()["Zombas.tag"] = "holeWall"
                    n.sq:AddSpecialObject(wall)
                    n.sq:RecalcProperties()
                end
            end
        end
    end
end

local function placeHole(square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local below    = getSquare(x, y, z - 1)
    local needGen  = not below or not below:getFloor() or below:getFloor():getSprite() == nil

    if needGen then generateChamber(x, y, z - 1) end

    local md    = square:getModData()
    local floor = square:getFloor()
    -- Save original ground tile for reference (holes currently cannot be disarmed)
    if floor then
        local spr = floor:getSprite()
        if spr then md[Zombas.MD.ORIGINAL_FLOOR] = tostring(spr:getName()) end
    end
    md[Zombas.MD.HAS_HOLE]       = true
    md[Zombas.MD.HOLE_GENERATED] = needGen
    -- Visual: replace floor tile with dark hole sprite
    local holeSpr = getSprite(Zombas.Sprites.HOLE)
    if holeSpr and floor then floor:setSprite(holeSpr) end
    registerSquare(square)
end

local function triggerHole(square, entity)
    if not Zombas.hasHole(square) then return end

    local maxZ = Zombas.get("MaxHoleZombies")
    if instanceof(entity, "IsoZombie") then
        if maxZ > 0 and Zombas.countZombiesInHole(square) >= maxZ then return end
    end

    local bx, by, bz = square:getX(), square:getY(), square:getZ() - 1
    local below = getSquare(bx, by, bz)
    if not below then return end

    -- Teleport entity; native fall-damage physics triggers on position change
    entity:setX(bx + 0.5)
    entity:setY(by + 0.5)
    entity:setZ(bz)
end

-- ─── Stake Fence ─────────────────────────────────────────────────────────────

local function placeFence(square, dir)
    local md = square:getModData()
    md[Zombas.MD.HAS_FENCE]    = true
    md[Zombas.MD.FENCE_DIR]    = dir
    md[Zombas.MD.FENCE_STAKES] = Zombas.get("MAX_FENCE_STAKES")
    md[Zombas.MD.FENCE_COOLDOWN] = 0
    local spriteName = (dir == "N") and Zombas.Sprites.FENCE_N or Zombas.Sprites.FENCE_W
    addTrapObject(square, spriteName, "fence")

    registerSquare(square)
end

local function disarmFence(character, square)
    local md     = square:getModData()
    local stakes = md[Zombas.MD.FENCE_STAKES] or 0
    for _ = 1, stakes do giveItem(character, "Base.SpearCrafted") end
    removeTrapObject(square, "fence")
    md[Zombas.MD.HAS_FENCE]     = nil
    md[Zombas.MD.FENCE_DIR]     = nil
    md[Zombas.MD.FENCE_STAKES]  = nil
    md[Zombas.MD.FENCE_COOLDOWN] = nil

    unregisterSquare(square)
end

local function breakFenceStakes(square)
    local md     = square:getModData()
    local stakes = md[Zombas.MD.FENCE_STAKES] or 0
    local chance = Zombas.get("FENCE_BREAK_CHANCE")
    local broken = 0
    for _ = 1, stakes do
        if ZombRand(100) < chance then broken = broken + 1 end
    end
    if broken > 0 then
        local newCount = math.max(0, stakes - broken)
        md[Zombas.MD.FENCE_STAKES] = newCount
        if newCount == 0 then
            removeTrapObject(square, "fence")
            md[Zombas.MD.HAS_FENCE]     = nil
            md[Zombas.MD.FENCE_DIR]     = nil
            md[Zombas.MD.FENCE_COOLDOWN] = nil
        end

    end
end

local function triggerFence(square, entity)
    local md = square:getModData()
    if not md[Zombas.MD.HAS_FENCE] then return end

    local now = getTimestamp()
    if now < (md[Zombas.MD.FENCE_COOLDOWN] or 0) then return end

    local fenceStakes = md[Zombas.MD.FENCE_STAKES] or 0
    local scale = fenceStakes / Zombas.get("MAX_FENCE_STAKES")
    local dMin = Zombas.get("FENCE_DAMAGE_MIN")
    local dMax = Zombas.get("FENCE_DAMAGE_MAX")
    local dmg  = (dMin + ZombRand(dMax - dMin + 1)) * scale

    local isCrit = ZombRand(100) < Zombas.get("FENCE_CRIT_CHANCE")
    if isCrit then dmg = dmg * Zombas.get("CRIT_MULT") end

    if instanceof(entity, "IsoZombie") then
        local bd = entity:getBodyDamage()
        bd:SetOverallBodyHealth(bd:getOverallBodyHealth() - dmg)
    elseif instanceof(entity, "IsoPlayer") then
        local bd = entity:getBodyDamage()
        bd:AddDamage(BodyPartType.LowerLegL, dmg * 0.5)
        bd:AddDamage(BodyPartType.LowerLegR, dmg * 0.5)
    end

    breakFenceStakes(square)
    md[Zombas.MD.FENCE_COOLDOWN] = now + 30

end

-- ─── Active trap registry ────────────────────────────────────────────────────
-- Populated when traps are placed/disarmed and when squares load from a save.
-- Avoids scanning the whole area around players every tick.

local activePits   = {}   -- sqKey -> sq
local activeHoles  = {}   -- sqKey -> sq
local activeFences = {}   -- sqKey -> { sq=sq, dir="N"|"W" }
local prevPos      = {}   -- entity id -> { x, y, z }

local function sqKey(sq)
    return sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
end

registerSquare = function(sq)
    local key = sqKey(sq)
    if Zombas.hasPit(sq)   then activePits[key]   = sq end
    if Zombas.hasHole(sq)  then activeHoles[key]  = sq end
    if Zombas.hasFence(sq) then
        activeFences[key] = { sq = sq, dir = Zombas.getFenceDir(sq) }
    end
end

unregisterSquare = function(sq)
    local key = sqKey(sq)
    activePits[key]   = nil
    activeHoles[key]  = nil
    activeFences[key] = nil
end

-- OnLoadGridsquare doesn't exist server-side in B42.
-- Registry is populated at runtime: traps are registered when created,
-- and a small scan around each player repopulates it after load.

-- ─── Player triggers (immediate, no tick needed) ──────────────────────────────

local function checkFenceCrossingForEntity(entity, id)
    if not Zombas.get("EnableStakeFence") then return end
    if tableIsEmpty(activeFences) then return end

    local cx  = math.floor(entity:getX())
    local cy  = math.floor(entity:getY())
    local cz  = math.floor(entity:getZ())
    local prev = prevPos[id]

    if prev and (cx ~= prev.x or cy ~= prev.y) then
        local dx = cx - prev.x
        local dy = cy - prev.y

        if math.abs(dx) == 1 and dy == 0 then
            local fenceSq = dx > 0
                and getSquare(cx, cy, cz)
                or  getSquare(prev.x, prev.y, prev.z)
            if fenceSq and Zombas.hasFence(fenceSq)
                and Zombas.getFenceDir(fenceSq) == "W"
            then
                triggerFence(fenceSq, entity)
            end
        elseif dx == 0 and math.abs(dy) == 1 then
            local fenceSq = dy > 0
                and getSquare(cx, cy, cz)
                or  getSquare(prev.x, prev.y, prev.z)
            if fenceSq and Zombas.hasFence(fenceSq)
                and Zombas.getFenceDir(fenceSq) == "N"
            then
                triggerFence(fenceSq, entity)
            end
        end
    end

    prevPos[id] = { x = cx, y = cy, z = cz }
end

local scannedPlayers = {}

local function scanNearbyTraps(player)
    local cx = math.floor(player:getX())
    local cy = math.floor(player:getY())
    local cz = math.floor(player:getZ())
    for dx = -8, 8 do
        for dy = -8, 8 do
            local s = getSquare(cx + dx, cy + dy, cz)
            if s and (Zombas.hasPit(s) or Zombas.hasHole(s) or Zombas.hasFence(s)) then
                registerSquare(s)
            end
        end
    end
end

Events.OnPlayerUpdate.Add(function(player)
    if not player then return end
    local sq = player:getCurrentSquare()
    if not sq then return end

    -- Repopulate registry once per player after load
    local pid = player:getOnlineID() or tostring(player)
    if not scannedPlayers[pid] then
        scannedPlayers[pid] = true
        scanNearbyTraps(player)
    end

    local key = sqKey(sq)

    if Zombas.get("EnableStakePit") and activePits[key] and Zombas.isArmed(sq) then
        triggerPit(sq, player)
    end
    if Zombas.get("EnableHoleTrap") and activeHoles[key] then
        triggerHole(sq, player)
    end

    local id = player:getOnlineID() or tostring(player)
    checkFenceCrossingForEntity(player, id)
end)

-- ─── Zombie / vehicle tick (only registered squares) ─────────────────────────
-- Much cheaper than a 49×49 area scan: iterates only squares with active traps
-- and squares adjacent to active fences.

local tickCount = 0
local TICK_RATE = 10

Events.OnTick.Add(function()
    tickCount = tickCount + 1
    if tickCount < TICK_RATE then return end
    tickCount = 0

    -- Pit trap: check zombies and vehicles on registered pit squares
    if Zombas.get("EnableStakePit") then
        for _, sq in pairs(activePits) do
            if Zombas.isArmed(sq) then
                local objs = sq:getMovingObjects()
                if objs then
                    for i = 0, objs:size() - 1 do
                        local e = objs:get(i)
                        if instanceof(e, "IsoZombie") then
                            triggerPit(sq, e)
                        elseif instanceof(e, "IsoVehicle") then
                            triggerVehicle(sq, e)
                        end
                    end
                end
            end
        end
    end

    -- Hole trap: check zombies on registered hole squares
    if Zombas.get("EnableHoleTrap") then
        for _, sq in pairs(activeHoles) do
            local objs = sq:getMovingObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    local e = objs:get(i)
                    if instanceof(e, "IsoZombie") then
                        triggerHole(sq, e)
                    end
                end
            end
        end
    end

    -- Fence crossing: only check zombies on the two squares flanking each fence
    if Zombas.get("EnableStakeFence") and not tableIsEmpty(activeFences) then
        -- Build set of squares to watch (both sides of every active fence)
        local watchSet = {}
        for _, data in pairs(activeFences) do
            local sq  = data.sq
            local fx, fy, fz = sq:getX(), sq:getY(), sq:getZ()
            local a, b
            if data.dir == "W" then
                a = getSquare(fx - 1, fy, fz)
                b = sq
            else  -- "N"
                a = getSquare(fx, fy - 1, fz)
                b = sq
            end
            if a then watchSet[sqKey(a)] = a end
            if b then watchSet[sqKey(b)] = b end
        end

        -- Check zombies on those squares only
        for _, wsq in pairs(watchSet) do
            local objs = wsq:getMovingObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    local zombie = objs:get(i)
                    if zombie and instanceof(zombie, "IsoZombie") and not zombie:isDead() then
                        local id = zombie:getOnlineID() or tostring(zombie)
                        checkFenceCrossingForEntity(zombie, id)
                    end
                end
            end
        end
    end
end)

-- ─── Client command handler ───────────────────────────────────────────────────

Events.OnClientCommand.Add(function(module, cmd, player, args)
    if module ~= "Zombas" then return end
    local sq = getSquare(args.x, args.y, args.z)
    if not sq then return end

    if cmd == "digPit" then
        if not Zombas.hasPit(sq) and not Zombas.hasHole(sq) then
            placePit(sq)
        end

    elseif cmd == "digHole" then
        if not Zombas.hasHole(sq) and not Zombas.hasPit(sq) and isDiggable(sq) then
            placeHole(sq)
        end

    elseif cmd == "addStake" then
        if Zombas.hasPit(sq) then
            local md = sq:getModData()
            local count = md[Zombas.MD.STAKES] or 0
            if count < Zombas.get("MAX_STAKES") and not md[Zombas.MD.CONCEALED] then
                md[Zombas.MD.STAKES] = count + 1
                Zombas.updatePitSprite(sq)

            end
        end

    elseif cmd == "concealPit" then
        if Zombas.hasPit(sq) and Zombas.isArmed(sq) and not Zombas.isConcealed(sq) then
            concealPit(sq)
        end

    elseif cmd == "disarmPit" then
        if Zombas.hasPit(sq) then
            disarmPit(player, sq)
        end

    elseif cmd == "placeFence" then
        if not Zombas.hasFence(sq) and isDiggable(sq) then
            local dir = args.dir
            if dir == "N" or dir == "W" then
                placeFence(sq, dir)
            end
        end

    elseif cmd == "disarmFence" then
        if Zombas.hasFence(sq) then
            disarmFence(player, sq)
        end
    end
end)
