.PHONY: check

check:
	lua tests/joyride.lua
	lua tests/joyride_nomad.lua
	lua tests/scanner_drone.lua
	luajit tests/joyride.lua
	luajit tests/joyride_nomad.lua
	luajit tests/scanner_drone.lua
