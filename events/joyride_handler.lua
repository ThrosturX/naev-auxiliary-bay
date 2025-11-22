--[[
<?xml version='1.0' encoding='utf8'?>
<event name="Joyride Handler">
 <location>load</location>
 <chance>100</chance>
 <unique />
</event>
--]]

--[[
   Joyride Handler

   Allows the player to fly joyride other ships
--]]

-- luacheck: globals CHECK_MOTHERSHIP CHECK_JOYRIDE end_joyride (Hook functions passed by name)


local der = require "common.derelict"
local vntk = require "vntk"

-- to circumvent hook.safe bug
local last_ship = nil
function CHECK_MOTHERSHIP ( ref_name )
    if not ref_name then ref_name = last_ship end
    local nc = naev.cache()
    if nc.player_mothership == ref_name then
        nc.joyride.hook = hook.pilot(nc.joyride.pilot, "board", "end_joyride")
    end
end

function CHECK_JOYRIDE( new_name, new_type , old_ship )
    local nc = naev.cache()
    if nc.joyride and not nc.joyride.hook then
        -- we actually need to wait one more frame before the mothership is set, so hook it here
        last_ship = old_ship -- monkey patch for hook.safe bug
        hook.safe( "CHECK_MOTHERSHIP", old_ship)

    end
end

function create()
    hook.ship_swap( "CHECK_JOYRIDE" )
end

function end_joyride()
    if naev.cache().joyride.pilot and naev.cache().joyride.pilot:exists() then
        -- make sure we are in the shuttle (we reserve this variable when we are out of the mothership)
        if player.pilot():ship() ~= ship.get("Cargo Shuttle") then
            vntk.msg( _("Docking Error"), _("The ship you are in doesn't appear to have the necessary adjustments to fit inside the docking bay. Whatever you've done with the shuttle, you'd better bring it back if you want to get back on your ship."))
            -- player doesn't get to return
            player.commClose()
            return false -- pun not intended
        end
        player.pilot():hookClear() -- clear player hooks to prevent errors

        -- we are redocking, save the current outfit layout
        shuttle_outfits = {}
        for j, o in ipairs(player.pilot():outfitsList()) do
            shuttle_outfits[#shuttle_outfits + 1] = o:nameRaw()
        end
        local carried_fuel = player.pilot():stats().fuel
        -- the player goes back into the captain's seat
        -- bringing any cargo along
        player.shipSwap(naev.cache().joyride.mothership, false, true)
        -- copy the vector
        player.pilot():setDir(naev.cache().joyride.pilot:dir())
        player.pilot():setVel(naev.cache().joyride.pilot:vel())
        player.pilot():setFuel(player.pilot():stats().fuel + carried_fuel)

        -- put the cargo back
        local cl = naev.cache().joyride.pilot:cargoList()
        -- goes back into the player
        for k,v in pairs( cl ) do
            naev.cache().joyride.pilot:cargoRm( v.name, v.q )
            player.pilot():cargoAdd( v.name, v.q )
        end
        naev.cache().joyride.pilot:rm()
        player.allowSave(true)
        der.sfx.board:play()
        player.landAllow ( true )
    end
    naev.cache().joyride = nil
    naev.cache().player_mothership = nil
    last_ship = nil
end
