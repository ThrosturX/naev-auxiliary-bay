local der = require "common.derelict"
local fmt = require "format"
local vntk = require "vntk"

local joyride = {}

local DEFAULT_AI = "escort_guardian"
local SPAWNED_HOOK = "joyride_mothership_spawned"
local RETURNING_HOOK = "joyride_returning"
local ENDED_HOOK = "joyride_ended"
local SHUTTLE_RETURNED_HOOK = "joyride_shuttle_returned"
local CONTROLLED_CHANGED_HOOK = "joyride_controlled_ship_changed"
local MOTHERSHIP_RESTORED_HOOK = "joyride_mothership_restored"
local session_sequence = 0

local function cache()
   return naev.cache().joyride
end

local function fail(reason)
   return false, reason
end

local function profile_value(state, key, fallback)
   local profile = state and state.profile or nil
   if profile and profile[key] ~= nil then return profile[key] end
   return fallback
end

local function owned_ship(name)
   for _, entry in ipairs(player.ships()) do
      if entry.name == name then return entry end
   end
end

local function cargo_quantity(subject)
   local quantity = 0
   for _, item in ipairs(subject:cargoList()) do
      if item.q > 0 then quantity = quantity + item.q end
   end
   return quantity
end

local function has_cargo(subject)
   return cargo_quantity(subject) > 0
end

local function has_mission_cargo(subject)
   for _, item in ipairs(subject:cargoList()) do
      if item.m and item.q > 0 then return true end
   end
   return false
end

local function regular_cargo(subject)
   local result = {}
   for _, item in ipairs(subject:cargoList()) do
      if not item.m and item.q > 0 then
         result[#result + 1] = { commodity = item.c, quantity = item.q }
      end
   end
   return result
end

local function remove_regular_cargo(subject, cargo)
   for _, item in ipairs(cargo) do
      subject:cargoRm(item.commodity, item.quantity)
   end
end

local function add_regular_cargo(subject, cargo)
   for _, item in ipairs(cargo or {}) do
      subject:cargoAdd(item.commodity, item.quantity)
   end
end

local function outfit_names(subject, kind)
   local result = {}
   for _outfit_index, installed in ipairs(subject:outfitsList(kind)) do
      result[#result + 1] = installed:nameRaw()
   end
   return result
end

local function snapshot_outfit_state(subject)
   local result = { slots = {}, intrinsics = {} }
   for id, installed in pairs(subject:outfits()) do
      if installed then result.slots[id] = installed:nameRaw() end
   end
   for _intrinsic_index, installed in ipairs(
         subject:outfitsList("intrinsic")) do
      result.intrinsics[#result.intrinsics + 1] = installed:nameRaw()
   end
   return result
end

local function restore_outfit_state(subject, saved)
   if not saved then return end
   local current = subject:outfits()
   for id, installed in pairs(current) do
      local expected = saved.slots and saved.slots[id] or nil
      if installed and installed:nameRaw() ~= expected then
         subject:outfitRmSlot(id)
      end
   end
   current = subject:outfits()
   for id, name in pairs(saved.slots or {}) do
      local installed = current[id]
      if not installed or installed:nameRaw() ~= name then
         subject:outfitAddSlot(name, id, true, true)
      end
   end
   subject:outfitRm("intrinsic")
   for _intrinsic_index, name in ipairs(saved.intrinsics or {}) do
      subject:outfitAddIntrinsic(name)
   end
end

local function snapshot_virtual_state(subject, state)
   if not subject or not state or state.kind ~= "virtual"
      or not state.profile.persist_virtual_state then return nil end
   local snapshot = {
      hull = subject:ship():nameRaw(),
      outfits = snapshot_outfit_state(subject),
      shipvars = {},
      weapon_sets = {},
   }
   for _shipvar_index, name in ipairs(state.profile.shipvars or {}) do
      local value = subject:shipvarPeek(name)
      if value ~= nil then snapshot.shipvars[name] = value end
   end
   for id = 1, 10 do
      snapshot.weapon_sets[id] = {}
      for _slot_index, slot in ipairs(subject:weapsetList(id)) do
         snapshot.weapon_sets[id][#snapshot.weapon_sets[id] + 1] = slot
      end
   end
   state.virtual_state = snapshot
   return snapshot
end

local function restore_virtual_state(subject, snapshot, shipvars)
   if not subject or not snapshot
      or snapshot.hull ~= subject:ship():nameRaw() then return end
   for _shipvar_index, name in ipairs(shipvars or {}) do
      subject:shipvarPop(name)
   end
   for name, value in pairs(snapshot.shipvars or {}) do
      subject:shipvarPush(name, value)
   end
   restore_outfit_state(subject, snapshot.outfits)
   if not snapshot.weapon_sets then return end
   subject:weapsetCleanup()
   local outfits = subject:outfits()
   for id, slots in ipairs(snapshot.weapon_sets) do
      for _slot_index, slot in ipairs(slots) do
         if outfits[slot] then subject:weapsetAdd(id, slot) end
      end
   end
end

local function owned_outfit_names(name)
   local result = {}
   for _index, installed in ipairs(player.shipOutfits(name) or {}) do
      result[#result + 1] = type(installed) == "string"
         and installed or installed:nameRaw()
   end
   return result
end

local function snapshot_mothership(subject, profile)
   local armour, shield, stress = subject:health()
   return {
      mothership = player.ship(),
      ship = subject:ship(),
      pos = subject:pos(),
      dir = subject:dir(),
      vel = subject:vel(),
      outfits = subject:outfitsList(),
      cargo = regular_cargo(subject),
      mothership_acquired = player.shipMetadata().acquired,
      armour = armour,
      shield = shield,
      stress = stress,
      energy = subject:energy(),
      fuel = subject:stats().fuel,
      profile = profile or {},
      faction = subject:faction(),
   }
end

local function mothership_faction(state)
   if state.mothership_faction then return state.mothership_faction end
   local base = profile_value(state, "faction", state.faction)
   local name = profile_value(state, "name", state.mothership)
   state.mothership_faction = faction.dynAdd(base, name, name, {
      ai = profile_value(state, "ai", DEFAULT_AI),
      clear_enemies = true,
   })
   return state.mothership_faction
end

local function configure_mothership(state, subject)
   subject:setVisplayer(true)
   subject:setNoClear(true)
   subject:setNoLand(true)
   subject:setNoJump(true)
   subject:setActiveBoard(true)
   subject:setHilight(true)
   subject:setFriendly(true)
   subject:setInvincPlayer(true)
   state.pilot = subject
   naev.trigger(SPAWNED_HOOK, {
      client = profile_value(state, "client", "joyride"),
      pilot = subject,
   })
   return subject
end

function joyride.spawn_mothership()
   local state = cache()
   if not state then return nil end
   if state.follow_mothership == false then return nil end
   if state.pilot and state.pilot:exists() then return state.pilot end
   if state.hook then
      hook.rm(state.hook)
      state.hook = nil
   end

   local name = profile_value(state, "name", state.mothership)
   local ai_name = profile_value(state, "ai", DEFAULT_AI)
   local mothership = pilot.add(state.ship, mothership_faction(state), state.pos,
      name, { ai = ai_name, naked = true })
   mothership:setDir(state.dir)
   mothership:setVel(state.vel)
   for _, installed in ipairs(state.outfits) do
      mothership:outfitAdd(installed)
   end
   add_regular_cargo(mothership, state.cargo)
   if state.armour then
      mothership:setHealth(state.armour, state.shield, state.stress)
      mothership:setEnergy(state.energy)
      mothership:setFuel(state.fuel)
   end
   return configure_mothership(state, mothership)
end

function joyride.follow_mothership(enabled)
   local state = cache()
   if not state then return fail("no Joyride session is active") end
   state.follow_mothership = enabled ~= false
   return true
end

function joyride.mothership_follows()
   local state = cache()
   return state ~= nil and state.follow_mothership ~= false
end

local function begin_session(state)
   session_sequence = session_sequence + 1
   state.token = session_sequence
   naev.cache().joyride = state
   -- Evo Factions reads these original Joyride cache fields directly. Keep
   -- their meaning stable without making Evo a dependency of Joyride.
   naev.cache().player_mothership = state.mothership
   player.allowSave(false)
   if state.profile.noland then
      state.noland = state.profile.noland
      player.landAllow(false, state.noland)
   end
end

function joyride.swap_to_subship(in_pilot, template, acquired, profile)
   if cache() then return fail("a Joyride session is already active") end
   acquired = acquired or fmt.f(
      _("Belongs in the bay of your {mothership}."),
      { mothership = in_pilot:ship():name() })

   local state = snapshot_mothership(in_pilot, profile)
   state.kind = "virtual"
   state.subship = template:ship()
   begin_session(state)

   remove_regular_cargo(in_pilot, state.cargo)
   in_pilot:hookClear()
   local desired_fuel = template:stats().fuel_consumption
   local reserved_fuel
   if in_pilot:stats().fuel > desired_fuel + in_pilot:stats().fuel_consumption then
      reserved_fuel = desired_fuel
      in_pilot:setFuel(in_pilot:stats().fuel - reserved_fuel)
   end

   local template_name = template:name()
   local template_pos, template_vel = template:pos(), template:vel()
   local template_dir, template_target = template:dir(), template:target()
   local template_outfits = template:outfitsList()
   local armour, shield, stress = template:health()
   local energy = template:energy()
   template:rm()

   state.virtual_name = player.shipAdd(state.subship:nameRaw(), template_name,
      acquired, true)
   player.shipSwap(state.virtual_name, false, false)
   local controlled = player.pilot()
   controlled:setVel(template_vel)
   controlled:setDir(template_dir)
   controlled:setPos(template_pos)
   controlled:setTarget(template_target)
   controlled:setFuel(reserved_fuel or 0)
   controlled:outfitRm("all")
   controlled:outfitRm("cores")
   for _, installed in ipairs(template_outfits) do
      controlled:outfitAdd(installed, 1, true)
   end
   restore_virtual_state(controlled, state.profile.virtual_state,
      state.profile.shipvars)
   controlled:setHealth(armour, shield, stress)
   controlled:setEnergy(energy)
   local called, spawned = pcall(joyride.spawn_mothership)
   if not called or not spawned then
      if state.hook then hook.rm(state.hook) end
      if state.pilot and state.pilot:exists() then state.pilot:rm() end
      player.shipSwap(state.mothership, false, true)
      local restored = player.pilot()
      add_regular_cargo(restored, state.cargo)
      restored:setHealth(state.armour, state.shield, state.stress)
      restored:setEnergy(state.energy)
      restored:setFuel(state.fuel)
      naev.cache().joyride = nil
      naev.cache().player_mothership = nil
      player.allowSave(true)
      player.landAllow(true)
      return fail(called and "the mothership could not be spawned" or spawned)
   end
   der.sfxUnboard()
   return controlled
end

local function begin_owned_state(state, controlled_name)
   state.kind = "owned"
   state.controlled = controlled_name
   begin_session(state)
   return true
end

function joyride.begin_owned_sortie(name, template, profile)
   if cache() then return fail("a Joyride session is already active") end
   local destination = owned_ship(name)
   if not destination then return fail("the assigned owned ship is unavailable") end
   if destination.deployed then return fail("the assigned owned ship is already deployed") end
   if name == player.ship() then return fail("the assigned ship is already controlled") end
   if has_mission_cargo(player.pilot()) then
      return fail("mission cargo prevents changing seats")
   end
   if not template or not template:exists() then
      return fail("the launched ship is unavailable")
   end

   local mothership = player.pilot()
   local state = snapshot_mothership(mothership, profile)
   remove_regular_cargo(mothership, state.cargo)
   mothership:hookClear()

   local pos, dir, vel = template:pos(), template:dir(), template:vel()
   local armour, shield, stress = template:health()
   local energy, fuel = template:energy(), template:stats().fuel
   local carried_cargo = regular_cargo(template)
   template:rm()
   begin_owned_state(state, name)
   player.shipSwap(name, true, false)
   local controlled = player.pilot()
   controlled:setPos(pos)
   controlled:setDir(dir)
   controlled:setVel(vel)
   controlled:setHealth(armour, shield, stress)
   controlled:setEnergy(energy)
   controlled:setFuel(fuel)
   controlled:cargoRm("all")
   add_regular_cargo(controlled, carried_cargo)
   local called, spawned = pcall(joyride.spawn_mothership)
   if not called or not spawned then
      if state.hook then hook.rm(state.hook) end
      if state.pilot and state.pilot:exists() then state.pilot:rm() end
      player.shipSwap(state.mothership, true, false)
      add_regular_cargo(player.pilot(), state.cargo)
      naev.cache().joyride = nil
      naev.cache().player_mothership = nil
      player.allowSave(true)
      player.landAllow(true)
      return fail(called and "the mothership could not be spawned" or spawned)
   end
   der.sfxUnboard()
   return controlled
end

function joyride.begin_stored_owned_sortie(mothership_name, profile, position,
      direction)
   if cache() then return fail("a Joyride session is already active") end
   local mothership = owned_ship(mothership_name)
   if not mothership then return fail("the stored mothership is not owned") end
   if player.ship() == mothership_name then
      return fail("select a stored craft before beginning its sortie")
   end
   if not position then return fail("the stored mothership position is required") end

   local state = {
      mothership = mothership_name,
      ship = mothership.ship,
      pos = position,
      dir = direction or 0,
      vel = vec2.new(0, 0),
      outfits = player.shipOutfits(mothership_name) or {},
      cargo = {},
      mothership_acquired = (player.shipMetadata(mothership_name) or {}).acquired,
      profile = profile or {},
      faction = player.pilot():faction(),
   }
   begin_owned_state(state, player.ship())
   local called, spawned = pcall(joyride.spawn_mothership)
   if not called or not spawned then
      if state.hook then hook.rm(state.hook) end
      if state.pilot and state.pilot:exists() then state.pilot:rm() end
      naev.cache().joyride = nil
      naev.cache().player_mothership = nil
      player.allowSave(true)
      player.landAllow(true)
      return fail(called and "the stored mothership could not be spawned"
         or spawned)
   end
   return true
end

local function validate_landable()
   local state = cache()
   if not state then return nil, "no Joyride session is active" end
   if not state.profile.landable then
      return nil, "the active Joyride profile does not allow landing"
   end
   return state
end

function joyride.land()
   local state, reason = validate_landable()
   if not state then return fail(reason) end
   snapshot_virtual_state(player.pilot(), state)
   if state.pilot and state.pilot:exists() then
      state.pos, state.dir, state.vel = state.pilot:pos(),
         state.pilot:dir(), state.pilot:vel()
      state.cargo = regular_cargo(state.pilot)
      state.outfits = state.pilot:outfitsList()
      state.armour, state.shield, state.stress = state.pilot:health()
      state.energy = state.pilot:energy()
      state.fuel = state.pilot:stats().fuel
      state.pilot:rm()
   end
   state.pilot = nil
   player.allowSave(false)
   return true
end

function joyride.takeoff()
   local state, reason = validate_landable()
   if not state then return fail(reason) end
   player.allowSave(false)
   if state.follow_mothership == false then return true end
   return joyride.spawn_mothership() ~= nil
end

function joyride.landed_ship_swap(new_name)
   local state = cache()
   if not state or not state.profile.landable or state.pilot
      or state.internal_swap or not player.isLanded() then return false end
   if player.ship() ~= new_name then return false end
   if new_name == state.mothership then
      local client = profile_value(state, "client", "joyride")
      local returned_kind = state.kind
      local returned_name = state.kind == "owned" and state.controlled or nil
      local virtual_name = state.virtual_name
      local returned_hull = state.kind == "virtual"
         and state.subship:nameRaw() or nil
      local returned_outfits
      local returned_state
      if state.kind == "virtual" and virtual_name
         and state.profile.persist_virtual_state and owned_ship(virtual_name) then
         state.internal_swap = true
         player.shipSwap(virtual_name, true, false)
         returned_outfits = outfit_names(player.pilot(), "all")
         returned_state = snapshot_virtual_state(player.pilot(), state)
         player.shipSwap(new_name, true, false)
         state.internal_swap = nil
      elseif state.kind == "virtual" and virtual_name then
         returned_outfits = owned_outfit_names(virtual_name)
      end
      naev.cache().joyride = nil
      naev.cache().player_mothership = nil
      player.allowSave(true)
      player.landAllow(true)
      if virtual_name and virtual_name ~= new_name and owned_ship(virtual_name) then
         player.shipRm(virtual_name)
      end
      naev.trigger(ENDED_HOOK, {
         client = client,
         returned_kind = returned_kind,
         returned_name = returned_name,
         landed = true,
         hull = returned_hull,
         outfits = returned_outfits,
         virtual_state = returned_state,
      })
      return true
   end

   local client = profile_value(state, "client", "joyride")
   local previous = state.kind == "owned" and state.controlled
      or state.virtual_name
   if state.kind == "virtual" then
      local virtual_name = state.virtual_name
      state.kind = "owned"
      state.virtual_name = nil
      if virtual_name and virtual_name ~= new_name and owned_ship(virtual_name) then
         player.shipRm(virtual_name)
      end
      naev.trigger(SHUTTLE_RETURNED_HOOK, {
         client = client,
         returned_kind = "virtual",
      })
   end
   state.controlled = new_name
   naev.trigger(CONTROLLED_CHANGED_HOOK, {
      client = client,
      previous = previous,
      controlled = new_name,
   })
   return true
end

function joyride.restore_sold_mothership(ship_type, name)
   local state = cache()
   if not state or state.pilot or not state.profile.landable
      or name ~= state.mothership then return false end
   local controlled = player.ship()
   player.shipAdd(ship_type:nameRaw(), name, state.mothership_acquired, true)
   state.internal_swap = true
   player.shipSwap(name, true, false)
   local restored = player.pilot()
   restored:outfitRm("all")
   restored:outfitRm("cores")
   for _, installed in ipairs(state.outfits) do
      restored:outfitAdd(installed, 1, true)
   end
   player.pay(-restored:worth())
   player.shipSwap(controlled, true, false)
   state.internal_swap = nil
   naev.trigger(MOTHERSHIP_RESTORED_HOOK, {
      client = profile_value(state, "client", "joyride"),
      name = name,
   })
   return true
end

function joyride.ship_bought(ship_type, traded)
   local state = cache()
   if not state or not state.profile.trade_replacement then
      return fail("the active Joyride profile does not allow replacement")
   end
   if not traded or state.kind ~= "virtual" then
      return fail("the purchase did not replace the virtual shuttle")
   end
   state.subship = ship_type
   state.virtual_name = player.ship()
   return true
end

function joyride.handoff_to_owned(name)
   local state = cache()
   if not state or not state.profile.owned_handoff then
      return fail("the active Joyride profile does not allow this handoff")
   end
   if state.kind ~= "virtual" or player.ship() ~= state.virtual_name then
      return fail("the virtual shuttle is not currently controlled")
   end
   local destination = owned_ship(name)
   if not destination then return fail("the requested ship is not owned") end
   if destination.deployed then return fail("the requested ship is deployed") end
   if has_cargo(player.pilot()) then return fail("the virtual shuttle must be empty") end

   local client = profile_value(state, "client", "joyride")
   local returned_state = snapshot_virtual_state(player.pilot(), state)
   naev.trigger(SHUTTLE_RETURNED_HOOK, {
      client = client,
      returned_kind = "virtual",
      hull = player.pilot():ship():nameRaw(),
      outfits = outfit_names(player.pilot()),
      virtual_state = returned_state,
   })
   local virtual_name = state.virtual_name
   state.internal_swap = true
   player.shipSwap(name, true, false)
   state.internal_swap = nil
   player.shipRm(virtual_name)
   state.kind = "owned"
   state.controlled = name
   state.virtual_name = nil
   return true
end

function joyride.end_joyride(options)
   options = options or {}
   local state = cache()
   if not state then return fail("no Joyride session is active") end
   if not state.pilot or not state.pilot:exists() then
      return fail("the mothership is not available")
   end
   if state.kind == "virtual" and player.pilot():ship() ~= state.subship then
      vntk.msg(_("Docking Error"), _(
         "The ship you are in does not fit in the auxiliary bay. Return with the ship you launched before trying to dock."))
      player.commClose()
      return fail("the controlled ship is not the virtual shuttle")
   end
   if state.kind == "owned" and player.ship() ~= state.controlled then
      return fail("the active owned ship does not match the Joyride session")
   end

   local seat_transfer = options.seat_transfer == true
   if seat_transfer and has_cargo(player.pilot()) then
      return fail("unload this craft before changing seats")
   end
   if not seat_transfer and cargo_quantity(player.pilot()) > state.pilot:cargoFree() then
      return fail("the mothership does not have enough free cargo space")
   end

   local returned_kind = state.kind
   local returned_name = state.kind == "owned" and state.controlled or nil
   local returned_hull = player.pilot():ship():nameRaw()
   local returned_outfits = outfit_names(player.pilot(),
      state.profile.persist_virtual_state and "all" or nil)
   local returned_state = snapshot_virtual_state(player.pilot(), state)
   local carried_fuel = state.kind == "virtual" and player.pilot():stats().fuel or 0
   local client = profile_value(state, "client", "joyride")
   local returned_armour, returned_shield, returned_stress =
      player.pilot():health()
   local returned_armour_max = player.pilot():stats().armour

   local return_pos, return_dir, return_vel = state.pilot:pos(),
      state.pilot:dir(), state.pilot:vel()
   local mothership_cargo = regular_cargo(state.pilot)
   naev.trigger(RETURNING_HOOK, {
      client = client,
      returned_kind = returned_kind,
      returned_name = returned_name,
      seat_transfer = seat_transfer,
      armour = returned_armour,
      shield = returned_shield,
      stress = returned_stress,
      armour_max = returned_armour_max,
   })
   player.pilot():hookClear()
   if state.hook then
      hook.rm(state.hook)
      state.hook = nil
   end
   state.pilot:rm()
   state.pilot = nil
   player.shipSwap(state.mothership, seat_transfer, state.kind == "virtual")
   local player_pilot = player.pilot()
   player_pilot:setPos(return_pos)
   player_pilot:setDir(return_dir)
   player_pilot:setVel(return_vel)
   player_pilot:setFuel(player_pilot:stats().fuel + carried_fuel)
   add_regular_cargo(player_pilot, mothership_cargo)

   player.allowSave(true)
   player.landAllow(true)
   der.sfxBoard()
   naev.cache().joyride = nil
   naev.cache().player_mothership = nil
   naev.trigger(ENDED_HOOK, {
      client = client,
      returned_kind = returned_kind,
      returned_name = returned_name,
      seat_transfer = seat_transfer,
      hull = returned_hull,
      outfits = returned_outfits,
      virtual_state = returned_state,
   })
   return true
end

return joyride
