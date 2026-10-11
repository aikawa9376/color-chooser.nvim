.PHONY: test
test:
	nvim --headless --clean -u NONE -l tests/run.lua
