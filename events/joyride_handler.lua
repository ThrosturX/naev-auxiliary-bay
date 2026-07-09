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

local joyride = require "joyride"

function ENTER_JUMPIN_MOTHERSHIP ()
    joyride.spawn_mothership()
    -- make spawn_mothership jump in from this system next time if following player
    local nc = naev.cache()
    nc.joyride.pos = system.cur()
    if nc.joyride.hook then
        hook.rm(nc.joyride.hook)
    end
    nc.joyride.hook = hook.pilot(nc.joyride.pilot, "board", "end_joyride")
end

local enter_hook = nil
function ENTER_SCHEDULE_MOTHERSHIP ()
    -- check if the joyride actually ended already
    if not naev.cache().joyride then
        if enter_hook then
            hook.rm(enter_hook)
            enter_hook = nil
        end
        return
    end
    -- disallow landing if requested by the user
    if naev.cache().joyride.noland then
        player.landAllow( false, tostring(naev.cache().joyride.noland) )
    end
    -- gotta jump in the player's ship at some point
    hook.timer( math.random(6, 20), "ENTER_JUMPIN_MOTHERSHIP" )
end


local joyride_ship
local last_ship = nil -- to circumvent hook.safe bug
function CHECK_MOTHERSHIP ( ref_name )
    if not ref_name then ref_name = last_ship end
    local nc = naev.cache()
    if nc.player_mothership == ref_name then
        nc.joyride.hook = hook.pilot(nc.joyride.pilot, "board", "end_joyride")
        -- make spawn_mothership jump in from this system if following player
        naev.cache().joyride.pos = system.cur()
        enter_hook = hook.enter( "ENTER_SCHEDULE_MOTHERSHIP" )
        joyride_ship = player.pilot():ship():nameRaw()
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


local info_button
local update_hook
local function rc_fighter()
    if naev.cache().joyride ~= nil then
        print("already joyriding")
        return -- already joyriding
    end
    local target = player.pilot():target()
    local mom = target:mothership()
    if not mom or mom ~= player.pilot() then
        if info_button then
            player.infoButtonUnregister( info_button )
            info_button = nil
            return
        end
    end

    local clone = target:clone()
    clone:changeAI("escort")
    clone:setTarget(target:target())

    joyride.swap_to_subship( player.pilot(), clone, "It came from one of your fighter bays." )
    local nc = naev.cache()
    nc.joyride.noland = _("You're piloting one of your fighters!")
    player.landAllow( false, nc.joyride.noland )
    player.pilot():setNoJump( true )
    player.pilot():setNoDeath( true )
    -- for some reason, the pilot hook "attacked" doesn't quite work as we'd want
    update_hook = hook.update("FIGHTER_ATTACKED")
end

function FIGHTER_REMOTE_CENTROL()
    -- check if the player is targeting a friendly fighter
    local target = player.pilot():target()
    if not target then
        return
    end
    local mom = target:mothership()
    if mom and mom == player.pilot() then
        info_button = player.infoButtonRegister ( _("Remote Control Fighter"), rc_fighter, 3 )
    elseif info_button then
        player.infoButtonUnregister( info_button )
        info_button = nil
    end
end

function create()
    hook.ship_swap( "CHECK_JOYRIDE" )
    hook.info("FIGHTER_REMOTE_CENTROL")
end

function end_joyride()
    if not naev.cache().joyride then
        print("Warning: ending joyride without a joyride vessel")
        return
    end
    if naev.cache().joyride.pilot and naev.cache().joyride.pilot:exists() then
        -- make sure we are in the shuttle (we reserve this variable when we are out of the mothership)
        if player.pilot():ship() ~= ship.get(joyride_ship) then
            vntk.msg( _("Docking Error"), _("The ship you are in doesn't appear to have the necessary adjustments to fit inside the docking bay. Whatever you've done with the ship you left with, you'd better bring it back if you want to get back on your ship."))
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
        player.pilot():setPos(naev.cache().joyride.pilot:pos())
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
    if enter_hook ~= nil then
        hook.rm(enter_hook)
        enter_hook = nil
    end
    if update_hook ~= nil then
        hook.rm(update_hook)
        update_hook = nil
    end
end

function FIGHTER_ATTACKED( _arg1, _arg2, _arg3 )
    local rc_plt = player.pilot()
    if not rc_plt or not rc_plt:exists() then
        print("Warning: rc_plt is nil")
        return nil
    end
    -- check if we're done here
    if rc_plt:health() <= 10 or rc_plt:disabled() then
        -- create an explosion since this fighter "died"
        local dummy = rc_plt:clone()
        dummy:changeAI("escort")
        -- end the joyride
        hook.safe("end_joyride")
    end
end
