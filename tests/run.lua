vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.columns = 100
vim.o.lines = 40
vim.o.swapfile = false
vim.o.termguicolors = true

local C = require("color-chooser.color")
local chooser = require("color-chooser")
local ui = require("color-chooser.ui")
local count = 0
local function eq(actual, expected)
  assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end
local function near(actual, expected, tolerance)
  assert(math.abs(actual - expected) <= (tolerance or 1e-6), string.format("expected %f, got %f", expected, actual))
end
local function test(name, callback)
  local ok, err = xpcall(callback, debug.traceback)
  if ui.active then
    ui.close(ui.active)
  end
  if not ok then
    error(name .. ": " .. err)
  end
  count = count + 1
  print("ok " .. count .. " - " .. name)
end

test("hex literals preserve case, prefix, shorthand and alpha", function()
  for _, text in ipairs({ "#abc", "#ABCD", "#aabbcc", "#AABBCCDD", "0xabcdef", "0XABCDEF80" }) do
    local color, format = C.parse(text)
    assert(color, text)
    eq(C.format(color, format), text)
  end
  local color, format = C.parse("#abc")
  color.r = 0.5
  eq(C.format(color, format), "#80bbcc")
end)

test("CSS rgb numbers, percentages and alpha", function()
  for _, text in ipairs({ "rgb(255, 128, 0)", "rgba(255, 128, 0, 0.5)", "rgb(100% 50% 0% / 50%)",
    "rgb(100%, 50%, 0%)", "RGB(255 0 0)", "rgb(-5 300 0 / 200%)" }) do
    local color, format = C.parse(text)
    assert(color, text)
    near(color.r, text:find("-5", 1, true) and 0 or 1)
    local again = assert(C.parse(C.format(color, format)))
    for _, key in ipairs({ "r", "g", "b", "a" }) do near(again[key], color[key], 1 / 255) end
  end
  local color = assert(C.parse("rgba(255, 0, 0, 0)"))
  eq(color.a, 0)
end)

test("HSL hue units and conversion", function()
  for _, angle in ipairs({ "120", "120deg", "133.333333grad", ".333333333turn", "2.094395102rad", "-240deg" }) do
    local color = assert(C.parse("hsl(" .. angle .. " 100% 50% / .25)"))
    near(color.r, 0, 1e-6)
    near(color.g, 1)
    near(color.b, 0, 1e-6)
    near(color.a, 0.25)
  end
  local color, format = C.parse("hsla(240, 100%, 50%, 0.5)")
  eq(C.format(color, format), "hsla(240, 100%, 50%, 0.5)")
end)

test("malformed literals are rejected", function()
  for _, text in ipairs({ "#ab", "#abcde", "#abcdefghi", "0xabc", "rgb(1,2)", "rgba(1,2,3,nope)",
    "rgb(1 2 3 / nope)", "rgb(1 2 3 / .5 / .6)", "rgb(1,,2,3)", "rgb(1, 2 3, 4)",
    "rgb(1%, 2, 3)", "hsl(12foo 30% 40%)", "hsl(0 1 .5)", "red", "#ff0000 trailing" }) do
    assert(C.parse(text) == nil, text)
  end
end)

test("HSV and HSL round trips cover chromatic and achromatic colors", function()
  for _, r in ipairs({ 0, 0.2, 0.5, 1 }) do
    for _, g in ipairs({ 0, 0.3, 0.6, 1 }) do
      for _, b in ipairs({ 0, 0.4, 0.7, 1 }) do
        local color = { r = r, g = g, b = b, a = 0.6 }
        local h, s, v = C.rgb_to_hsv(color)
        local rgb = C.hsv_to_rgb(h, s, v, color.a)
        near(rgb.r, r); near(rgb.g, g); near(rgb.b, b); near(rgb.a, 0.6)
        local hh, ss, ll = C.rgb_to_hsl(color)
        rgb = C.hsl_to_rgb(hh, ss, ll)
        near(rgb.r, r); near(rgb.g, g); near(rgb.b, b)
      end
    end
  end
end)

test("recognition uses cursor byte positions and literal boundaries", function()
  local line = "色 = '#abc'; other = rgba(20, 40, 60, .5); last = 0x123456"
  for _, literal in ipairs({ "#abc", "rgba(20, 40, 60, .5)", "0x123456" }) do
    local first, last = line:find(literal, 1, true)
    for col = first - 1, last - 1 do
      eq(assert(C.find_at(line, col)).text, literal)
    end
    assert(not C.find_at(line, last))
  end
  for _, text in ipairs({ "foo#abc", "#abc1234", "#abcxyz", "foo0x123456", "foorgb(1,2,3)", "##abc" }) do
    for col = 0, #text - 1 do assert(not C.find_at(text, col), text) end
  end
end)

local function source(text, col)
  vim.cmd("enew!")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  vim.api.nvim_win_set_cursor(0, { 1, col or 0 })
  return buf, vim.api.nvim_get_current_win()
end

test("command loads without setup and adjustment replaces only the literal", function()
  vim.cmd("runtime plugin/color-chooser.lua")
  eq(vim.fn.exists(":ColorChooser"), 2)
  local buf = source("local color = '#FF0000' -- keep", 17)
  vim.cmd("ColorChooser")
  local session = assert(ui.active)
  eq(session.color.r, 1)
  eq(vim.bo[session.buf].modifiable, false)
  session.selected = 2
  ui.adjust(session, 1, true)
  near(session.h, 10)
  ui.apply(session)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "local color = '#FF2B00' -- keep" })
  eq(ui.active, nil)
  assert(not vim.api.nvim_buf_is_valid(session.buf))
end)

test("cancel and reset leave source unchanged", function()
  local buf = source("#abc", 1)
  local session = chooser.open()
  ui.adjust(session, 1)
  ui.cycle_format(session)
  local reset = vim.fn.maparg("r", "n", false, true).callback
  reset()
  eq(C.format(session.color, session.format), "#abc")
  ui.adjust(session, -1)
  ui.close(session)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "#abc" })
end)

test("no literal inserts default or supplied color at the tracked cursor", function()
  local buf = source("hello world", 6)
  local session = chooser.open("hsl(120 100% 50%)")
  eq(session.target, nil)
  ui.apply(session)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "hello hsl(120 100% 50%)world" })
  buf = source("text", 0)
  session = chooser.open()
  eq(C.hex(session.color), "#ff8800")
  ui.apply(session)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "#ff8800text" })
end)

test("extmarks track edits before the source literal", function()
  local buf = source("x = '#abc'", 6)
  local session = chooser.open()
  vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, { "prefix " })
  session.color = assert(C.parse("#123456"))
  ui.apply(session)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "prefix x = '#123456'" })
end)

test("source conflicts and read-only buffers refuse apply", function()
  local buf = source("#abcdef", 2)
  local session = chooser.open()
  local messages, original_notify = {}, vim.notify
  vim.notify = function(message) messages[#messages + 1] = message end
  vim.api.nvim_buf_set_text(buf, 0, 1, 0, 2, { "f" })
  ui.apply(session)
  eq(ui.active, session)
  assert(messages[1]:find("source color changed", 1, true))
  ui.close(session)
  session = chooser.open()
  vim.bo[buf].readonly = true
  ui.apply(session)
  eq(ui.active, session)
  assert(messages[2]:find("read-only", 1, true))
  vim.bo[buf].readonly = false
  vim.notify = original_notify
end)

test("mouse grid and sliders set the expected channels", function()
  source("#ff0000", 0)
  local session = chooser.open()
  local l = session.layout
  ui.click(session, l.rows.sv + l.grid_height - 1, l.x)
  near(session.v, 0)
  ui.click(session, l.rows.sv, l.x + l.grid_width * 2 - 1)
  near(session.s, 1); near(session.v, 1)
  for _, region in ipairs(session.regions) do
    if region.key == "a" then
      ui.click(session, region.row, region.x)
      near(session.color.a, 0)
      assert(C.format(session.color, session.format):match("00$"))
    end
  end
end)

test("whole-literal replacement and deletion report conflicts without errors", function()
  local old_notify, messages = vim.notify, {}
  vim.notify = function(message) messages[#messages + 1] = message end
  for _, replacement in ipairs({ "#123456", "" }) do
    local buf = source("#abcdef", 2)
    local session = chooser.open()
    vim.api.nvim_buf_set_text(buf, 0, 0, 0, 7, { replacement })
    ui.apply(session)
    eq(ui.active, session)
    eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { replacement })
    ui.close(session)
  end
  eq(#messages, 2)
  for _, message in ipairs(messages) do assert(message:find("source color changed", 1, true)) end
  vim.notify = old_notify
end)

test("wiping the picker buffer clears its window and session", function()
  source("#abc", 0)
  local session = chooser.open()
  vim.api.nvim_buf_delete(session.buf, { force = true })
  eq(ui.active, nil)
  assert(not vim.api.nvim_win_is_valid(session.win))
end)

test("gray colors keep the chosen hue while changing value", function()
  source("#ff0000", 0)
  local session = chooser.open()
  session.selected = 2
  ui.adjust(session, 1, true)
  session.selected = 6
  for _ = 1, 10 do ui.adjust(session, -1, true) end
  near(session.s, 0); near(session.h, 10)
  session.selected = 7
  ui.adjust(session, -1, true)
  near(session.h, 10)
end)

test("input callback ignores closed sessions", function()
  source("#abc", 0)
  local session = chooser.open()
  local old, callback = vim.ui.input, nil
  vim.ui.input = function(_, cb) callback = cb end
  ui.edit(session)
  vim.ui.input = old
  ui.close(session)
  callback("#ff0000")
  eq(ui.active, nil)
end)

test("external close and resize clean up the session", function()
  source("#abc", 0)
  local session = chooser.open()
  vim.api.nvim_win_close(session.win, true)
  eq(ui.active, nil)
  assert(not vim.api.nvim_buf_is_valid(session.buf))
  session = chooser.open()
  vim.o.columns, vim.o.lines = 60, 32
  vim.api.nvim_exec_autocmds("VimResized", {})
  eq(session.width, 56)
  eq(session.height, 27)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)) do
    assert(vim.fn.strdisplaywidth(line) <= session.width, line)
  end
  vim.o.columns, vim.o.lines = 40, 20
  vim.api.nvim_exec_autocmds("VimResized", {})
  eq(ui.active, nil)
  vim.o.columns, vim.o.lines = 100, 40
end)

test("picker reuses one active session and invalid arguments create none", function()
  source("#abc", 0)
  local session = chooser.open()
  chooser.open()
  eq(ui.active, session)
  ui.close(session)
  local original_notify = vim.notify
  vim.notify = function() end
  chooser.open("garbage")
  vim.notify = original_notify
  eq(ui.active, nil)
end)

test("a standard 80x24 terminal shows every control and action", function()
  source("#abc", 0)
  vim.o.columns, vim.o.lines = 80, 24
  local session = assert(chooser.open())
  eq(session.height, 19)
  eq(session.layout.compact, true)
  local lines = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
  eq(#lines, session.height)
  assert(lines[#lines]:find("Enter apply", 1, true))
  for _, line in ipairs(lines) do assert(vim.fn.strdisplaywidth(line) <= session.width, line) end
  for _, region in ipairs(session.regions) do assert(region.last_row < session.height) end
  ui.close(session)
  vim.o.columns, vim.o.lines = 100, 40
end)

print(string.format("Passed %d tests", count))
