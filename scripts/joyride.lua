local der = require "common.derelict"
local fmt = require "format"
local vntk = require "vntk"

local joyride = {}

local DEFAULT_AI = "escort_guardian"
local SPAWNED_HOOK = "joyride_mothership_spawned"
local ENDED_HOOK = "joyride_ended"
local SHUTTLE_RETURNED_HOOK = "joyride_shuttle_returned"
local MOTHERSHIP_RESTORED_HOOK = "joyride_mothership_restored"

local function cache()
   return naev.cache().joyride
end

local function profile_value(key, fallback)
   local state = cache()
   local profile = state and state.profile or nil
   if profile and profile[key] ~= nil then
      return profile[key]
   end
   return fallback
end

local function mothership_faction(state)
   local base = profile_value("faction", player.pilot():faction())
   local name = profile_value("name", state.mothership)
   return faction.dynAdd(base, name, name, {
      ai = profile_value("ai", DEFAULT_AI),
      clear_enemies = true,
   })
end

local function restore_cargo(pilot, cargo)
   for _, item in ipairs(cargo) do
      if not item.m then
         pilot:cargoAdd(item.c, item.q)
      end
   end
end

local function fail(reason)
   return false, reason
end

local function owned_ship(name)
   for _, entry in ipairs(player.ships()) do
      if entry.name == name then
         return entry
      end
   end
end

local function has_mission_cargo(pilot)
   for _, item in ipairs(pilot:cargoList()) do
      if item.m and item.q > 0 then
         return true
      end
   end
   return false
end

local function has_cargo(pilot)
   for _, item in ipairs(pilot:cargoList()) do
      if item.q > 0 then
         return true
      end
   end
   return false
end

local function outfit_names(pilot)
   local outfits = {}
   for _, outfit in ipairs(pilot:outfitsList()) do
      outfits[#outfits + 1] = outfit:nameRaw()
   end
   return outfits
end

local function hull_name(pilot)
   return pilot:ship():nameRaw()
end

local function validate_profile(flag)
   local state = cache()
   if not state then
      return nil, "no Joyride session is active"
   end
   if not state.profile[flag] then
      return nil, "the active Joyride profile does not allow this operation"
   end
   return state
end

function joyride.spawn_mothership(clone)
   local state = cache()
   if not state then
      return nil
   end
   if not clone and state.pilot and state.pilot:exists() then
      return state.pilot
   end

   if state.hook then
      hook.rm(state.hook)
      state.hook = nil
   end

   local ai_name = profile_value("ai", DEFAULT_AI)
   local pilot_name = profile_value("name", state.mothership)
   local fakefac = mothership_faction(state)
   local mothership

   if clone then
      mothership = clone
      mothership:setFaction(fakefac)
      mothership:rename(pilot_name)
      restore_cargo(mothership, state.cargo)
   else
      mothership = pilot.add(state.ship, fakefac, state.pos, pilot_name, {
         ai = ai_name,
         naked = true,
      })
      mothership:setDir(state.dir)
      mothership:setVel(state.vel)
      for _, outfit in ipairs(state.outfits) do
         mothership:outfitAdd(outfit)
      end
      restore_cargo(mothership, state.cargo)
   end

   mothership:setVisplayer(true)
   mothership:setNoClear(true)
   mothership:setNoLand(true)
   mothership:setNoJump(true)
   mothership:setActiveBoard(true)
   mothership:setHilight(true)
   mothership:setFriendly(true)
   mothership:setInvincPlayer(true)
   state.pilot = mothership

   naev.trigger(SPAWNED_HOOK, {
      client = profile_value("client", "joyride"),
      pilot = mothership,
   })
   return mothership
end

function joyride.swap_to_subship(in_pilot, template, acquired, profile)
   acquired = acquired or fmt.f(
      _("Belongs in the bay of your {mothership}."),
      { mothership = in_pilot:ship():name() }
   )

   local ship_type = template:ship()
   local ship_name = template:name()
   local state = {
      mothership = player.ship(),
      ship = in_pilot:ship(),
      subship = ship_type,
      pos = in_pilot:pos(),
      dir = in_pilot:dir(),
      vel = in_pilot:vel(),
      outfits = in_pilot:outfitsList(),
      cargo = in_pilot:cargoList(),
      mothership_acquired = player.shipMetadata().acquired,
      profile = profile or {},
      kind = "virtual",
   }
   naev.cache().joyride = state

   for _, item in ipairs(state.cargo) do
      if not item.m then
         in_pilot:cargoRm(item.c, item.q)
      end
   end

   local desired_fuel = template:stats().fuel_consumption
   local reserved_fuel
   if in_pilot:stats().fuel > desired_fuel + in_pilot:stats().fuel_consumption then
      reserved_fuel = desired_fuel
      in_pilot:setFuel(in_pilot:stats().fuel - reserved_fuel)
   end

   in_pilot:hookClear()

   -- pilot:clone() does not copy an AI. Assign one immediately so other
   -- pilots can safely scan the clone as soon as this callback returns.
   local clone = in_pilot:clone()
   clone:changeAI(profile_value("ai", DEFAULT_AI))

   local newship = player.shipAdd(ship_type:nameRaw(), ship_name, acquired, true)
   state.virtual_name = newship
   player.shipSwap(newship, false, false)
   in_pilot = player.pilot()
   in_pilot:setVel(template:vel())
   in_pilot:setDir(template:dir())
   in_pilot:setPos(template:pos())
   in_pilot:setTarget(template:target())
   in_pilot:setFuel(0)
   in_pilot:outfitRm("all")
   in_pilot:outfitRm("cores")
   for _, outfit in ipairs(template:outfitsList()) do
      in_pilot:outfitAdd(outfit, 1, true)
   end

   player.allowSave(false)
   der.sfxUnboard()
   local armour, shield, stress = template:health()
   local energy = template:energy()
   template:rm()
   in_pilot:setHealth(armour, shield, stress)
   in_pilot:setEnergy(energy)

   joyride.spawn_mothership(clone)
   if state.profile.noland then
      state.noland = state.profile.noland
      player.landAllow(false, state.noland)
   end
   if reserved_fuel then
      in_pilot:setFuel(reserved_fuel)
   end
   naev.cache().player_mothership = state.mothership
   return in_pilot
end

function joyride.land()
   local state, reason = validate_profile("landable")
   if not state then
      return fail(reason)
   end
   if state.pilot and state.pilot:exists() then
      state.pos = state.pilot:pos()
      state.dir = state.pilot:dir()
      state.vel = state.pilot:vel()
      state.pilot:rm()
   end
   state.pilot = nil
   player.allowSave(false)
   return true
end

function joyride.takeoff()
   local state, reason = validate_profile("landable")
   if not state then
      return fail(reason)
   end
   player.allowSave(false)
   joyride.spawn_mothership()
   return true
end

function joyride.guard_landed_ship_swap(new_name, old_name)
   local state = cache()
   if not state or not state.profile.landed_ship_lock
      or state.pilot ~= nil or old_name == nil then
      return false
   end

   local ignored = state.ignored_landed_swap
   if ignored and ignored.new_name == new_name
      and ignored.old_name == old_name then
      state.ignored_landed_swap = nil
      return false
   end
   if player.ship() ~= new_name or not owned_ship(old_name) then
      return false
   end

   -- Naev exposes ship_swap only after the equipment screen has changed ships.
   -- The handler defers this check so a Trade or Joyride handoff can remove the
   -- old ship first. If it still exists, this was only an equipment-screen
   -- inspection and the craft that actually landed must remain controlled.
   state.ignored_landed_swap = {
      new_name = old_name,
      old_name = new_name,
   }
   player.shipSwap(old_name, false, false)
   return true
end

function joyride.restore_sold_mothership(ship_type, name)
   local state = cache()
   if not state or not state.profile.protect_mothership_sale
      or state.pilot ~= nil or name ~= state.mothership then
      return false
   end

   local controlled = player.ship()
   player.shipAdd(ship_type:nameRaw(), name, state.mothership_acquired, true)
   player.shipSwap(name, true, false)
   player.pilot():outfitRm("all")
   player.pilot():outfitRm("cores")
   for _, outfit in ipairs(state.outfits) do
      player.pilot():outfitAdd(outfit, 1, true)
   end
   player.pay(-player.pilot():worth())
   naev.trigger(MOTHERSHIP_RESTORED_HOOK, {
      client = profile_value("client", "joyride"),
      name = name,
   })
   state.ignored_landed_swap = {
      new_name = controlled,
      old_name = name,
   }
   player.shipSwap(controlled, true, false)
   return true
end

function joyride.ship_bought(ship_type, traded)
   local state, reason = validate_profile("trade_replacement")
   if not state then
      return fail(reason)
   end
   if not traded or state.kind ~= "virtual" then
      return fail("the purchase did not replace the virtual shuttle")
   end
   state.subship = ship_type
   state.virtual_name = player.ship()
   return true
end

function joyride.handoff_to_owned(name)
   local state, reason = validate_profile("owned_handoff")
   if not state then
      return fail(reason)
   end
   if state.kind ~= "virtual" or player.ship() ~= state.virtual_name then
      return fail("the virtual shuttle is not currently controlled")
   end
   local destination = owned_ship(name)
   if not destination then
      return fail("the requested ship is not owned")
   end
   if destination.deployed then
      return fail("the requested ship is deployed")
   end
   if has_cargo(player.pilot()) then
      return fail("the virtual shuttle must be empty")
   end

   local client = profile_value("client", "joyride")
   naev.trigger(SHUTTLE_RETURNED_HOOK, {
      client = client,
      returned_kind = "virtual",
      hull = hull_name(player.pilot()),
      outfits = outfit_names(player.pilot()),
   })
   local virtual_name = state.virtual_name
   player.shipSwap(name, true, false)
   player.shipRm(virtual_name)
   state.kind = "owned"
   state.controlled = name
   state.virtual_name = nil
   return true
end

function joyride.launch_owned(name)
   local state, reason = validate_profile("owned_escorts")
   if not state then
      return fail(reason)
   end
   local entry = owned_ship(name)
   if not entry then
      return fail("the requested ship is not owned")
   end
   if name == state.mothership or name == state.virtual_name
      or name == player.ship() then
      return fail("the requested ship cannot be deployed")
   end
   if entry.deployed then
      return fail("the requested ship is already deployed")
   end
   player.shipDeploy(name, true, true)
   return true
end

function joyride.recall_owned(name)
   local state, reason = validate_profile("owned_escorts")
   if not state then
      return fail(reason)
   end
   local entry = owned_ship(name)
   if not entry then
      return fail("the requested ship is not owned")
   end
   if name == state.mothership or name == state.virtual_name then
      return fail("the requested ship cannot be recalled")
   end
   if not entry.deployed then
      return fail("the requested ship is not deployed")
   end
   player.shipDeploy(name, false, false)
   return true
end

function joyride.borrow_owned(name, profile)
   local state = cache()
   if not state then
      if not profile or not profile.owned_escorts then
         return fail("the requested Joyride profile does not allow owned escorts")
      end
      local destination = owned_ship(name)
      if not destination then
         return fail("the requested ship is not owned")
      end
      if not destination.deployed then
         return fail("the requested ship is not deployed")
      end
      if name == player.ship() then
         return fail("the currently controlled ship cannot be borrowed")
      end
      if has_mission_cargo(player.pilot()) then
         return fail("mission cargo prevents changing ships")
      end

      local mothership = player.pilot()
      state = {
         mothership = player.ship(),
         ship = mothership:ship(),
         pos = mothership:pos(),
         dir = mothership:dir(),
         vel = mothership:vel(),
         outfits = mothership:outfitsList(),
         cargo = mothership:cargoList(),
         mothership_acquired = player.shipMetadata().acquired,
         profile = profile,
         kind = "owned",
         controlled = name,
      }
      naev.cache().joyride = state
      naev.cache().player_mothership = state.mothership

      for _, item in ipairs(state.cargo) do
         if not item.m then
            mothership:cargoRm(item.c, item.q)
         end
      end
      mothership:hookClear()
      local clone = mothership:clone()
      clone:changeAI(profile.ai or DEFAULT_AI)

      player.shipDeploy(name, false, false)
      player.shipSwap(name, true, false)
      player.allowSave(false)
      joyride.spawn_mothership(clone)
      return true
   end

   local reason
   state, reason = validate_profile("owned_escorts")
   if not state then return fail(reason) end
   if state.kind ~= "owned" then
      return fail("an owned ship must be controlled before changing seats")
   end
   if player.ship() ~= state.controlled then
      return fail("the active owned ship does not match the Joyride session")
   end
   local destination = owned_ship(name)
   if not destination then
      return fail("the requested ship is not owned")
   end
   if not destination.deployed then
      return fail("the requested ship is not deployed")
   end
   if name == state.mothership then
      return fail("use end_joyride to return to the mothership")
   end
   if has_mission_cargo(player.pilot()) then
      return fail("mission cargo prevents changing ships")
   end

   local previous = player.ship()
   player.shipDeploy(name, false, false)
   player.shipSwap(name, true, false)
   player.shipDeploy(previous, true, true)
   state.controlled = name
   return true
end

function joyride.end_joyride(options)
   options = options or {}
   local state = cache()
   if not state then
      return fail("no Joyride session is active")
   end
   if not state.pilot or not state.pilot:exists() then
      return fail("the mothership is not available")
   end
   if state.kind == "virtual" and player.pilot():ship() ~= state.subship then
      vntk.msg(
         _("Docking Error"),
         _("The ship you are in does not fit in the auxiliary bay. Return with the ship you launched before trying to dock.")
      )
      player.commClose()
      return fail("the controlled ship is not the virtual shuttle")
   end

   if state.kind == "virtual" and state.profile.landable
      and has_cargo(player.pilot()) then
      return fail("the virtual shuttle must be empty")
   end
   if state.kind == "owned" and has_mission_cargo(player.pilot()) then
      return fail("mission cargo prevents returning to the mothership")
   end
   if state.kind == "owned" and player.ship() ~= state.controlled then
      return fail("the active owned ship does not match the Joyride session")
   end

   player.pilot():hookClear()
   local returned_kind = state.kind
   local returned_name = state.kind == "owned" and state.controlled or nil
   local returned_hull = hull_name(player.pilot())
   local returned_outfits = outfit_names(player.pilot())
   local carried_fuel = state.kind == "virtual" and player.pilot():stats().fuel or 0

   player.shipSwap(state.mothership, state.kind == "owned", state.kind == "virtual")
   player.pilot():setPos(state.pilot:pos())
   player.pilot():setDir(state.pilot:dir())
   player.pilot():setVel(state.pilot:vel())
   player.pilot():setFuel(player.pilot():stats().fuel + carried_fuel)
   for _, item in ipairs(state.pilot:cargoList()) do
      state.pilot:cargoRm(item.c, item.q)
      player.pilot():cargoAdd(item.c, item.q)
   end
   state.pilot:rm()

   -- Some clients use mothership hail as a seat transfer rather than a recall.
   -- Restore the owned craft as a vanilla escort after control returns to the
   -- mothership. Virtual shuttles are still consumed by the bay as usual.
   local redeployed = returned_name and options.redeploy_owned == true
   if redeployed then
      player.shipDeploy(returned_name, true, true)
   end

   local client = profile_value("client", "joyride")
   player.allowSave(true)
   player.landAllow(true)
   der.sfxBoard()
   naev.cache().joyride = nil
   naev.cache().player_mothership = nil
   naev.trigger(ENDED_HOOK, {
      client = client,
      returned_kind = returned_kind,
      redeployed = redeployed == true,
      hull = returned_hull,
      outfits = returned_outfits,
   })
   return true
end

return joyride
