local fmt = require "format"
local der = require "common.derelict"
local joyride = require "joyride"
local pir = require "common.pirate"

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

-- NOTE:  in_pilot must be the player
local function aux_mission( in_pilot )
    -- setup
    local template = pilot.add("Cargo Shuttle", "Trader", player.pilot():pos(), ship_name)
    local ship_name = fmt.f( _("{name}'s Shuttle"), {name = player:ship() } )
    local acquired = fmt.f(_("The shuttle bay of your {mothership}."), { mothership = player:ship() } )
    
    -- main heavy lifter
    local pp = joyride.swap_to_subship( in_pilot, template, acquired )

    -- extra fluff comes here
    -- can't let the player land in a cargo shuttle that wasn't owned by the player
    local land_msg = _("The shuttle is only suited for light space travel.") 
    player.landAllow ( false, land_msg)
--  player.pilot():setNoJump(true)

    -- cache.joyride created by joyride.swap_to_subship
    naev.cache().joyride.noland = land_msg
    -- risky?
    player.pilot():hookClear() -- clear player hooks to prevent errors

    player.pilot():setHealth(100, 75, 25)
    player.pilot():setEnergy(35)

    return true

end

function ontoggle( p, po, on )
    if naev.cache().joyride == nil then
        configure_outfits()
        return aux_mission( p )
        -- return auxiliary_ship_mission( p )
    end
    po:state("off")
end
