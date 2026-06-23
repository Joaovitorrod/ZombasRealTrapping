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

local function setAnim(self, name, value)
    if self.character and self.character.setAnimVariable then
        self.character:setAnimVariable(name, value)
    end
end

local function setMetabolic(character)
    if Metabolics and Metabolics.HeavyWork then
        character:setMetabolicTarget(Metabolics.HeavyWork)
    end
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
end

function ISZombasDigPit:start()
    setAnim(self, "Digging", true)
end

function ISZombasDigPit:update()
    setMetabolic(self.character)
end

function ISZombasDigPit:perform()
    local shovel = self.character:getInventory():getFirstTypeRecurse("Base.Shovel")
        or self.character:getInventory():getFirstTypeRecurse("Base.ShovelGardenTrowel")
    if shovel then shovel:setCondition(shovel:getCondition() - 1) end
    sendCmd(self.character, "digPit", self.square)
    ISBaseTimedAction.perform(self)
end

function ISZombasDigPit:stop()
    setAnim(self, "Digging", false)
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
    if not Zombas.isDiggableSurface(self.square) then return false end
    return true
end

function ISZombasDigHole:start()
    setAnim(self, "Digging", true)
end

function ISZombasDigHole:update()
    setMetabolic(self.character)
end

function ISZombasDigHole:perform()
    local shovel = self.character:getInventory():getFirstTypeRecurse("Base.Shovel")
    if shovel then shovel:setCondition(shovel:getCondition() - 2) end
    sendCmd(self.character, "digHole", self.square)
    ISBaseTimedAction.perform(self)
end

function ISZombasDigHole:stop()
    setAnim(self, "Digging", false)
    ISBaseTimedAction.stop(self)
end

-- ─── Add Spear to Pit ───────────────────────────────────────────────────────

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
    return Zombas.countSpears(self.character:getInventory()) > 0
end

function ISZombasAddStake:perform()
    Zombas.removeSpears(self.character:getInventory(), 1)
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
end

function ISZombasDisarm:start()
    setAnim(self, "Digging", true)
end

function ISZombasDisarm:perform()
    sendCmd(self.character, "disarmPit", self.square)
    ISBaseTimedAction.perform(self)
end

function ISZombasDisarm:stop()
    setAnim(self, "Digging", false)
    ISBaseTimedAction.stop(self)
end

-- ─── Place Stake Fence ───────────────────────────────────────────────────────

ISZombasPlaceFence = ISBaseTimedAction:derive("ISZombasPlaceFence")

function ISZombasPlaceFence:new(character, square, dir)
    local o = ISBaseTimedAction.new(self, character)
    o.square     = square
    o.dir        = dir
    o.stopOnWalk = true
    o.maxTime    = 120
    return o
end

function ISZombasPlaceFence:isValid()
    if Zombas.hasFence(self.square) then return false end
    if not Zombas.isDiggableSurface(self.square) then return false end
    return Zombas.countSpears(self.character:getInventory()) >= Zombas.get("MAX_FENCE_STAKES")
end

function ISZombasPlaceFence:perform()
    Zombas.removeSpears(self.character:getInventory(), Zombas.get("MAX_FENCE_STAKES"))
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
