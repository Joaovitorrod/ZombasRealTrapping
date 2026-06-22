-- Server-side trap logic: placement, trigger checks, damage, vehicle handling,
-- hole chamber generation, stake fence crossing detection.

-- ─── Utilities ───────────────────────────────────────────────────────────────

local function getSquare(x, y, z)
    return getCell():getGridSquare(x, y, z)
end

local function addTrapObject(square, spriteName, tag)
    local sprite = getSprite(spriteName)
    if not sprite then return nil end
    local obj = IsoObject.new(square:getCell(), square, sprite)
    obj:setIsThumpable(false)
    obj:setSolid(false)
    obj:getModData()["Zombas.tag"] = tag
    square:AddSpecialObject(obj)
    square:RecalcProperties()
    square:RecalcAllWithNeighbours(true)
    return obj
end

local function removeTrapObject(square, tag)
    local obj = Zombas.getTrapObject(square, tag)
    if not obj then return end
    square:RemoveSpecialObject(obj)
    square:RecalcProperties()
    square:RecalcAllWithNeighbours(true)
end

local function giveItem(character, fullType)
    local item = InventoryItemFactory.CreateItem(fullType)
    if item and character then
        character:getInventory():AddItem(item)
    end
end

-- ─── Valid dig surface list (mirrors Zombas.ValidDigSurfaces) ────────────────

local function isDiggable(square)
    return Zombas.isDiggableSurface(square)
end

-- ─── Stake Pit ───────────────────────────────────────────────────────────────

local function placePit(square)
    local md = square:getModData()
    md[Zombas.MD.HAS_PIT]   = true
    md[Zombas.MD.STAKES]     = 0
    md[Zombas.MD.CONCEALED]  = false
    md[Zombas.MD.COOLDOWN]   = 0
    addTrapObject(square, Zombas.Sprites.PIT_EMPTY, "pit")
    square:transmitModData()
end

local function concealPit(square)
    local md    = square:getModData()
    local floor = square:getFloor()
    if floor and floor:getSprite() then
        md[Zombas.MD.ORIGINAL_FLOOR] = floor:getSprite():getName()
    end
    md[Zombas.MD.CONCEALED] = true
    -- Replace floor tile with native hay tile
    local haySprite = getSprite("floors_interior_tilesandstone2_8")
    if haySprite and floor then
        floor:setTile(haySprite)
    end
    -- Hide the pit IsoObject while concealed
    local obj = Zombas.getTrapObject(square, "pit")
    if obj then obj:setVisible(false) end
    square:transmitModData()
end

local function revealPit(square)
    local md    = square:getModData()
    local floor = square:getFloor()
    -- Restore original floor tile
    if floor and md[Zombas.MD.ORIGINAL_FLOOR] then
        local orig = getSprite(md[Zombas.MD.ORIGINAL_FLOOR])
        if orig then floor:setTile(orig) end
        md[Zombas.MD.ORIGINAL_FLOOR] = nil
    end
    md[Zombas.MD.CONCEALED] = false
    local obj = Zombas.getTrapObject(square, "pit")
    if obj then obj:setVisible(true) end
    Zombas.updatePitSprite(square)
    square:transmitModData()
end

local function disarmPit(character, square)
    local md     = square:getModData()
    local stakes = md[Zombas.MD.STAKES] or 0
    -- Return surviving stakes to player
    for _ = 1, stakes do giveItem(character, "Zombas.WoodenStake") end
    -- Restore floor if concealed
    if md[Zombas.MD.CONCEALED] then revealPit(square) end
    removeTrapObject(square, "pit")
    md[Zombas.MD.HAS_PIT]  = nil
    md[Zombas.MD.STAKES]   = nil
    md[Zombas.MD.CONCEALED] = nil
    md[Zombas.MD.COOLDOWN]  = nil
    square:transmitModData()
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
        square:transmitModData()
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
    square:transmitModData()
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

    local dmg    = Zombas.get("VEH_DAMAGE_MIN") + ZombRand(
        Zombas.get("VEH_DAMAGE_MAX") - Zombas.get("VEH_DAMAGE_MIN") + 1)
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
    square:transmitModData()
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
        if f then f:setTile(floorSpr) end
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
            if not hasWall then
                local wall = IsoObject.new(n.sq:getCell(), n.sq, wallSpr)
                wall:setSolid(true)
                wall:getModData()["Zombas.tag"] = "holeWall"
                n.sq:AddSpecialObject(wall)
                n.sq:RecalcProperties()
            end
        end
    end
end

local function placeHole(square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local below    = getSquare(x, y, z - 1)
    local needGen  = not below or not below:getFloor() or below:getFloor():getSprite() == nil

    if needGen then generateChamber(x, y, z - 1) end

    local md = square:getModData()
    md[Zombas.MD.HAS_HOLE]       = true
    md[Zombas.MD.HOLE_GENERATED] = needGen

    addTrapObject(square, Zombas.Sprites.HOLE, "hole")
    square:transmitModData()
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
    square:transmitModData()
end

local function disarmFence(character, square)
    local md     = square:getModData()
    local stakes = md[Zombas.MD.FENCE_STAKES] or 0
    for _ = 1, stakes do giveItem(character, "Zombas.WoodenStake") end
    removeTrapObject(square, "fence")
    md[Zombas.MD.HAS_FENCE]     = nil
    md[Zombas.MD.FENCE_DIR]     = nil
    md[Zombas.MD.FENCE_STAKES]  = nil
    md[Zombas.MD.FENCE_COOLDOWN] = nil
    square:transmitModData()
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
        square:transmitModData()
    end
end

local function triggerFence(square, entity)
    local md = square:getModData()
    if not md[Zombas.MD.HAS_FENCE] then return end

    local now = getTimestamp()
    if now < (md[Zombas.MD.FENCE_COOLDOWN] or 0) then return end

    local dMin = Zombas.get("FENCE_DAMAGE_MIN")
    local dMax = Zombas.get("FENCE_DAMAGE_MAX")
    local dmg  = dMin + ZombRand(dMax - dMin + 1)

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
    square:transmitModData()
end

-- ─── Tick: check pits and holes near players ─────────────────────────────────

local tickCount   = 0
local TICK_RATE   = 30
-- prevPos tracks zombie previous square for fence crossing detection
local prevPos     = {}

local function checkArea()
    local players = IsoPlayer.getPlayers()
    for pi = 0, players:size() - 1 do
        local player = players:get(pi)
        local px = math.floor(player:getX())
        local py = math.floor(player:getY())
        local pz = math.floor(player:getZ())

        for dx = -24, 24 do
            for dy = -24, 24 do
                local sq = getSquare(px + dx, py + dy, pz)
                if sq then
                    -- Stake Pit
                    if Zombas.get("EnableStakePit") and Zombas.hasPit(sq) and Zombas.isArmed(sq) then
                        local objs = sq:getMovingObjects()
                        if objs then
                            for i = 0, objs:size() - 1 do
                                local e = objs:get(i)
                                if instanceof(e, "IsoZombie") or instanceof(e, "IsoPlayer") then
                                    triggerPit(sq, e)
                                elseif instanceof(e, "IsoVehicle") then
                                    triggerVehicle(sq, e)
                                end
                            end
                        end
                    end

                    -- Hole Trap
                    if Zombas.get("EnableHoleTrap") and Zombas.hasHole(sq) then
                        local objs = sq:getMovingObjects()
                        if objs then
                            for i = 0, objs:size() - 1 do
                                local e = objs:get(i)
                                if instanceof(e, "IsoZombie") or instanceof(e, "IsoPlayer") then
                                    triggerHole(sq, e)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Fence crossing: compare zombie current square vs previous each tick
local function checkFenceCrossings()
    if not Zombas.get("EnableStakeFence") then return end
    local cell = getCell()
    local zList = cell:getZombieList()
    if not zList then return end

    for i = 0, zList:size() - 1 do
        local zombie = zList:get(i)
        if zombie and not zombie:isDead() then
            local id  = zombie:getOnlineID() or i
            local cx  = math.floor(zombie:getX())
            local cy  = math.floor(zombie:getY())
            local cz  = math.floor(zombie:getZ())
            local prev = prevPos[id]

            if prev and (cx ~= prev.x or cy ~= prev.y) then
                local dx = cx - prev.x
                local dy = cy - prev.y

                if math.abs(dx) == 1 and dy == 0 then
                    -- East/West movement — check W face
                    local fenceSq = dx > 0
                        and getSquare(cx, cy, cz)   -- moving E: W face of dest
                        or  getSquare(prev.x, prev.y, prev.z) -- moving W: W face of origin
                    if fenceSq and Zombas.hasFence(fenceSq)
                        and Zombas.getFenceDir(fenceSq) == "W"
                    then
                        triggerFence(fenceSq, zombie)
                    end
                elseif dx == 0 and math.abs(dy) == 1 then
                    -- North/South movement — check N face
                    local fenceSq = dy > 0
                        and getSquare(cx, cy, cz)
                        or  getSquare(prev.x, prev.y, prev.z)
                    if fenceSq and Zombas.hasFence(fenceSq)
                        and Zombas.getFenceDir(fenceSq) == "N"
                    then
                        triggerFence(fenceSq, zombie)
                    end
                end
            end

            prevPos[id] = { x = cx, y = cy, z = cz }
        end
    end
end

Events.OnTick.Add(function()
    tickCount = tickCount + 1
    if tickCount < TICK_RATE then return end
    tickCount = 0
    checkArea()
    checkFenceCrossings()
end)

-- ─── Client command handler ───────────────────────────────────────────────────

Events.OnClientCommand.Add(function(module, cmd, player, args)
    if module ~= "Zombas" then return end
    local sq = getSquare(args.x, args.y, args.z)
    if not sq then return end

    if cmd == "digPit" then
        if not Zombas.hasPit(sq) and not Zombas.hasHole(sq)
            and player:getInventory():containsTypeRecurse("Base.Shovel")
        then
            placePit(sq)
        end

    elseif cmd == "digHole" then
        if not Zombas.hasHole(sq) and not Zombas.hasPit(sq)
            and player:getInventory():containsTypeRecurse("Base.Shovel")
            and (player:getStr() or 0) >= Zombas.get("HOLE_STRENGTH_REQ")
            and isDiggable(sq)
        then
            placeHole(sq)
        end

    elseif cmd == "addStake" then
        if Zombas.hasPit(sq) then
            local md = sq:getModData()
            local count = md[Zombas.MD.STAKES] or 0
            if count < Zombas.get("MAX_STAKES") and not md[Zombas.MD.CONCEALED] then
                md[Zombas.MD.STAKES] = count + 1
                Zombas.updatePitSprite(sq)
                sq:transmitModData()
            end
        end

    elseif cmd == "concealPit" then
        if Zombas.hasPit(sq) and Zombas.isArmed(sq) and not Zombas.isConcealed(sq) then
            concealPit(sq)
        end

    elseif cmd == "disarmPit" then
        if Zombas.hasPit(sq)
            and player:getInventory():containsTypeRecurse("Base.Shovel")
        then
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
