require "ZombasTimedActions"

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function playerObj(playerNum)
    return getSpecificPlayer(playerNum)
end

local function squareOf(player)
    return player:getCurrentSquare()
end

local function inv(player)
    return player:getInventory()
end

local function has(player, itemType)
    return inv(player):containsTypeRecurse(itemType)
end

local function hasTool(player, ...)
    for _, t in ipairs({...}) do
        if inv(player):containsTypeRecurse(t) then return true end
    end
    return false
end

local function stakeCount(player)
    local items = inv(player):getItemsFromTypeRecurse("Zombas.WoodenStake")
    return items and items:size() or 0
end

local function label(key, ...)
    return getText(key, ...)
end

-- ─── Main context menu hook ──────────────────────────────────────────────────

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    local player = playerObj(playerNum)
    local sq     = squareOf(player)
    if not sq then return end

    local hasShovel = hasTool(player, "Base.Shovel", "Base.ShovelGardenTrowel")

    -- ── Stake Pit ────────────────────────────────────────────────────────────
    if Zombas.get("EnableStakePit") then
        if Zombas.hasPit(sq) then
            local md       = sq:getModData()
            local stakes   = md[Zombas.MD.STAKES] or 0
            local maxStakes = Zombas.get("MAX_STAKES")
            local concealed = Zombas.isConcealed(sq)

            -- Add stake
            if not concealed and stakes < maxStakes and has(player, "Zombas.WoodenStake") then
                context:addOption(
                    label("ContextMenu_Zombas_AddStake", stakes, maxStakes),
                    worldobjects,
                    function() ISTimedActionQueue.add(ISZombasAddStake:new(player, sq)) end
                )
            end

            -- Conceal
            if not concealed and Zombas.isArmed(sq) and has(player, "Base.Hay") then
                context:addOption(
                    label("ContextMenu_Zombas_Conceal"),
                    worldobjects,
                    function() ISTimedActionQueue.add(ISZombasConceal:new(player, sq)) end
                )
            end

            -- Disarm / fill
            if hasShovel then
                context:addOption(
                    label("ContextMenu_Zombas_DisarmPit"),
                    worldobjects,
                    function() ISTimedActionQueue.add(ISZombasDisarm:new(player, sq)) end
                )
            end

        else
            -- Dig stake pit (requires shovel, no existing pit/hole)
            if hasShovel and not Zombas.hasHole(sq) then
                context:addOption(
                    label("ContextMenu_Zombas_DigPit"),
                    worldobjects,
                    function() ISTimedActionQueue.add(ISZombasDigPit:new(player, sq)) end
                )
            end
        end
    end

    -- ── Hole Trap ────────────────────────────────────────────────────────────
    if Zombas.get("EnableHoleTrap") then
        if not Zombas.hasHole(sq) and not Zombas.hasPit(sq) then
            local str = player:getStr() or 0
            if hasTool(player, "Base.Shovel")
                and str >= Zombas.get("HOLE_STRENGTH_REQ")
                and Zombas.isDiggableSurface(sq)
            then
                context:addOption(
                    label("ContextMenu_Zombas_DigHole"),
                    worldobjects,
                    function() ISTimedActionQueue.add(ISZombasDigHole:new(player, sq)) end
                )
            end
        end
    end

    -- ── Stake Fence ──────────────────────────────────────────────────────────
    if Zombas.get("EnableStakeFence") then
        if Zombas.hasFence(sq) then
            context:addOption(
                label("ContextMenu_Zombas_DisarmFence"),
                worldobjects,
                function() ISTimedActionQueue.add(ISZombasDisarmFence:new(player, sq)) end
            )
        else
            local needed = Zombas.get("MAX_FENCE_STAKES")
            if stakeCount(player) >= needed and Zombas.isDiggableSurface(sq) then
                -- Submenu for direction
                local sub = context:getNew(context)
                context:addSubMenu(
                    context:addOption(label("ContextMenu_Zombas_PlaceFence"), worldobjects, nil),
                    sub
                )
                sub:addOption(
                    label("ContextMenu_Zombas_FenceNorth"),
                    worldobjects,
                    function() ISTimedActionQueue.add(ISZombasPlaceFence:new(player, sq, "N")) end
                )
                sub:addOption(
                    label("ContextMenu_Zombas_FenceWest"),
                    worldobjects,
                    function() ISTimedActionQueue.add(ISZombasPlaceFence:new(player, sq, "W")) end
                )
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
