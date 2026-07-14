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

local calls = {}
local triggers = {}
local spawned_motherships = 0
local save_allowed
local paid = 0
local current_name
local current_pilot
local ships = {}

local function record(value)
   calls[#calls + 1] = value
end

local function ship_type(name)
   return {
      nameRaw = function() return name end,
      name = function() return name end,
   }
end

local function make_pilot(hull)
   local cargo = {}
   local pilot = {
      cargo = cargo,
      removed = false,
      ship = function() return hull end,
      cargoList = function(self)
         local result = {}
         for _, item in ipairs(self.cargo) do
            result[#result + 1] = { c = item.c, q = item.q, m = item.m }
         end
         return result
      end,
      cargoAdd = function(self, commodity, quantity)
         self.cargo[#self.cargo + 1] = { c = commodity, q = quantity }
      end,
      cargoRm = function(self, commodity, quantity)
         for index = #self.cargo, 1, -1 do
            local item = self.cargo[index]
            if item.c == commodity and item.q == quantity then
               table.remove(self.cargo, index)
               return
            end
         end
      end,
      outfitsList = function() return {} end,
      worth = function() return 16000000 end,
      stats = function() return { fuel = 0 } end,
      hookClear = function() end,
      clone = function(self)
         local copy = make_pilot(hull)
         for _, item in ipairs(self.cargo) do
            copy.cargo[#copy.cargo + 1] = { c = item.c, q = item.q, m = item.m }
         end
         return copy
      end,
      changeAI = function() end,
      exists = function(self) return not self.removed end,
      rm = function(self) self.removed = true; record("pilot-rm") end,
      pos = function() return "position" end,
      dir = function() return 0 end,
      vel = function() return "velocity" end,
      setPos = function() end,
      setDir = function() end,
      setVel = function() end,
      setFuel = function() end,
      faction = function() return "Player" end,
      setFaction = function() end,
      rename = function() end,
      outfitAdd = function() end,
      outfitRm = function() end,
      setVisplayer = function() end,
      setNoClear = function() end,
      setNoLand = function() end,
      setNoJump = function() end,
      setActiveBoard = function() end,
      setHilight = function() end,
      setFriendly = function() end,
      setInvincPlayer = function() end,
   }
   return pilot
end

local carrier_type = ship_type("Hephaestus")
local alpaca_type = ship_type("Alpaca")
local llama_type = ship_type("Llama")
local hyena_type = ship_type("Hyena")
local shark_type = ship_type("Shark")
local pilots = {
   Carrier = make_pilot(carrier_type),
   Temp = make_pilot(alpaca_type),
   Replacement = make_pilot(llama_type),
   Purchased = make_pilot(hyena_type),
   EscortA = make_pilot(shark_type),
   EscortB = make_pilot(shark_type),
   EscortC = make_pilot(shark_type),
}

local cache = {}
naev = {
   cache = function() return cache end,
   trigger = function(name, payload)
      record("trigger:" .. name)
      triggers[#triggers + 1] = { name = name, payload = payload }
   end,
}
faction = { dynAdd = function() return "Nomad faction" end }
hook = { rm = function() end }
pilot = {
   add = function()
      spawned_motherships = spawned_motherships + 1
      local spawned = make_pilot(carrier_type)
      pilots.spawned = spawned
      return spawned
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
               name = name,
               ship = pilots[name]:ship(),
               deployed = deployed,
            }
         end
      end
      return result
   end,
   shipSwap = function(name, ignore_cargo, remove)
      record(string.format("swap:%s:%s:%s", name, tostring(ignore_cargo), tostring(remove)))
      local previous = current_name
      ships[name] = nil
      if remove then
         ships[previous] = nil
      else
         ships[previous] = false
      end
      current_name = name
      current_pilot = pilots[name]
   end,
   shipRm = function(name)
      record("remove:" .. name)
      ships[name] = nil
   end,
   shipAdd = function(hull, name)
      record("add:" .. hull .. ":" .. name)
      ships[name] = false
      return name
   end,
   shipMetadata = function()
      return { acquired = "Original carrier" }
   end,
   pay = function(amount)
      paid = paid + amount
   end,
   shipDeploy = function(name, deployed, spawn)
      record(string.format("deploy:%s:%s:%s", name, tostring(deployed), tostring(spawn)))
      ships[name] = deployed
   end,
   allowSave = function(allowed) save_allowed = allowed end,
   landAllow = function() end,
   commClose = function() end,
}

local joyride = require "joyride"
local profile = {
   client = "nomad",
   landable = true,
   landed_ship_lock = true,
   protect_mothership_sale = true,
   trade_replacement = true,
   owned_handoff = true,
   owned_escorts = true,
}

local function begin_virtual(name, hull)
   current_name = name
   current_pilot = pilots[name]
   ships = {
      Carrier = false,
      Purchased = false,
      EscortA = true,
      EscortB = true,
      EscortC = false,
   }
   cache.joyride = {
      mothership = "Carrier",
      ship = carrier_type,
      subship = hull,
      virtual_name = name,
      kind = "virtual",
      pos = "position",
      dir = 0,
      vel = "velocity",
      outfits = {},
      cargo = {},
      mothership_acquired = "Original carrier",
      profile = profile,
      pilot = make_pilot(carrier_type),
   }
   cache.player_mothership = "Carrier"
end

current_name = "Carrier"
current_pilot = pilots.Carrier
current_pilot.cargo = { { c = "Food", q = 2 } }
ships = { EscortA = true, EscortB = true }
local ok, reason = joyride.borrow_owned("EscortA")
assert(not ok and reason:find("profile") and cache.joyride == nil,
   "initial owned borrowing must remain opt-in through an explicit profile")
calls = {}
assert(joyride.borrow_owned("EscortA", profile),
   "a profile-enabled deployed escort must begin an owned Joyride session")
assert(calls[1] == "deploy:EscortA:false:false"
   and calls[2] == "swap:EscortA:true:false",
   "initial borrowing must recall the target before transferring control")
assert(cache.joyride.kind == "owned"
   and cache.joyride.controlled == "EscortA"
   and cache.joyride.mothership == "Carrier",
   "initial borrowing must preserve the original fixed mothership identity")
assert(save_allowed == false and cache.joyride.pilot,
   "an owned sortie must keep saving disabled and spawn the waiting mothership")
assert(joyride.end_joyride() and current_name == "Carrier",
   "the initially borrowed escort must return through the normal Joyride path")
assert(ships.EscortA == false,
   "ordinary Joyride return must continue recalling the controlled escort")
assert(#pilots.Carrier.cargo == 1 and pilots.Carrier.cargo[1].c == "Food"
   and pilots.Carrier.cargo[1].q == 2,
   "mothership cargo must survive an initial owned sortie without duplication")

begin_virtual("Temp", alpaca_type)
local original_identity = cache.joyride.mothership
assert(joyride.land(), "a Nomad virtual shuttle must be landable")
assert(cache.joyride.pilot == nil and save_allowed == false,
   "landing must remove only the runtime mothership and keep saving disabled")
calls = {}
player.shipSwap("Carrier", false, false)
assert(joyride.guard_landed_ship_swap("Carrier", "Temp")
   and current_name == "Temp"
   and calls[2] == "swap:Temp:false:false",
   "a landed mothership selection must restore the sortie craft and its cargo")
assert(not joyride.guard_landed_ship_swap("Temp", "Carrier")
   and current_name == "Temp",
   "the corrective swap hook must be ignored exactly once")
player.shipSwap("EscortA", false, false)
assert(joyride.guard_landed_ship_swap("EscortA", "Temp")
   and current_name == "Temp",
   "landed inspection of any owned ship must restore the sortie craft")
assert(joyride.takeoff(), "a landed Nomad shuttle must take off")
assert(cache.joyride.pilot and cache.joyride.mothership == original_identity,
   "takeoff must respawn the same stored mothership identity")
assert(triggers[#triggers].name == "joyride_mothership_spawned",
   "takeoff must emit the client-scoped mothership spawn event")
local respawned_mothership = cache.joyride.pilot
assert(joyride.takeoff() and cache.joyride.pilot == respawned_mothership
   and spawned_motherships == 1,
   "repeated takeoff callbacks must not duplicate the live mothership")

current_name = "Replacement"
current_pilot = pilots.Replacement
assert(joyride.ship_bought(llama_type, true),
   "a stock Trade must replace the virtual shuttle hull")
assert(cache.joyride.subship == llama_type
   and cache.joyride.virtual_name == "Replacement",
   "Trade must update the session virtual identity")
current_pilot.cargo = { { c = "Food", q = 1 } }
ok, reason = joyride.end_joyride()
assert(not ok and reason:find("empty") and current_name == "Replacement",
   "virtual docking must reject all cargo before mutating ships")
current_pilot.cargo = {}
assert(joyride.end_joyride(), "an empty traded shuttle must dock")
local ended = triggers[#triggers]
assert(ended.name == "joyride_ended"
   and ended.payload.returned_kind == "virtual"
   and ended.payload.hull == "Llama",
   "virtual return must report its replacement hull and return kind")
assert(ships.Replacement == nil,
   "docking must remove the traded virtual representation")

begin_virtual("Temp", alpaca_type)
calls = {}
assert(joyride.handoff_to_owned("Purchased"),
   "an empty virtual shuttle must hand off to a purchased owned ship")
assert(calls[1] == "trigger:joyride_shuttle_returned"
   and calls[2] == "swap:Purchased:true:false"
   and calls[3] == "remove:Temp",
   "Buy handoff must notify the client before swapping and deleting the shuttle")
assert(cache.joyride.kind == "owned" and cache.joyride.mothership == "Carrier"
   and ships.Temp == nil,
   "handoff must enter owned mode without replacing the mothership identity")

current_pilot.cargo = { { c = "Mission", q = 1, m = true } }
ok, reason = joyride.borrow_owned("EscortA")
assert(not ok and reason:find("mission") and ships.EscortA == true,
   "mission cargo must block owned-seat borrowing before deployment changes")
current_pilot.cargo = { { c = "Food", q = 2 } }
calls = {}
assert(joyride.borrow_owned("EscortA"), "a deployed escort must be borrowable")
assert(calls[1] == "deploy:EscortA:false:false"
   and calls[2] == "swap:EscortA:true:false"
   and calls[3] == "deploy:Purchased:true:true",
   "borrowing must recall the destination and redeploy the previous owned seat")
assert(pilots.Purchased.cargo[1].c == "Food",
   "ordinary cargo must remain aboard the previous owned ship")

assert(joyride.launch_owned("EscortC") and ships.EscortC == true,
   "launch_owned must immediately set vanilla deployment state")
assert(joyride.recall_owned("EscortB") and ships.EscortB == false,
   "recall_owned must immediately clear vanilla deployment state")
ships.EscortB = true
current_pilot.cargo = { { c = "Mission", q = 1, m = true } }
ok, reason = joyride.end_joyride()
assert(not ok and reason:find("mission") and current_name == "EscortA",
   "mission cargo must block mothership return before mutation")
current_pilot.cargo = {}
assert(joyride.end_joyride { redeploy_owned = true },
   "an owned escort must transfer control back to the mothership")
ended = triggers[#triggers]
assert(ended.payload.returned_kind == "owned" and current_name == "Carrier",
   "owned return must report its kind and restore the fixed mothership")
assert(ended.payload.redeployed == true and ships.EscortA == true
   and ships.EscortB == true
   and ships.Purchased == true,
   "seat transfer must redeploy the returned craft and preserve other escorts")

begin_virtual("Temp", alpaca_type)
current_pilot.cargo = { { c = "Food", q = 1 } }
ok, reason = joyride.handoff_to_owned("Purchased")
assert(not ok and reason:find("empty") and current_name == "Temp",
   "Buy handoff must reject cargo before deleting the virtual shuttle")

begin_virtual("Temp", alpaca_type)
cache.joyride.profile = {
   client = "other",
   landable = true,
}
assert(joyride.land(), "another landable profile must still be able to land")
player.shipSwap("Carrier", false, false)
assert(not joyride.guard_landed_ship_swap("Carrier", "Temp")
   and current_name == "Carrier",
   "landed ship locking must remain opt-in")

begin_virtual("Temp", alpaca_type)
assert(joyride.land(), "the virtual shuttle must land before a Trade")
player.shipSwap("Replacement", false, false)
ships.Temp = nil
assert(not joyride.guard_landed_ship_swap("Replacement", "Temp")
   and current_name == "Replacement",
   "a completed Trade must not be reversed after removing the old ship")

begin_virtual("Temp", alpaca_type)
assert(joyride.land(), "the virtual shuttle must land before a carrier sale")
ships.Carrier = nil
paid = 0
assert(joyride.restore_sold_mothership(carrier_type, "Carrier")
   and ships.Carrier == false
   and paid == -16000000
   and current_name == "Temp",
   "selling the mothership must restore ownership and reverse the proceeds")
assert(triggers[#triggers].name == "joyride_mothership_restored",
   "restoring a sold mothership must notify the active Joyride client")

local real_end_joyride = joyride.end_joyride
local unboarded = false
player.unboard = function() unboarded = true end
joyride.end_joyride = function()
   assert(unboarded, "the board hook must suppress stock boarding first")
   return true
end
dofile("events/joyride_handler.lua")
assert(end_joyride(), "the Joyride board hook must complete normally")
joyride.end_joyride = real_end_joyride

print("ok - Joyride Nomad lifecycle")
