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

-- luacheck: globals end_joyride joyride_land joyride_takeoff joyride_ship_bought joyride_ship_sold joyride_ship_swapped joyride_mothership_spawned joyride_session_ended (Hook functions passed by name)

local joyride = require "joyride"

local function attach_board_hook()
    local state = naev.cache().joyride
    if not state or not state.pilot or not state.pilot:exists() then return end
    if state.hook then hook.rm(state.hook) end
    state.hook = hook.pilot(state.pilot, "board", "end_joyride")
end

function ENTER_JUMPIN_MOTHERSHIP ( token )
    local state = naev.cache().joyride
    if not state or state.token ~= token
        or not joyride.mothership_follows() then return end
    joyride.spawn_mothership()
    -- make spawn_mothership jump in from this system next time if following player
    local nc = naev.cache()
    if not nc.joyride then return end
    nc.joyride.pos = system.cur()
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
    if not joyride.mothership_follows() then return end
    -- gotta jump in the player's ship at some point
    hook.timer( math.random(6, 20), "ENTER_JUMPIN_MOTHERSHIP",
        naev.cache().joyride.token )
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
    hook.ship_swap( "joyride_ship_swapped" )
    hook.ship_buy( "joyride_ship_bought" )
    hook.ship_sell( "joyride_ship_sold" )
    hook.land( "joyride_land" )
    hook.takeoff( "joyride_takeoff" )
    hook.custom( "joyride_mothership_spawned", "joyride_mothership_spawned" )
    hook.custom( "joyride_ended", "joyride_session_ended" )
    hook.info("FIGHTER_REMOTE_CENTROL")
end

function joyride_ship_swapped( new_name )
    joyride.landed_ship_swap( new_name )
end

function joyride_ship_sold( ship_type, name )
    if joyride.restore_sold_mothership( ship_type, name ) then
        player.msg( _("The active Joyride mothership cannot be sold during a sortie.") )
    end
end

function joyride_mothership_spawned()
    attach_board_hook()
    if enter_hook then hook.rm(enter_hook) end
    enter_hook = hook.enter( "ENTER_SCHEDULE_MOTHERSHIP" )
end

function joyride_session_ended()
    if enter_hook then
        hook.rm(enter_hook)
        enter_hook = nil
    end
    if update_hook then
        hook.rm(update_hook)
        update_hook = nil
    end
end

function joyride_ship_bought( ship_type, traded )
    joyride.ship_bought( ship_type, traded )
end

function joyride_land()
    joyride.land()
end

function joyride_takeoff()
    joyride.takeoff()
end

function end_joyride()
    player.unboard()
    if not joyride.end_joyride{ physical = true } then return false end
    return true
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
