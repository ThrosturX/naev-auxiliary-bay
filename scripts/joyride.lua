local der = require "common.derelict"

local function spawn_ghost()
    if
        naev.cache().joyride
    then
        if naev.cache().joyride.hook then
            hook.rm(naev.cache().joyride.hook)
            naev.cache().joyride.hook = nil
        end
        local pp = player.pilot()
        local fakefac = faction.dynAdd(pp:faction():name(), naev.cache().joyride.mothership, naev.cache().joyride.mothership, { ai = "escort_guardian", clear_enemies = true})

        naev.cache().joyride.pilot = pilot.add(naev.cache().joyride.ship, fakefac, naev.cache().joyride.pos, naev.cache().joyride.mothership, { naked = true })
        -- match speed and velocity
        naev.cache().joyride.pilot:setDir(naev.cache().joyride.dir)
        naev.cache().joyride.pilot:setVel(naev.cache().joyride.vel)
        -- and outfits
        for _j, o in ipairs(naev.cache().joyride.outfits) do
            naev.cache().joyride.pilot:outfitAdd(o)
        end
        -- put the cargo back
        for k, v in pairs(naev.cache().joyride.cargo) do
            -- the player took the mission cargo
            if not v.m then
                naev.cache().joyride.pilot:cargoAdd( v.name, v.q )
            end
        end
        naev.cache().joyride.pilot:setVisplayer(true)
        naev.cache().joyride.pilot:setNoClear(true)
        naev.cache().joyride.pilot:setNoLand(true)
        naev.cache().joyride.pilot:setNoJump(true)
        naev.cache().joyride.pilot:setActiveBoard(true)
        naev.cache().joyride.pilot:setHilight(true)
        naev.cache().joyride.pilot:setFriendly(true)
        naev.cache().joyride.pilot:setInvincPlayer(true)
        -- Handled by events/joyride_handler.lua
        -- hook.pilot(naev.cache().joyride.pilot, "board", "auxiliary_ship_return")
    end
end

local module = {}

module.swap_to_subship = function ( in_pilot, template, acquired )
    if not acquired then
        acquired = fmt.f(_("Belongs in the bay of your {mothership}."), { mothership = in_pilot():ship():name() } )
    end
    local ship_type = template:ship():nameRaw()
    local ship_name = template:name()
    naev.cache().joyride = {}
    naev.cache().joyride.mothership = player.ship() -- this only works for the player anyway
    naev.cache().joyride.ship = in_pilot:ship()
    naev.cache().joyride.pos = in_pilot:pos()
    naev.cache().joyride.dir = in_pilot:dir()
    naev.cache().joyride.vel = in_pilot:vel()
    naev.cache().joyride.outfits = in_pilot:outfitsList()
    naev.cache().joyride.cargo = in_pilot:cargoList()

    local cl = in_pilot:cargoList()
    for k, v in pairs( cl ) do
        if not v.m then
            -- goes into the placeholder ship
            in_pilot:cargoRm( v.name, v.q )
        end
    end

    local desired_fuel = template:stats().fuel_consumption
    local reserved_fuel
    if in_pilot:stats().fuel > desired_fuel + in_pilot:stats().fuel_consumption then
        reserved_fuel = desired_fuel
        -- unfuel the ship before we hand it over
        in_pilot:setFuel(in_pilot:stats().fuel - reserved_fuel)
    end

    in_pilot:hookClear() -- clear player hooks to prevent errors

    -- create and swap to the new ship here
    local newship = player.shipAdd(ship_type, ship_name, acquired, true)
    player.shipSwap( newship , false, false)

    -- fix the velocity vector and direction
    in_pilot:setVel(naev.cache().joyride.vel)
    in_pilot:setDir(naev.cache().joyride.dir)

    -- perform refit
    in_pilot:setFuel(0)   -- don't start with free fuel
    in_pilot:outfitRm( "all" )
    in_pilot:outfitRm( "cores" )

    for _j, o in ipairs( template:outfitsList() ) do
        in_pilot = in_pilot -- not sure why I'm doing this, but swapship.swap#116 does this
        in_pilot:outfitAdd(o, 1 , true)
    end
    player.allowSave(false)
    der.sfx.unboard:play()
    template:rm()
    
    -- create the player's ship in space
    spawn_ghost()
    naev.cache().joyride.pilot:changeAI( "escort_guardian" )

    if reserved_fuel then
        in_pilot:setFuel(reserved_fuel)
    else
        in_pilot:setFuel(0)   -- don't start with free fuel
    end

    naev.cache().player_mothership = naev.cache().joyride.mothership

    return in_pilot
end

return module
