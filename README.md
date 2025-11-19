# mcl_adventure
Adventure mode for Mineclonia

Features:
--  * Per-player Adventure flag (saved).
--  * Blocks cannot be broken by hand or tools unless tool is whitelisted.
--  * Entities CAN be interacted with (normal punching / use).
--      - Crops/mobs/boats/minecarts etc. behave normally except where restricted.
--  * Optional:
--      - Strict "CanDestroy" tool rules (default ON, Minecraft-like).
--      - Restrict placing blocks ("CanPlaceOn").
--      - Allow crops/plants to be harvested.
--      - Control which damage sources can hurt Adventure players.
--      - Protect Adventure players from /kill.
--      - Custom spawn points via command, like beds but anytime.
--
--  Tool whitelist:
--      minetest.override_item("mcl_tools:shears", {
--          adventure_can_break = { "mcl_core:web" },
--      })
--
--  Example:
--      Shears break webs but not anything else in Adventure mode.
--
--  Placement whitelist:
--      minetest.override_item("mcl_core:stone", {
--          adventure_can_place = true,
--      })