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
local skill_outfit = { nameRaw = function() return "Hunter's Instinct" end }
local slot_skill_outfit = { nameRaw = function() return "The Bite" end }

local function common_pilot(hull)
   local subject = {
      shipvars = {},
      weapon_sets = {},
      intrinsic_outfits = {},
      slot_outfits = { [3] = outfit },
      ship = function() return hull end,
      faction = function() return "Player" end,
      pos = function() return "position" end,
      dir = function() return 1 end,
      vel = function() return "velocity" end,
      health = function() return 90, 80, 0 end,
      energy = function() return 70 end,
      stats = function() return { fuel = 60, fuel_consumption = 10 } end,
      outfitsList = function(self, kind)
         if kind == "intrinsic" then return self.intrinsic_outfits end
         return {}
      end,
      outfits = function(self) return self.slot_outfits end,
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
      outfitRm = function(self, kind)
         if kind == "intrinsic" then self.intrinsic_outfits = {} end
      end,
      outfitRmSlot = function(self, id) self.slot_outfits[id] = nil end,
      outfitAddSlot = function(self, name, id)
         self.slot_outfits[id] = name == "The Bite" and slot_skill_outfit or name
         return true
      end,
      outfitAddIntrinsic = function(self, name)
         self.intrinsic_outfits[#self.intrinsic_outfits + 1] =
            name == "Hunter's Instinct" and skill_outfit or name
      end,
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
   subject.shipvarPeek = function(self, name) return self.shipvars[name] end
   subject.shipvarPush = function(self, name, value)
      self.shipvars[name] = value
   end
   subject.shipvarPop = function(self, name) self.shipvars[name] = nil end
   subject.weapsetList = function(self, id)
      local result = {}
      for _slot_index, slot in ipairs(self.weapon_sets[id] or {}) do
         result[#result + 1] = slot
      end
      return result
   end
   subject.weapsetCleanup = function(self) self.weapon_sets = {} end
   subject.weapsetAdd = function(self, id, slot)
      self.weapon_sets[id] = self.weapon_sets[id] or {}
      self.weapon_sets[id][#self.weapon_sets[id] + 1] = slot
   end
   return subject
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
shuttle.outfitsList = function(self, kind)
   if kind == "intrinsic" then return self.intrinsic_outfits end
   return { outfit }
end
shuttle.setTarget = function() end

local template = common_pilot(shuttle_type)
template.name = function() return "QA Shuttle" end
template.target = function() return nil end
template.outfitsList = function() return { outfit } end
template.rm = function() record("template-removed") end

local shared_cache = {}
local ended_payload
local current_name = "QA Carrier"
local current_pilot = carrier
naev = {
   cache = function() return shared_cache end,
   trigger = function(name, payload)
      record("trigger:" .. name .. ":" .. payload.client)
      if name == "joyride_ended" then ended_payload = payload end
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
   persist_virtual_state = true,
   shipvars = { "bioshipexp", "biostage", "bio_attack1" },
   virtual_state = {
      hull = "Alpaca",
      outfits = {
         slots = { [3] = "The Bite" },
         intrinsics = { "Hunter's Instinct" },
      },
      shipvars = { bioshipexp = 300, biostage = 2, bio_attack1 = true },
      weapon_sets = { [1] = { 3 } },
   },
}))
assert(index_of("template-removed") < index_of("ship-add")
   and index_of("ship-add") < index_of("mothership-added"),
   "the disposable pilot must be removed before its owned replacement exists")
assert(shared_cache.joyride.pilot == clone,
   "Joyride must reconstruct exactly one mothership pilot")
assert(shuttle.shipvars.bioshipexp == 300
   and shuttle.shipvars.biostage == 2
   and shuttle.shipvars.bio_attack1 == true
   and shuttle.slot_outfits[3]:nameRaw() == "The Bite"
   and shuttle.intrinsic_outfits[1]:nameRaw() == "Hunter's Instinct"
   and shuttle.weapon_sets[1][1] == 3,
   "virtual launch must restore opted-in outfits, ship variables, and weapon sets")

shuttle.shipvars.bioshipexp = 900
shuttle.shipvars.biostage = 3
shuttle.shipvars.bio_attack1 = nil
shuttle.shipvars.bio_attack2 = true
shuttle.weapon_sets = { [2] = { 3 } }

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
assert(ended_payload.virtual_state.hull == "Alpaca"
   and ended_payload.virtual_state.shipvars.bioshipexp == 900
   and ended_payload.virtual_state.shipvars.biostage == 3
   and ended_payload.virtual_state.shipvars.bio_attack1 == nil
   and ended_payload.virtual_state.weapon_sets[2][1] == 3,
   "virtual return must report the latest opted-in persistent state")

print("ok - Joyride virtual lifecycle")
