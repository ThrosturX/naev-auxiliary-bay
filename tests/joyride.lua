package.path = "scripts/?.lua;" .. package.path

package.preload["common.derelict"] = function()
   return {
      sfxUnboard = function() end,
      sfxBoard = function() end,
   }
end
package.preload.format = function()
   return { f = function(text) return text end }
end
package.preload.vntk = function()
   return { msg = function() error("unexpected docking error") end }
end

local host = getfenv and getfenv(1) or _ENV
host._ = function(text) return text end

local calls = {}
local function record(name)
   calls[#calls + 1] = name
end
local function index_of(name)
   for i, value in ipairs(calls) do
      if value == name then return i end
   end
end

local mothership_ship = { name = function() return "Hephaestus" end }
local subship_type = { nameRaw = function() return "Alpaca" end }
local food = { nameRaw = function() return "Food" end }
local outfit = { nameRaw = function() return "Small Cargo Pod" end }

local clone = {
   changeAI = function(_, ai) record("clone-ai:" .. ai) end,
   setFaction = function() end,
   rename = function() end,
   cargoAdd = function(_, cargo, quantity)
      assert(cargo == food and quantity == 3, "mothership cargo restoration must use Commodity objects")
   end,
   setDir = function() end,
   setVel = function() end,
   outfitAdd = function() end,
   setVisplayer = function() end,
   setNoClear = function() end,
   setNoLand = function() end,
   setNoJump = function() end,
   setActiveBoard = function() end,
   setHilight = function() end,
   setFriendly = function() end,
   setInvincPlayer = function() end,
   exists = function() return true end,
   pos = function() return "mother-pos" end,
   dir = function() return 1 end,
   vel = function() return "mother-vel" end,
   cargoList = function() return { { c = food, q = 3 } } end,
   cargoRm = function(_, cargo, quantity)
      assert(cargo == food and quantity == 3, "stored cargo removal must use Commodity objects")
   end,
   rm = function() record("mothership-removed") end,
}

local stored_player = {
   ship = function() return mothership_ship end,
   faction = function() return "Player" end,
   pos = function() return "start-pos" end,
   dir = function() return 0 end,
   vel = function() return "start-vel" end,
   outfitsList = function() return {} end,
   worth = function() return 16000000 end,
   cargoList = function() return { { c = food, q = 3 } } end,
   cargoRm = function() end,
   cargoAdd = function(_, cargo, quantity)
      assert(cargo == food and quantity == 3, "returned cargo must use Commodity objects")
   end,
   stats = function() return { fuel = 1000, fuel_consumption = 100 } end,
   setFuel = function() end,
   hookClear = function() end,
   clone = function() record("clone"); return clone end,
   setPos = function() end,
   setDir = function() end,
   setVel = function() end,
}

local subpilot = {
   ship = function() return subship_type end,
   faction = function() return "Player" end,
   setVel = function() end,
   setDir = function() end,
   setPos = function() end,
   setTarget = function() end,
   setFuel = function() end,
   outfitRm = function() end,
   outfitAdd = function() end,
   setHealth = function() end,
   setEnergy = function() end,
   hookClear = function() end,
   outfitsList = function() return { outfit } end,
   stats = function() return { fuel = 10 } end,
}

local template = {
   ship = function() return subship_type end,
   name = function() return "QA Shuttle" end,
   stats = function() return { fuel_consumption = 20 } end,
   vel = function() return "template-vel" end,
   dir = function() return 2 end,
   pos = function() return "template-pos" end,
   target = function() return nil end,
   outfitsList = function() return { outfit } end,
   health = function() return 100, 50, 0 end,
   energy = function() return 25 end,
   rm = function() record("template-removed") end,
}

local shared_cache = {}
local current_pilot = stored_player
host.naev = {
   cache = function() return shared_cache end,
   trigger = function(name, payload)
      record("trigger:" .. name .. ":" .. payload.client)
   end,
}
host.faction = { dynAdd = function() return "Joyride faction" end }
host.hook = { rm = function() end }
host.player = {
   ship = function() return "QA Carrier" end,
   pilot = function() return current_pilot end,
   shipMetadata = function() return { acquired = "QA carrier" } end,
   shipAdd = function()
      record("ship-add")
      return "stored shuttle"
   end,
   shipSwap = function(ship)
      if ship == "stored shuttle" then
         current_pilot = subpilot
      else
         current_pilot = stored_player
      end
   end,
   allowSave = function() end,
   landAllow = function() end,
   commClose = function() end,
}
host.pilot = {
   add = function(_, _, _, _, options)
      record("pilot-add:" .. options.ai)
      return clone
   end,
}

local joyride = require "joyride"
joyride.swap_to_subship(stored_player, template, "QA", {
   client = "TXCrewmates",
   ai = "escort_guardian",
})

assert(index_of("clone-ai:escort_guardian") < index_of("ship-add"),
   "the cloned player ship must receive an AI before the player swaps ships")
assert(shared_cache.joyride.pilot == clone,
   "Joyride must own the only mothership pilot")
assert(joyride.end_joyride(), "the original auxiliary ship must redock")
assert(shared_cache.joyride == nil and shared_cache.player_mothership == nil,
   "redocking must clear Joyride state")
assert(index_of("mothership-removed"), "redocking must remove the NPC mothership")
assert(index_of("trigger:joyride_ended:TXCrewmates"),
   "redocking must notify the owning client")

shared_cache.joyride = {
   mothership = "QA Carrier",
   ship = mothership_ship,
   pos = "spawn",
   dir = 0,
   vel = "velocity",
   outfits = {},
   cargo = {},
   profile = { client = "joyride", ai = "escort_guardian" },
}
joyride.spawn_mothership()
assert(index_of("pilot-add:escort_guardian"),
   "respawned motherships must be created with an explicit AI")

print("ok - Joyride lifecycle")
