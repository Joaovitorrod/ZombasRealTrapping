-- Mod Options integration for B42.
-- Uses PZAPI ModOptions if available; falls back to Zombas.Config defaults.

Zombas = Zombas or {}
Zombas.Options = Zombas.Options or {}

local MOD_ID = "Zombas_TrapStructures"

-- Option definitions: key, type, default, min, max, label
local OPTION_DEFS = {
    -- Feature toggles
    { key="EnableStakePit",     type="boolean", label="Enable Stake Pit Trap" },
    { key="EnableHoleTrap",     type="boolean", label="Enable Hole Trap" },
    { key="EnableStakeFence",   type="boolean", label="Enable Stake Fence" },

    -- Stake Pit
    { key="DAMAGE_MIN",         type="integer", min=1,  max=100,  label="Stake Pit: Min Damage" },
    { key="DAMAGE_MAX",         type="integer", min=1,  max=200,  label="Stake Pit: Max Damage" },
    { key="CRIT_CHANCE",        type="integer", min=0,  max=100,  label="Stake Pit: Crit Chance (%)" },
    { key="STAKE_BREAK_CHANCE", type="integer", min=0,  max=100,  label="Stake Pit: Stake Break Chance (%)" },

    -- Vehicle
    { key="VEH_DAMAGE_MIN",     type="integer", min=1,  max=100,  label="Vehicle: Min Tire Damage" },
    { key="VEH_DAMAGE_MAX",     type="integer", min=1,  max=100,  label="Vehicle: Max Tire Damage" },
    { key="VEH_CRIT_CHANCE",    type="integer", min=0,  max=100,  label="Vehicle: Blowout Chance (%)" },

    -- Hole Trap
    { key="MaxHoleZombies",     type="integer", min=0,  max=100,  label="Hole Trap: Max Zombies (0=unlimited)" },

    -- Stake Fence
    { key="FENCE_DAMAGE_MIN",   type="integer", min=1,  max=100,  label="Stake Fence: Min Damage" },
    { key="FENCE_DAMAGE_MAX",   type="integer", min=1,  max=200,  label="Stake Fence: Max Damage" },
    { key="FENCE_CRIT_CHANCE",  type="integer", min=0,  max=100,  label="Stake Fence: Crit Chance (%)" },
}

-- Cached resolved values (populated on init)
local resolved = {}

local function resolveAll(optInst)
    for _, def in ipairs(OPTION_DEFS) do
        local v = nil
        if optInst then
            local opt = optInst:getOption(def.key)
            if opt then v = opt:getValue() end
        end
        if v == nil then v = Zombas.Config[def.key] end
        resolved[def.key] = v
    end
end

-- Public getter used by all other modules
function Zombas.Options.get(key)
    if resolved[key] ~= nil then return resolved[key] end
    return Zombas.Config[key]
end

-- Re-read all values (called after player changes options)
function Zombas.Options.reload()
    local ok, ModOptions = pcall(require, "ModOptions")
    local inst = (ok and ModOptions) and ModOptions:getInstance(MOD_ID) or nil
    resolveAll(inst)
end

local function tryRegisterModOptions()
    local ok, ModOptions = pcall(require, "ModOptions")
    if not ok or not ModOptions then
        -- ModOptions API not present; use defaults
        resolveAll(nil)
        return
    end

    local inst = ModOptions:getInstance(MOD_ID)
    inst:setName("Zombas - Trap Structures")

    for _, def in ipairs(OPTION_DEFS) do
        local default = Zombas.Config[def.key]
        if def.type == "boolean" then
            inst:addToggle(def.key, default, def.label)
        elseif def.type == "integer" then
            inst:addSlider(def.key, def.min, def.max, default, def.label)
        end
    end

    inst:addCallback(function() Zombas.Options.reload() end)
    resolveAll(inst)
end

-- Server sync: server broadcasts its config to joining clients
-- so damage is always calculated with host values in MP.
if isServer() then
    Events.OnClientCommand.Add(function(module, cmd, player, args)
        if module ~= "Zombas" or cmd ~= "requestConfig" then return end
        local cfg = {}
        for _, def in ipairs(OPTION_DEFS) do
            cfg[def.key] = Zombas.Options.get(def.key)
        end
        sendServerCommand(player, "Zombas", "syncConfig", cfg)
    end)
end

if isClient() then
    Events.OnServerCommand.Add(function(module, cmd, args)
        if module ~= "Zombas" or cmd ~= "syncConfig" then return end
        for k, v in pairs(args) do
            resolved[k] = v
        end
    end)

    Events.OnGameStart.Add(function()
        tryRegisterModOptions()
        -- Request server config on join (MP); in SP this is a no-op since
        -- client == server and resolved values are already set.
        sendClientCommand("Zombas", "requestConfig", {})
    end)
else
    -- Non-client context (server-only startup or SP)
    Events.OnGameStart.Add(function()
        tryRegisterModOptions()
    end)
end
