local enter_hooks = {}
local ship_swap_hooks = {}

hook = {
   enter = function(callback)
      enter_hooks[#enter_hooks + 1] = callback
   end,
   ship_swap = function(callback)
      ship_swap_hooks[#ship_swap_hooks + 1] = callback
   end,
}

player = {
   pilot = function()
      return {
         outfits = function()
            return {}
         end,
      }
   end,
}

dofile("events/scanner_drone.lua")
create()

assert(#enter_hooks == 1 and enter_hooks[1] == "scan_drone_enter",
   "the scanner handler must register one system-entry hook")
assert(#ship_swap_hooks == 1 and ship_swap_hooks[1] == "scan_drone_enter",
   "the scanner handler must register one ship-swap hook")

for _index = 1, 20 do
   scan_drone_enter()
end

assert(#ship_swap_hooks == 1,
   "scanner checks must not recursively register ship-swap hooks")

print("scanner drone hook tests passed")
