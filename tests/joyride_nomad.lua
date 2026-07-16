package.path = "scripts/?.lua;" .. package.path

package.preload["common.derelict"] = function()
   return { sfxUnboard = function() end, sfxBoard = function() end }
end
package.preload.format = function()
   return { f = function(text) return text end }
end
package.preload.vntk = function()
   return { msg = function() error("unexpected docking dialogue") end }
end

_ = function(text) return text end
vec2 = { new = function(x, y) return { x = x, y = y } end }

local calls, triggers = {}, {}
local function record(value) calls[#calls + 1] = value end
local function index_of(value)
   for index, candidate in ipairs(calls) do
      if candidate == value then return index end
   end
end

local function ship_type(name)
   return { nameRaw = function() return name end, name = function() return name end }
end

local carrier_type = ship_type("Hephaestus")
local scout_type = ship_type("Shark")
local shuttle_type = ship_type("Alpaca")
local purchased_type = ship_type("Llama")

local function make_pilot(hull, label)
   local subject = {
      label = label,
      cargo = {},
      removed = false,
      capacity = 100,
      ship = function() return hull end,
      faction = function() return "Player" end,
      pos = function(self) return self.label .. "-pos" end,
      dir = function() return 1 end,
      vel = function(self) return self.label .. "-vel" end,
      health = function() return 90, 80, 0 end,
      worth = function() return 1000 end,
      energy = function() return 70 end,
      stats = function()
         return { fuel = 60, fuel_consumption = 10, armour = 100 }
      end,
      outfitsList = function() return {} end,
      cargoList = function(self)
         local result = {}
         for _, item in ipairs(self.cargo) do
            result[#result + 1] = { c = item.c, q = item.q, m = item.m }
         end
         return result
      end,
      cargoFree = function(self) return self.capacity end,
      cargoAdd = function(self, commodity, quantity)
         self.cargo[#self.cargo + 1] = { c = commodity, q = quantity }
      end,
      cargoRm = function(self, commodity, quantity)
         if commodity == "all" then self.cargo = {}; return end
         for index = #self.cargo, 1, -1 do
            local item = self.cargo[index]
            if item.c == commodity and item.q == quantity then
               table.remove(self.cargo, index)
               return
            end
         end
      end,
      clone = function(self)
         local result = make_pilot(hull, self.label .. "-clone")
         for _, item in ipairs(self.cargo) do
            result.cargo[#result.cargo + 1] = { c = item.c, q = item.q, m = item.m }
         end
         return result
      end,
      changeAI = function() end,
      exists = function(self) return not self.removed end,
      rm = function(self) self.removed = true; record("rm:" .. self.label) end,
      hookClear = function() end,
      setPos = function() end,
      setDir = function() end,
      setVel = function() end,
      setFuel = function() end,
      setHealth = function() end,
      setEnergy = function() end,
      setTarget = function() end,
      outfitAdd = function() end,
      outfitRm = function() end,
      setFaction = function() end,
      rename = function() end,
      setVisplayer = function() end,
      setNoClear = function() end,
      setNoLand = function() end,
      setNoJump = function() end,
      setActiveBoard = function() end,
      setHilight = function() end,
      setFriendly = function() end,
      setInvincPlayer = function() end,
   }
   return subject
end

local pilots = {
   Carrier = make_pilot(carrier_type, "carrier"),
   Scout = make_pilot(scout_type, "scout"),
   Purchased = make_pilot(purchased_type, "purchased"),
   Shuttle = make_pilot(shuttle_type, "shuttle"),
}
local ships, current_name, current_pilot = {}, "Carrier", pilots.Carrier
local cache = {}
local landed = false

naev = {
   cache = function() return cache end,
   trigger = function(name, payload)
      record("trigger:" .. name)
      triggers[#triggers + 1] = { name = name, payload = payload }
   end,
}
faction = { dynAdd = function() return "Nomad faction" end }
hook = {
   rm = function(id) record("hook-rm:" .. tostring(id)) end,
   pilot = function() return 1 end,
   timer = function() return 2 end,
   safe = function() return 3 end,
   enter = function() return 4 end,
   ship_swap = function() end,
   ship_buy = function() end,
   land = function() end,
   takeoff = function() end,
   info = function() end,
   update = function() return 5 end,
}
system = { cur = function() return "system" end }
pilot = {
   add = function(hull)
      record("add:mothership")
      local result = make_pilot(hull, "spawned")
      pilots.spawned = result
      return result
   end,
}
player = {
   ship = function() return current_name end,
   pilot = function() return current_pilot end,
   ships = function()
      local result = {}
      for name, deployed in pairs(ships) do
         if name ~= current_name then
            result[#result + 1] = {
               name = name, ship = pilots[name]:ship(), deployed = deployed,
            }
         end
      end
      return result
   end,
   shipMetadata = function() return { acquired = "Original carrier" } end,
   shipOutfits = function() return {} end,
   shipAdd = function(_, name) ships[name] = false; return name end,
   shipRm = function(name) ships[name] = nil; record("remove:" .. name) end,
   shipSwap = function(name, ignore_cargo, remove)
      record(string.format("swap:%s:%s:%s", name,
         tostring(ignore_cargo), tostring(remove)))
      local previous = current_name
      if remove then ships[previous] = nil else ships[previous] = false end
      ships[name] = nil
      current_name, current_pilot = name, pilots[name]
   end,
   allowSave = function() end,
   landAllow = function() end,
   pay = function(amount) record("pay:" .. tostring(amount)) end,
   commClose = function() end,
   unboard = function() end,
   isLanded = function() return landed end,
   infoButtonRegister = function() return 1 end,
   infoButtonUnregister = function() end,
}

local joyride = require "joyride"
local profile = {
   client = "nomad", landable = true,
   trade_replacement = true, owned_handoff = true,
}

local function reset(name, owned)
   cache.joyride, cache.player_mothership = nil, nil
   calls, triggers = {}, {}
   current_name, current_pilot = name, pilots[name]
   ships = owned
   for _, subject in pairs(pilots) do
      if type(subject) == "table" then
         subject.removed = false
         subject.cargo = {}
         subject.capacity = 100
      end
   end
end

-- A launched owned craft and an adopted stored craft enter the same state.
reset("Carrier", { Scout = false, Purchased = false })
local template = make_pilot(scout_type, "launched")
assert(joyride.begin_owned_sortie("Scout", template, profile))
assert(cache.joyride.kind == "owned"
   and cache.joyride.controlled == "Scout"
   and cache.joyride.mothership == "Carrier"
   and current_name == "Scout" and cache.joyride.pilot,
   "launched owned craft must enter the common owned lifecycle")
assert(index_of("rm:launched") < index_of("swap:Scout:true:false")
   and index_of("swap:Scout:true:false") < index_of("add:mothership"),
   "owned seat entry must never overlap duplicate craft or carrier names")
assert(joyride.end_joyride { seat_transfer = true })

reset("Scout", { Carrier = false, Purchased = false })
assert(joyride.begin_stored_owned_sortie(
   "Carrier", profile, "parked-position", 2))
assert(cache.joyride.kind == "owned"
   and cache.joyride.controlled == "Scout"
   and cache.joyride.mothership == "Carrier"
   and current_name == "Scout" and cache.joyride.pilot,
   "stored takeoff must adopt the selected craft into the same owned state")
local stored_mothership = cache.joyride.pilot
assert(joyride.takeoff() and cache.joyride.pilot == stored_mothership,
   "stored adoption must spawn exactly one returnable mothership")

-- Seat transfers require an empty controlled craft and notify before swapping.
pilots.Scout.cargo = { { c = "Food", q = 1 } }
local ok, reason = joyride.end_joyride { seat_transfer = true }
assert(not ok and reason:find("unload") and current_name == "Scout",
   "seat transfer must reject all cargo before mutation")
pilots.Scout.cargo = {}
calls = {}
assert(joyride.end_joyride { seat_transfer = true })
assert(index_of("trigger:joyride_returning")
   < index_of("swap:Carrier:true:false"),
   "joyride_returning must synchronously precede an owned shipSwap")
local returning = triggers[#triggers - 1]
assert(returning.name == "joyride_returning"
   and returning.payload.armour == 90
   and returning.payload.shield == 80
   and returning.payload.armour_max == 100,
   "joyride_returning must carry immutable pre-swap health values")

-- Physical return accepts cargo only when the live mothership can fit it.
reset("Scout", { Carrier = false })
assert(joyride.begin_stored_owned_sortie(
   "Carrier", profile, "parked-position", 2))
assert(joyride.takeoff())
pilots.Scout.cargo = { { c = "Mission", q = 2, m = true } }
cache.joyride.pilot.capacity = 1
ok, reason = joyride.end_joyride()
assert(not ok and reason:find("cargo space") and current_name == "Scout",
   "physical return must reject cargo that does not fit")
cache.joyride.pilot.capacity = 2
assert(joyride.end_joyride(),
   "physical return must accept cargo that fits")

-- Handoff is narrow, cargo-safe, and retains the existing session.
reset("Shuttle", { Carrier = false, Purchased = false })
cache.joyride = {
   kind = "virtual", mothership = "Carrier", virtual_name = "Shuttle",
   subship = shuttle_type, profile = profile,
   pilot = make_pilot(carrier_type, "carrier-proxy"),
}
cache.player_mothership = "Carrier"
pilots.Shuttle.cargo = { { c = "Food", q = 1 } }
ok, reason = joyride.handoff_to_owned("Purchased")
assert(not ok and reason:find("empty"),
   "handoff must reject cargo before deleting the virtual craft")
pilots.Shuttle.cargo = {}
calls = {}
assert(joyride.handoff_to_owned("Purchased"))
assert(calls[1] == "trigger:joyride_shuttle_returned"
   and calls[2] == "swap:Purchased:true:false"
   and calls[3] == "remove:Shuttle",
   "handoff must notify, swap, and remove in that order")
assert(cache.joyride.kind == "owned"
   and cache.joyride.controlled == "Purchased",
   "handoff must reuse the common owned lifecycle")

-- Land/takeoff removes and recreates only the runtime mothership.
reset("Shuttle", { Carrier = false })
cache.joyride = {
   kind = "virtual", mothership = "Carrier", ship = carrier_type,
   subship = shuttle_type, virtual_name = "Shuttle",
   pos = "position", dir = 1, vel = "velocity", outfits = {}, cargo = {},
   profile = profile, pilot = make_pilot(carrier_type, "landed-proxy"),
}
assert(joyride.land() and cache.joyride.pilot == nil,
   "landing must remove the runtime mothership but retain the session")
assert(joyride.takeoff() and cache.joyride.pilot,
   "takeoff must respawn the retained mothership session")
local respawned = cache.joyride.pilot
assert(joyride.takeoff() and cache.joyride.pilot == respawned,
   "duplicate takeoff callbacks must not duplicate the mothership")

-- Landed equipment swaps are adopted without reversing the user's selection,
-- and the active mothership is restored if sold through the shipyard UI.
reset("Scout", { Carrier = false, Purchased = false })
assert(joyride.begin_stored_owned_sortie(
   "Carrier", profile, "parked-position", 2))
assert(joyride.land())
landed = true
player.shipSwap("Purchased", true, false)
assert(joyride.landed_ship_swap("Purchased")
   and cache.joyride.controlled == "Purchased"
   and current_name == "Purchased",
   "landed owned-ship swaps must update the common sortie in place")
ships.Carrier = nil
assert(joyride.restore_sold_mothership(carrier_type, "Carrier")
   and ships.Carrier == false and current_name == "Purchased",
   "selling the active mothership must restore it without changing seats")
landed = false

-- Expired handler timers are harmless after the session has ended.
dofile("events/joyride_handler.lua")
cache.joyride, cache.player_mothership = nil, nil
ENTER_JUMPIN_MOTHERSHIP()
ENTER_SCHEDULE_MOTHERSHIP()

print("ok - Joyride integration lifecycle")
