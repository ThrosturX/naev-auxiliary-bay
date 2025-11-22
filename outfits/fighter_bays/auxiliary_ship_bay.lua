local fmt = require "format"
local der = require "common.derelict"

local shuttle_outfits
local function add_outfit( oname )
    if player.outfitNum( oname, true ) > 0 then
        shuttle_outfits[#shuttle_outfits + 1] = oname
        return true
    end
    return false
end

local accessories
local function get_accessories()
    if not accessories then
        accessories = {}
        local po = player.pilot():outfitsList()
        for _i, oo in ipairs(po) do
            if oo:type() == "Accessory" then
                table.insert(accessories, oo:nameRaw())
            end
        end
    end
    return accessories
end

local function configure_outfits()
    local needs_transponder
    local cf = system.cur():faction()
    if cf ~= nil and cf:reputationDefault() < 0 and not pir.factionIsPirate(cf) then
        needs_transponder = "Fake Transponder"
--  this code smell can stay until a crimson holo-disfigurator actually exists (or another kind of transponder)
--  elseif cf:playerStanding() <= 30 and not player.pilot():ship():tags().pirate then
--      needs_transponder = "Crimson Holo-Disfigurator"
    end
    if
        not shuttle_outfits
        or needs_transponder
    then
        shuttle_outfits = {}

        -- add a plasma drill if we own one
        if not add_outfit("S&K Plasma Drill") then
            -- if we don't have a plasma drill, maybe we are pirates
            -- so fit a transponder if we need one
            if needs_transponder then
                add_outfit(needs_transponder)
            else
                -- couldn't find anything useful, let's try to put a blink drive in the medium slot
                add_outfit("Blink Drive")
            end
        end
        -- if we have unlocked the pulse scanner, we definitely want one!
        add_outfit("Pulse Scanner")

        -- if we didn't already fill our slots, try to increase stealth
        add_outfit("Veil of Penelope")
        add_outfit("Nexus Concealment Coating")
        -- structure slots, no use for anything else since we don't allow landing or jumping
        add_outfit("Small Cargo Pod")
        add_outfit("Small Cargo Pod")

        -- accessory slot
        accessories = get_accessories()
        local accessory = accessories[rnd.rnd(1, #accessories)]
        if accessory then
            add_outfit(accessory)
        end

        -- tiny drone slot
        add_outfit("Za'lek Scanning Drone Interface")
    end
end

-- NOTE: Not implemented: outfit states, etc, the spawned 'ghost' is pretty much a naive copy
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
        -- Handled by event
        -- hook.pilot(naev.cache().joyride.pilot, "board", "auxiliary_ship_return")
    end
end
local function auxiliary_ship_mission( in_pilot )
    local template = pilot.add("Cargo Shuttle", "Trader", player.pilot():pos())
    -- Shuttle outfits was here

    local pp = in_pilot

    naev.cache().joyride = {}
    naev.cache().joyride.mothership = player.ship()
    naev.cache().joyride.ship = pp:ship()
    naev.cache().joyride.pos = pp:pos()
    naev.cache().joyride.dir = pp:dir()
    naev.cache().joyride.vel = pp:vel()
    naev.cache().joyride.outfits = pp:outfitsList()
    naev.cache().joyride.cargo = pp:cargoList()

    local cl = pp:cargoList()
    for k, v in pairs( cl ) do
        if not v.m then
            -- goes into the placeholder ship
            pp:cargoRm( v.name, v.q )
        end
    end

    local desired_fuel = template:stats().fuel_consumption
    local reserved_fuel
    if pp:stats().fuel > desired_fuel + pp:stats().fuel_consumption then
        reserved_fuel = desired_fuel
        -- unfuel the ship before we hand it over
        pp:setFuel(pp:stats().fuel - reserved_fuel)
    end

    -- create and swap to the shuttle here
    pp:hookClear() -- clear player hooks to prevent errors
    local acquired = fmt.f(_("The shuttle bay of your {mothership}."), { mothership = player:ship() } )

    local shuttle_name = fmt.f( _("{name}'s Shuttle"), {name = player:ship() } )
    local newship = player.shipAdd("Cargo Shuttle", shuttle_name, acquired, true)
    player.shipSwap( newship , false, false)

    -- fix the velocity vector and direction
    in_pilot:setVel(naev.cache().joyride.vel)
    in_pilot:setDir(naev.cache().joyride.dir)

    -- perform refit
    pp = in_pilot
    pp:setFuel(0)   -- don't start with free fuel
    pp:outfitRm( "all" )
    pp:outfitRm( "cores" )

    for _j, o in ipairs( template:outfitsList() ) do
        pp = in_pilot -- not sure why I'm doing this, but swapship.swap#116 does this
        pp:outfitAdd(o, 1 , true)
    end
    player.allowSave(false)
    der.sfx.unboard:play()
    template:rm()

    -- create the player's ship in space
    spawn_ghost()
    naev.cache().joyride.pilot:changeAI( "escort_guardian" )

    -- unregister the info button, need to hail the mothership now
    player.landAllow ( false, _("The shuttle is only suited for light space travel.") )
    player.pilot():setNoJump(true)

    -- risky
    player.pilot():hookClear() -- clear player hooks to prevent errors

    player.pilot():setHealth(100, 75, 25)
    player.pilot():setEnergy(35)

    if reserved_fuel then
        pp:setFuel(reserved_fuel)
    else
        pp:setFuel(0)   -- don't start with free fuel
    end

    local c = naev.cache()
    c.player_mothership = naev.cache().joyride.mothership

    return true
end

function ontoggle( p, po, on )
    if naev.cache().joyride == nil then
        configure_outfits()
        return auxiliary_ship_mission( p )
    end
    po:state("off")
end
