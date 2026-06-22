-- ISTimedAction subclasses for all Zombas trap interactions.
-- Each action runs on the client (animation/time), then sends a
-- validated command to the server to apply world changes.

require "TimedActions/ISBaseTimedAction"

-- ─── Helpers ────────────────────────────────────────────────────────────────

local function sendCmd(player, cmd, sq)
    sendClientCommand(player, "Zombas", cmd, {
        x = sq:getX(), y = sq:getY(), z = sq:getZ()
    })
end

local function hasTool(player, ...)
    local inv = player:getInventory()
    for _, t in ipairs({...}) do
        if inv:containsTypeRecurse(t) then return true end
    end
    return false
end

local function hasItem(player, itemType)
    return player:getInventory():containsTypeRecurse(itemType)
end

-- ─── Dig Stake Pit ──────────────────────────────────────────────────────────

ISZombasDigPit = ISBaseTimedAction:derive("ISZombasDigPit")

function ISZombasDigPit:new(character, square)
    local o = ISBaseTimedAction.new(self, character)
    o.square      = square
    o.stopOnWalk  = true
    o.stopOnRun   = true
    o.maxTime     = 200
    return o
end

function ISZombasDigPit:isValid()
    return not Zombas.hasPit(self.square)
        and hasTool(self.character, "Base.Shovel", "Base.ShovelGardenTrowel")
end

function ISZombasDigPit:start()
    self:setAnimVariable("Digging", true)
end

function ISZombasDigPit:update()
    self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function ISZombasDigPit:perform()
    local shovel = self.character:getInventory():getFirstTypeRecurse("Base.Shovel")
        or self.character:getInventory():getFirstTypeRecurse("Base.ShovelGardenTrowel")
    if shovel then shovel:setCondition(shovel:getCondition() - 1) end
    sendCmd(self.character, "digPit", self.square)
    ISBaseTimedAction.perform(self)
end

function ISZombasDigPit:stop()
    self:setAnimVariable("Digging", false)
    ISBaseTimedAction.stop(self)
end

-- ─── Dig Hole Trap ──────────────────────────────────────────────────────────

ISZombasDigHole = ISBaseTimedAction:derive("ISZombasDigHole")

function ISZombasDigHole:new(character, square)
    local o = ISBaseTimedAction.new(self, character)
    o.square      = square
    o.stopOnWalk  = true
    o.stopOnRun   = true
    o.maxTime     = 500
    return o
end

function ISZombasDigHole:isValid()
    if Zombas.hasHole(self.square) then return false end
    if not hasTool(self.character, "Base.Shovel") then return false end
    if (self.character:getStr() or 0) < Zombas.get("HOLE_STRENGTH_REQ") then return false end
    if not Zombas.isDiggableSurface(self.square) then return false end
    return true
end

function ISZombasDigHole:start()
    self:setAnimVariable("Digging", true)
end

function ISZombasDigHole:update()
    self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function ISZombasDigHole:perform()
    local shovel = self.character:getInventory():getFirstTypeRecurse("Base.Shovel")
    if shovel then shovel:setCondition(shovel:getCondition() - 2) end
    sendCmd(self.character, "digHole", self.square)
    ISBaseTimedAction.perform(self)
end

function ISZombasDigHole:stop()
    self:setAnimVariable("Digging", false)
    ISBaseTimedAction.stop(self)
end

-- ─── Add Wooden Stake to Pit ─────────────────────────────────────────────────

ISZombasAddStake = ISBaseTimedAction:derive("ISZombasAddStake")

function ISZombasAddStake:new(character, square)
    local o = ISBaseTimedAction.new(self, character)
    o.square     = square
    o.stopOnWalk = true
    o.maxTime    = 50
    return o
end

function ISZombasAddStake:isValid()
    if not Zombas.hasPit(self.square) then return false end
    local md = self.square:getModData()
    if (md[Zombas.MD.STAKES] or 0) >= Zombas.get("MAX_STAKES") then return false end
    if md[Zombas.MD.CONCEALED] then return false end
    return hasItem(self.character, "Zombas.WoodenStake")
end

function ISZombasAddStake:perform()
    local stake = self.character:getInventory():getFirstTypeRecurse("Zombas.WoodenStake")
    if stake then self.character:getInventory():Remove(stake) end
    sendCmd(self.character, "addStake", self.square)
    ISBaseTimedAction.perform(self)
end

-- ─── Conceal Pit with Hay ────────────────────────────────────────────────────

ISZombasConceal = ISBaseTimedAction:derive("ISZombasConceal")

function ISZombasConceal:new(character, square)
    local o = ISBaseTimedAction.new(self, character)
    o.square     = square
    o.stopOnWalk = true
    o.maxTime    = 60
    return o
end

function ISZombasConceal:isValid()
    return Zombas.isArmed(self.square)
        and not Zombas.isConcealed(self.square)
        and hasItem(self.character, "Base.Hay")
end

function ISZombasConceal:perform()
    local hay = self.character:getInventory():getFirstTypeRecurse("Base.Hay")
    if hay then self.character:getInventory():Remove(hay) end
    sendCmd(self.character, "concealPit", self.square)
    ISBaseTimedAction.perform(self)
end

-- ─── Disarm / Fill Pit ──────────────────────────────────────────────────────

ISZombasDisarm = ISBaseTimedAction:derive("ISZombasDisarm")

function ISZombasDisarm:new(character, square)
    local o = ISBaseTimedAction.new(self, character)
    o.square     = square
    o.stopOnWalk = true
    o.maxTime    = 200
    return o
end

function ISZombasDisarm:isValid()
    return Zombas.hasPit(self.square)
        and hasTool(self.character, "Base.Shovel", "Base.ShovelGardenTrowel")
end

function ISZombasDisarm:start()
    self:setAnimVariable("Digging", true)
end

function ISZombasDisarm:perform()
    sendCmd(self.character, "disarmPit", self.square)
    ISBaseTimedAction.perform(self)
end

function ISZombasDisarm:stop()
    self:setAnimVariable("Digging", false)
    ISBaseTimedAction.stop(self)
end

-- ─── Place Stake Fence ───────────────────────────────────────────────────────

ISZombasPlaceFence = ISBaseTimedAction:derive("ISZombasPlaceFence")

function ISZombasPlaceFence:new(character, square, dir)
    local o = ISBaseTimedAction.new(self, character)
    o.square     = square
    o.dir        = dir   -- "N" or "W"
    o.stopOnWalk = true
    o.maxTime    = 120
    return o
end

function ISZombasPlaceFence:isValid()
    if Zombas.hasFence(self.square) then return false end
    if not Zombas.isDiggableSurface(self.square) then return false end
    local inv = self.character:getInventory()
    local count = 0
    local items = inv:getItemsFromTypeRecurse("Zombas.WoodenStake")
    if items then count = items:size() end
    return count >= Zombas.get("MAX_FENCE_STAKES")
end

function ISZombasPlaceFence:perform()
    -- Consume 5 stakes
    local inv = self.character:getInventory()
    local needed = Zombas.get("MAX_FENCE_STAKES")
    local removed = 0
    local items = inv:getItemsFromTypeRecurse("Zombas.WoodenStake")
    if items then
        for i = 0, items:size() - 1 do
            if removed >= needed then break end
            inv:Remove(items:get(i))
            removed = removed + 1
        end
    end
    sendClientCommand(self.character, "Zombas", "placeFence", {
        x   = self.square:getX(),
        y   = self.square:getY(),
        z   = self.square:getZ(),
        dir = self.dir,
    })
    ISBaseTimedAction.perform(self)
end

-- ─── Disarm Stake Fence ──────────────────────────────────────────────────────

ISZombasDisarmFence = ISBaseTimedAction:derive("ISZombasDisarmFence")

function ISZombasDisarmFence:new(character, square)
    local o = ISBaseTimedAction.new(self, character)
    o.square     = square
    o.stopOnWalk = true
    o.maxTime    = 80
    return o
end

function ISZombasDisarmFence:isValid()
    return Zombas.hasFence(self.square)
end

function ISZombasDisarmFence:perform()
    sendCmd(self.character, "disarmFence", self.square)
    ISBaseTimedAction.perform(self)
end
