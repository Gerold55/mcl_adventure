-- mcl_adventure/init.lua
-- Hardcore Minecraft-like Adventure Mode for Mineclonia / Luanti
-- Blocks ALL block breaking and placement, even in creative (no flash/ghost dig)

local storage = minetest.get_mod_storage()

-- Per-player adventure state
local adventure_players = {}
local old_creative_state = {} -- stores if player had creative before adventure

mcl_adventure = {}

local function get_name(p)
    if type(p) == "string" then return p end
    if p and p.is_player and p:is_player() then
        return p:get_player_name()
    end
end

----------------------------------------------------------------------
-- Load/save state
----------------------------------------------------------------------

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local key = "player:" .. name
    local stored = storage:get_string(key)

    if stored == "" then
        local default_on = minetest.settings:get_bool("mcl_adventure_default", false)
        adventure_players[name] = default_on
        storage:set_string(key, default_on and "1" or "0")
    else
        adventure_players[name] = (stored == "1")
    end

    -- If joining already in adventure mode → disable creative instantly
    if adventure_players[name] then
        if minetest.get_player_privs(name).creative then
            old_creative_state[name] = true
            local privs = minetest.get_player_privs(name)
            privs.creative = nil
            minetest.set_player_privs(name, privs)
        end
    end
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
    return name and adventure_players[name] or false
end

-- ✓ Enable/Disable adventure mode
function mcl_adventure.set_adventure(p, enabled)
    local name = get_name(p)
    if not name then return end

    adventure_players[name] = enabled
    storage:set_string("player:" .. name, enabled and "1" or "0")

    local player = minetest.get_player_by_name(name)
    local privs = minetest.get_player_privs(name)

    if enabled then
        -- If player has creative, remove it temporarily
        if privs.creative then
            old_creative_state[name] = true
            privs.creative = nil
            minetest.set_player_privs(name, privs)
        end

        if player then
            minetest.chat_send_player(name, minetest.colorize("#55FF55",
                "[Adventure] Adventure mode enabled. ALL block breaking is disabled."))
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
    description = "Can change adventure mode for others",
    give_to_singleplayer = true,
})

minetest.register_chatcommand("adventure", {
    params = "[on|off|toggle] [player]",
    description = "Toggle Adventure mode",
    privs = { interact = true },
    func = function(name, param)
        local args = {}
        for w in param:gmatch("%S+") do args[#args+1] = w end

        local mode = args[1]
        local target = args[2] or name

        if target ~= name and
           not minetest.check_player_privs(name, { adventure_admin = true }) then
            return false, "You need adventure_admin to modify others."
        end

        local current = mcl_adventure.is_adventure(target)

        if mode == "on" then
            if current then return true, target.." is already in Adventure." end
            mcl_adventure.set_adventure(target, true)
            return true, target.." is now in Adventure mode."

        elseif mode == "off" then
            if not current then return true, target.." is not in Adventure." end
            mcl_adventure.set_adventure(target, false)
            return true, target.." left Adventure mode."

        else
            mcl_adventure.set_adventure(target, not current)
            return true, target.." Adventure mode toggled."
        end
    end,
})

----------------------------------------------------------------------
-- BLOCK ALL DIGGING COMPLETELY
----------------------------------------------------------------------

local old_node_dig = minetest.node_dig

function minetest.node_dig(pos, node, digger)
    if digger and digger:is_player() and mcl_adventure.is_adventure(digger) then
        local name = digger:get_player_name()
        minetest.chat_send_player(name,
            minetest.colorize("#FFAA00", "[Adventure] You cannot break blocks."))
        return -- fully block it
    end

    return old_node_dig(pos, node, digger)
end

----------------------------------------------------------------------
-- BLOCK ALL PLACING unless item has adventure_can_place=true
----------------------------------------------------------------------

local old_item_place = minetest.item_place

local function can_place(itemstack)
    local def = itemstack:get_definition()
    if not def then return false end

    if def.type ~= "node" then return true end -- tools/food ok

    return def.adventure_can_place == true
end

function minetest.item_place(stack, placer, pointed, ...)
    if placer and placer:is_player() and mcl_adventure.is_adventure(placer) then
        if not can_place(stack) then
            local name = placer:get_player_name()
            minetest.chat_send_player(name,
                minetest.colorize("#FFAA00",
                "[Adventure] You cannot place blocks."))
            return stack, pointed
        end
    end

    return old_item_place(stack, placer, pointed, ...)
end


-- Tool that can break stone and ores in Adventure:
--minetest.override_item("mcl_tools:pick_diamond", {
--    adventure_can_break = {
--        "mcl_core:diamond_ore", -- exact block
--        "group:stone",          -- any node with group stone > 0
--    },
--})

-- Block that can be placed in Adventure:
--minetest.override_item("mcl_core:stone", {
--    adventure_can_place = true,
--})
