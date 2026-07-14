.PHONY: check

check:
	lua tests/joyride.lua
	lua tests/joyride_nomad.lua
	luajit tests/joyride.lua
	luajit tests/joyride_nomad.lua
