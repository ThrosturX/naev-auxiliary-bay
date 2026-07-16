package.path = "scripts/?.lua;" .. package.path

package.preload["common.derelict"] = function()
   return { sfxUnboard = function() end, sfxBoard = function() end }
end
package.preload.format = function()
   return { f = function(text) return text end }
end
package.preload.vntk = function()
   return { msg = function() error("unexpected docking error") end }
end

_ = function(text) return text end

local calls = {}
local function record(value) calls[#calls + 1] = value end
local function index_of(value)
   for index, candidate in ipairs(calls) do
      if candidate == value then return index end
   end
end

local carrier_type = { name = function() return "Hephaestus" end }
local shuttle_type = { nameRaw = function() return "Alpaca" end }
local food = { nameRaw = function() return "Food" end }
local outfit = { nameRaw = function() return "Small Cargo Pod" end }

local function common_pilot(hull)
   return {
      ship = function() return hull end,
      faction = function() return "Player" end,
      pos = function() return "position" end,
      dir = function() return 1 end,
      vel = function() return "velocity" end,
      health = function() return 90, 80, 0 end,
      energy = function() return 70 end,
      stats = function() return { fuel = 60, fuel_consumption = 10 } end,
      outfitsList = function() return {} end,
      cargoList = function() return {} end,
      cargoFree = function() return 100 end,
      cargoAdd = function() end,
      cargoRm = function() end,
      hookClear = function() end,
      setPos = function() end,
      setDir = function() end,
      setVel = function() end,
      setFuel = function() end,
      setHealth = function() end,
      setEnergy = function() end,
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
      exists = function() return true end,
   }
end

local carrier = common_pilot(carrier_type)
carrier.outfitsList = function() return { outfit } end
carrier.cargoList = function() return { { c = food, q = 3 } } end
carrier.cargoRm = function(_, commodity, quantity)
   assert(commodity == food and quantity == 3)
end

local clone = common_pilot(carrier_type)
clone.changeAI = function(_, ai) record("clone-ai:" .. ai) end
clone.cargoRm = function(_, commodity, quantity)
   if commodity == "all" then
      record("clone-cargo-cleared")
      return
   end
   assert(commodity == food and quantity == 3)
end
clone.cargoAdd = function(_, commodity, quantity)
   assert(commodity == food and quantity == 3)
end
clone.cargoList = function() return { { c = food, q = 3 } } end
clone.rm = function() record("mothership-removed") end
carrier.clone = function() return clone end

local shuttle = common_pilot(shuttle_type)
shuttle.outfitsList = function() return { outfit } end
shuttle.setTarget = function() end

local template = common_pilot(shuttle_type)
template.name = function() return "QA Shuttle" end
template.target = function() return nil end
template.outfitsList = function() return { outfit } end
template.rm = function() record("template-removed") end

local shared_cache = {}
local current_name = "QA Carrier"
local current_pilot = carrier
naev = {
   cache = function() return shared_cache end,
   trigger = function(name, payload)
      record("trigger:" .. name .. ":" .. payload.client)
   end,
}
faction = { dynAdd = function() return "Joyride faction" end }
hook = { rm = function() end }
player = {
   ship = function() return current_name end,
   pilot = function() return current_pilot end,
   shipMetadata = function() return { acquired = "QA carrier" } end,
   shipAdd = function()
      record("ship-add")
      return "QA Shuttle"
   end,
   shipSwap = function(name, ignore_cargo, remove)
      record(string.format("swap:%s:%s:%s", name,
         tostring(ignore_cargo), tostring(remove)))
      current_name = name
      current_pilot = name == "QA Carrier" and carrier or shuttle
   end,
   allowSave = function() end,
   landAllow = function() end,
   commClose = function() end,
}
pilot = { add = function()
   record("mothership-added")
   return clone
end }

local joyride = require "joyride"
assert(joyride.swap_to_subship(carrier, template, "QA", {
   client = "TXCrewmates", ai = "escort_guardian",
}))
assert(index_of("template-removed") < index_of("ship-add")
   and index_of("ship-add") < index_of("mothership-added"),
   "the disposable pilot must be removed before its owned replacement exists")
assert(shared_cache.joyride.pilot == clone,
   "Joyride must reconstruct exactly one mothership pilot")

calls = {}
assert(joyride.end_joyride(), "the auxiliary ship must return")
assert(index_of("trigger:joyride_returning:TXCrewmates")
   < index_of("swap:QA Carrier:false:true"),
   "joyride_returning must be synchronous and precede shipSwap")
assert(index_of("mothership-removed")
   < index_of("swap:QA Carrier:false:true"),
   "the AI mothership must be removed before its owned replacement exists")
assert(index_of("swap:QA Carrier:false:true")
   < index_of("trigger:joyride_ended:TXCrewmates"),
   "joyride_ended must follow the completed swap")
assert(shared_cache.joyride == nil and shared_cache.player_mothership == nil,
   "return must clear the complete Joyride session")
assert(index_of("mothership-removed"),
   "return must remove the temporary mothership pilot")

print("ok - Joyride virtual lifecycle")
