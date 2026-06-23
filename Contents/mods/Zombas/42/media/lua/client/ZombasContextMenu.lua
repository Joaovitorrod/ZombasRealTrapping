print("[RealTrapZ] ZombasContextMenu.lua loading...")

-- B42: callbacks must be named functions, not inline lambdas

local function doDigPit(player, sq)
    ISTimedActionQueue.add(ISZombasDigPit:new(player, sq))
end

local function doDigHole(player, sq)
    ISTimedActionQueue.add(ISZombasDigHole:new(player, sq))
end

local function doAddStake(player, sq)
    ISTimedActionQueue.add(ISZombasAddStake:new(player, sq))
end

local function doConceal(player, sq)
    ISTimedActionQueue.add(ISZombasConceal:new(player, sq))
end

local function doDisarmPit(player, sq)
    ISTimedActionQueue.add(ISZombasDisarm:new(player, sq))
end

local function doPlaceFenceN(player, sq)
    ISTimedActionQueue.add(ISZombasPlaceFence:new(player, sq, "N"))
end

local function doPlaceFenceW(player, sq)
    ISTimedActionQueue.add(ISZombasPlaceFence:new(player, sq, "W"))
end

local function doDisarmFence(player, sq)
    ISTimedActionQueue.add(ISZombasDisarmFence:new(player, sq))
end

Events.OnPreFillWorldObjectContextMenu.Add(function(playerNum, context, worldObjects, test)
    if test then return end

    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local sq = player:getCurrentSquare()
    if not sq then return end

    local playerInv   = player:getInventory()
    local spearCount  = Zombas.countSpears(playerInv)
    local pitEnabled  = Zombas.get("EnableStakePit")
    local holeEnabled = Zombas.get("EnableHoleTrap")

    -- ── Dig Trap submenu (Stake Pit + Hole Trap) ──────────────────────────────
    if pitEnabled or holeEnabled then
        local digItems = {}

        if pitEnabled then
            if Zombas.hasPit(sq) then
                local md        = sq:getModData()
                local stakes    = md[Zombas.MD.STAKES]    or 0
                local maxStakes = Zombas.get("MAX_STAKES") or 4
                local concealed = Zombas.isConcealed(sq)
                if not concealed and stakes < maxStakes and spearCount > 0 then
                    digItems[#digItems+1] = { text = getText("ContextMenu_Zombas_AddStake", stakes, maxStakes), fn = doAddStake }
                end
                if not concealed and Zombas.isArmed(sq) and playerInv:containsTypeRecurse("Base.Hay") then
                    digItems[#digItems+1] = { text = getText("ContextMenu_Zombas_Conceal"), fn = doConceal }
                end
                digItems[#digItems+1] = { text = getText("ContextMenu_Zombas_DisarmPit"), fn = doDisarmPit }
            elseif not Zombas.hasHole(sq) then
                digItems[#digItems+1] = { text = getText("ContextMenu_Zombas_DigPit"), fn = doDigPit }
            end
        end

        if holeEnabled and not Zombas.hasHole(sq) and not Zombas.hasPit(sq) then
            local str = player:getPerkLevel(Perks.Strength) or 0
            if str >= (Zombas.get("HOLE_STRENGTH_REQ") or 4) and Zombas.isDiggableSurface(sq) then
                digItems[#digItems+1] = { text = getText("ContextMenu_Zombas_DigHole"), fn = doDigHole }
            end
        end

        if #digItems > 0 then
            local digSub    = context:getNew(context)
            local digParent = context:addOption(getText("ContextMenu_Zombas_DigTrap"), worldObjects, nil)
            context:addSubMenu(digParent, digSub)
            for _, item in ipairs(digItems) do
                digSub:addOption(item.text, player, item.fn, sq)
            end
        end
    end

    -- ── Stake Fence ───────────────────────────────────────────────────────────
    if Zombas.get("EnableStakeFence") then
        if Zombas.hasFence(sq) then
            context:addOption(getText("ContextMenu_Zombas_DisarmFence"), player, doDisarmFence, sq)
        elseif spearCount >= (Zombas.get("MAX_FENCE_STAKES") or 5) and Zombas.isDiggableSurface(sq) then
            local fenceSub    = context:getNew(context)
            local fenceParent = context:addOption(getText("ContextMenu_Zombas_PlaceFence"), worldObjects, nil)
            context:addSubMenu(fenceParent, fenceSub)
            fenceSub:addOption(getText("ContextMenu_Zombas_FenceNorth"), player, doPlaceFenceN, sq)
            fenceSub:addOption(getText("ContextMenu_Zombas_FenceWest"),  player, doPlaceFenceW, sq)
        end
    end
end)

print("[RealTrapZ] ZombasContextMenu.lua done")
