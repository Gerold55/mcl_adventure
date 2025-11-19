-- mcl_adventure/init.lua
-- Minecraft-style Adventure mode for Mineclonia

local storage = minetest.get_mod_storage()

-- Per-player adventure state
local adventure_players   = {}  -- [name] = true/false
local old_creative_state  = {}  -- [name] = true if they had creative before Adventure
local adventure_spawn_pos = {}  -- [name] = pos table (cached from storage)

mcl_adventure = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function get_name(p)
    if type(p) == "string" then
        return p
    elseif p and p.is_player and p:is_player() then
        return p:get_player_name()
    end
end

local function get_setting_bool(name, default)
    -- wrapper for cleaner code
    return minetest.settings:get_bool(name, default)
end

local function get_spawn(name)
    if adventure_spawn_pos[name] then
        return adventure_spawn_pos[name]
    end
    local s = storage:get_string("spawn:" .. name)
    if s == "" then return nil end
    local pos = minetest.string_to_pos(s)
    adventure_spawn_pos[name] = pos
    return pos
end

local function set_spawn(name, pos)
    adventure_spawn_pos[name] = pos
    storage:set_string("spawn:" .. name, minetest.pos_to_string(pos))
end

----------------------------------------------------------------------
-- Load/save state
----------------------------------------------------------------------

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local key  = "player:" .. name
    local stored = storage:get_string(key)

    if stored == "" then
        -- First join: use world setting
        local default_on = get_setting_bool("mcl_adventure_default", false)
        adventure_players[name] = default_on
        storage:set_string(key, default_on and "1" or "0")
    else
        adventure_players[name] = (stored == "1")
    end

    -- If joining already in Adventure mode → remove creative priv
    if adventure_players[name] then
        local privs = minetest.get_player_privs(name)
        if privs.creative then
            old_creative_state[name] = true
            privs.creative = nil
            minetest.set_player_privs(name, privs)
        end
    end

    -- Cache spawn if any
    get_spawn(name)
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    storage:set_string("player:" .. name, adventure_players[name] and "1" or "0")
end)

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function mcl_adventure.is_adventure(p)
    local name = get_name(p)
    if not name then return false end
    return adventure_players[name] or false
end

function mcl_adventure.set_adventure(p, enabled)
    local name = get_name(p)
    if not name then return end

    adventure_players[name] = not not enabled
    storage:set_string("player:" .. name, enabled and "1" or "0")

    local player = minetest.get_player_by_name(name)
    local privs  = minetest.get_player_privs(name)

    if enabled then
        -- Temporarily remove creative if present to avoid instant-dig ghosting
        if privs.creative then
            old_creative_state[name] = true
            privs.creative = nil
            minetest.set_player_privs(name, privs)
        end

        if player then
            minetest.chat_send_player(name, minetest.colorize("#55FF55",
                "[Adventure] Adventure mode enabled. "
                .. "Blocks are protected; tools can only break whitelisted blocks."))
        end
    else
        -- Restore creative if they had it before
        if old_creative_state[name] then
            privs.creative = true
            old_creative_state[name] = nil
            minetest.set_player_privs(name, privs)
        end

        if player then
            minetest.chat_send_player(name, minetest.colorize("#FF5555",
                "[Adventure] Adventure mode disabled."))
        end
    end
end

----------------------------------------------------------------------
-- Priv + Command
----------------------------------------------------------------------

minetest.register_privilege("adventure_admin", {
    description = "Can change Adventure mode and related settings for others",
    give_to_singleplayer = true,
})

-- /adventure [on|off|toggle] [player]
minetest.register_chatcommand("adventure", {
    params = "[on|off|toggle] [player]",
    description = "Toggle or set Adventure mode for a player",
    privs = { interact = true },
    func = function(name, param)
        local args = {}
        for w in param:gmatch("%S+") do args[#args + 1] = w end

        local mode   = args[1]
        local target = args[2] or name

        if target ~= name and
           not minetest.check_player_privs(name, { adventure_admin = true }) then
            return false, "You need the 'adventure_admin' privilege to modify others."
        end

        local current = mcl_adventure.is_adventure(target)

        if mode == "on" then
            if current then return true, target .. " is already in Adventure mode." end
            mcl_adventure.set_adventure(target, true)
            return true, target .. " is now in Adventure mode."

        elseif mode == "off" then
            if not current then return true, target .. " is not in Adventure mode." end
            mcl_adventure.set_adventure(target, false)
            return true, target .. " left Adventure mode."

        else
            -- toggle
            mcl_adventure.set_adventure(target, not current)
            return true, "Adventure mode for " .. target .. " is now "
                .. (not current and "ON" or "OFF") .. "."
        end
    end,
})

----------------------------------------------------------------------
-- Custom spawn command: /advspawn [player]
-- Sets Adventure spawn as if sleeping in a bed, but anytime.
----------------------------------------------------------------------

minetest.register_chatcommand("advspawn", {
    params = "[player]",
    description = "Set Adventure spawn point to your current position (like a bed)",
    privs = { interact = true },
    func = function(name, param)
        if not get_setting_bool("mcl_adventure_allow_custom_spawn", true) then
            return false, "[Adventure] Custom spawn is disabled in settings."
        end

        local target = param ~= "" and param or name

        if target ~= name and
           not minetest.check_player_privs(name, { adventure_admin = true }) then
            return false, "You need 'adventure_admin' to set spawn for others."
        end

        local player = minetest.get_player_by_name(target)
        if not player then
            return false, "Target player not found."
        end

        local pos = vector.round(player:get_pos())
        set_spawn(target, pos)

        return true, "Adventure spawn for " .. target
            .. " set to " .. minetest.pos_to_string(pos) .. "."
    end,
})

-- Respawn hook: send Adventure players to their custom spawn (if enabled)
minetest.register_on_respawnplayer(function(player)
    if not get_setting_bool("mcl_adventure_allow_custom_spawn", true) then
        return false -- let engine handle
    end

    local name = player:get_player_name()
    if not mcl_adventure.is_adventure(name) then
        return false
    end

    local pos = get_spawn(name)
    if not pos then
        return false -- no custom spawn, let default handle
    end

    player:set_pos(pos)
    return true
end)

----------------------------------------------------------------------
-- Tool whitelist logic (CanDestroy-style)
-- Tools must define:
--    adventure_can_break = { "mcl_core:cobble", "group:stone", ... }
-- to be able to break those nodes in Adventure.
----------------------------------------------------------------------

local function can_tool_break_node(node, toolstack)
    if toolstack:is_empty() then
        return false
    end

    local def = toolstack:get_definition()
    if not def or not def.adventure_can_break then
        return false
    end

    local entries = def.adventure_can_break
    for _, entry in ipairs(entries) do
        if entry:sub(1, 6) == "group:" then
            local group = entry:sub(7)
            if minetest.get_item_group(node.name, group) > 0 then
                return true
            end
        else
            -- exact node name
            if entry == node.name then
                return true
            end
        end
    end

    return false
end

----------------------------------------------------------------------
-- Placement whitelist logic (CanPlaceOn-style)
-- Nodes must define:
--    adventure_can_place = true
-- to be placeable in Adventure when restriction is enabled.
----------------------------------------------------------------------

local function can_place_item(itemstack)
    if itemstack:is_empty() then
        return false
    end

    local def = itemstack:get_definition()
    if not def then
        return false
    end

    -- Only restrict node placement; items (food, tools, buckets) still usable.
    if def.type ~= "node" then
        return true
    end

    return def.adventure_can_place == true
end

----------------------------------------------------------------------
-- Dig/place hooks
--  * Blocks cannot be broken unless tool is allowed (strict mode).
--  * Crops can optionally be allowed.
--  * Placement is optionally restricted.
----------------------------------------------------------------------

local old_node_dig   = minetest.node_dig
local old_item_place = minetest.item_place

function minetest.node_dig(pos, node, digger)
    if digger and digger:is_player() and mcl_adventure.is_adventure(digger) then
        local strict = get_setting_bool("mcl_adventure_strict_breaking", true)
        local allow_crops = get_setting_bool("mcl_adventure_allow_crop_harvest", false)

        -- If strict breaking is OFF: let tools work normally in Adventure.
        if not strict then
            return old_node_dig(pos, node, digger)
        end

        local tool = digger:get_wielded_item()

        -- If tool explicitly allowed to break this node: allow.
        if can_tool_break_node(node, tool) then
            return old_node_dig(pos, node, digger)
        end

        -- Optional: allow harvesting plants/crops even in Adventure.
        if allow_crops then
            local def = minetest.registered_nodes[node.name]
            if def and def.groups then
                local g = def.groups
                if (g.plant and g.plant > 0)
                or (g.flora and g.flora > 0)
                or (g.crop and g.crop > 0) then
                    return old_node_dig(pos, node, digger)
                end
            end
        end

        -- Otherwise: fully block block breaking.
        local pname = digger:get_player_name()
        if pname and pname ~= "" then
            minetest.chat_send_player(pname, minetest.colorize("#FFAA00",
                "[Adventure] You can't break that block with this item."))
        end
        return
    end

    return old_node_dig(pos, node, digger)
end

function minetest.item_place(stack, placer, pointed, ...)
    if placer and placer:is_player() and mcl_adventure.is_adventure(placer) then
        local restrict = get_setting_bool("mcl_adventure_restrict_placing", true)

        if restrict and not can_place_item(stack) then
            local pname = placer:get_player_name()
            if pname and pname ~= "" then
                minetest.chat_send_player(pname, minetest.colorize("#FFAA00",
                    "[Adventure] You can't place that block in Adventure mode."))
            end
            return stack, pointed
        end
    end

    return old_item_place(stack, placer, pointed, ...)
end

----------------------------------------------------------------------
-- Damage control for Adventure players
-- Uses: minetest.register_on_player_hpchange
----------------------------------------------------------------------

minetest.register_on_player_hpchange(function(player, hp_change, reason)
    if not mcl_adventure.is_adventure(player) then
        return hp_change
    end

    -- Only care about damage (negative HP change)
    if hp_change >= 0 then
        return hp_change
    end

    local allow_any   = get_setting_bool("mcl_adventure_allow_damage", true)
    if not allow_any then
        return 0
    end

    local allow_env   = get_setting_bool("mcl_adventure_allow_damage_environment", true)
    local allow_mobs  = get_setting_bool("mcl_adventure_allow_damage_mobs", true)
    local allow_other = get_setting_bool("mcl_adventure_allow_damage_other", true)

    local t = reason and reason.type or "unknown"

    -- Mob / punch damage
    if t == "punch" then
        if not allow_mobs then
            return 0
        end
        return hp_change
    end

    -- Environmental damages
    if t == "fall" or t == "node_damage" or t == "drown" or t == "void" then
        if not allow_env then
            return 0
        end
        return hp_change
    end

    -- The rest: potions, magic, commands, set_hp, etc.
    if not allow_other then
        return 0
    end

    return hp_change
end, true) -- true = this callback modifies HP

----------------------------------------------------------------------
-- /kill protection wrapper (optional)
----------------------------------------------------------------------

minetest.after(0, function()
    local orig = minetest.registered_chatcommands["kill"]
    if not orig then return end

    minetest.register_chatcommand("kill", {
        params      = orig.params,
        description = orig.description .. " (Adventure-aware)",
        privs       = orig.privs,
        func        = function(name, param)
            local protect = get_setting_bool("mcl_adventure_protect_kill", false)
            if not protect then
                -- behave like original
                return orig.func(name, param)
            end

            -- Very simple handling:
            -- /kill           -> self
            -- /kill <name>    -> that player
            local target_name = param ~= "" and param or name
            local target = minetest.get_player_by_name(target_name)

            if target and mcl_adventure.is_adventure(target) then
                return false, "[Adventure] /kill is disabled for players in Adventure mode."
            end

            return orig.func(name, param)
        end,
    })
end)

----------------------------------------------------------------------
-- OPTIONAL: helper to register example tools
-- (You can call this from another mod, or copy/paste these overrides.)
----------------------------------------------------------------------

function mcl_adventure.register_example_tools()
    local function safe_override(name, def)
        if minetest.registered_items[name] then
            minetest.override_item(name, def)
        end
    end

    -- Shears: can only break webs in Adventure mode
    safe_override("mcl_tools:shears", {
        adventure_can_break = { "mcl_core:web" },
    })

    -- Pickaxe: can break cobble, but NOT normal stone
    safe_override("mcl_tools:pick_iron", {
        adventure_can_break = { "mcl_core:cobble" },
    })

    -- Torch: can be placed in Adventure mode
    safe_override("mcl_torches:torch", {
        adventure_can_place = true,
    })
end
