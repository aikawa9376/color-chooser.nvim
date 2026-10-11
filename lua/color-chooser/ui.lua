local C = require("color-chooser.color")
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("color-chooser")
local source_ns = api.nvim_create_namespace("color-chooser-source")
local controls = { "sv", "h", "r", "g", "b", "s", "v", "a" }

local function notify(message)
  vim.notify("ColorChooser: " .. message, vim.log.levels.WARN)
end

local function alive(session)
  return M.active == session and api.nvim_buf_is_valid(session.buf) and api.nvim_win_is_valid(session.win)
end

local function contrast(color)
  return color.r * 0.299 + color.g * 0.587 + color.b * 0.114 > 0.55 and "#161616" or "#ffffff"
end

local function blend(color, base)
  local a = color.a or 1
  return { r = color.r * a + base * (1 - a), g = color.g * a + base * (1 - a), b = color.b * a + base * (1 - a) }
end

local function dimensions(config)
  local width = math.min(math.floor(config.width), vim.o.columns - 4)
  local height = math.min(math.floor(config.height), vim.o.lines - vim.o.cmdheight - 4)
  if width < 44 or height < 19 then
    return nil
  end
  return width, height
end

local function layout(session)
  local compact = session.height < 28
  local grid_height = session.height - (compact and 15 or 22)
  local grid_width = math.floor((session.width - 8) / 2)
  local rows = { sv = compact and 3 or 5 }
  rows.h = rows.sv + grid_height + (compact and 0 or 1)
  rows.r, rows.g, rows.b = rows.h + (compact and 1 or 2), rows.h + (compact and 2 or 3), rows.h + (compact and 3 or 4)
  rows.s, rows.v, rows.a = rows.h + (compact and 4 or 6), rows.h + (compact and 5 or 7), rows.h + (compact and 6 or 8)
  rows.format, rows.code = rows.h + (compact and 7 or 10), rows.h + (compact and 8 or 11)
  rows.help = rows.h + (compact and 9 or 13)
  session.layout = { grid_height = grid_height, grid_width = grid_width, rows = rows, x = 4,
    compact = compact, bar_width = session.width - 20 }
end

function M.render(session)
  if not alive(session) then
    return
  end
  local l = session.layout
  local lines, highlights, regions = {}, {}, {}
  for i = 1, session.height do
    lines[i] = ""
  end
  local function line(row, text)
    lines[row + 1] = text
  end
  local function paint(row, first, last, color, selected)
    local hex = C.hex(color)
    local group = "ColorChooserCell_" .. row .. "_" .. first
    local signature = hex .. tostring(selected)
    if session.highlights[group] ~= signature then
      api.nvim_set_hl(session.hl_ns, group, { bg = hex, fg = contrast(color), bold = selected or false })
      session.highlights[group] = signature
    end
    highlights[#highlights + 1] = { group, row, first, last }
  end
  local current = session.color
  local value = C.format(current, session.format)
  if not l.compact then
    line(0, "  " .. (session.target and "Replace color under cursor" or "Insert color at cursor"))
  end
  local half = math.floor((session.width - 6) / 2)
  line(l.compact and 0 or 1, "  Original" .. string.rep(" ", half - 8) .. "  New")
  for row = l.compact and 1 or 2, l.compact and 1 or 3 do
    line(row, "  " .. string.rep(" ", half) .. "  " .. string.rep(" ", half))
    for x = 0, half - 1 do
      local base = (math.floor(x / 2) + row) % 2 == 0 and 0.35 or 0.65
      paint(row, 2 + x, 3 + x, blend(session.original, base))
      paint(row, 4 + half + x, 5 + half + x, blend(current, base))
    end
  end
  line(l.rows.sv - 1, "  " .. (session.selected == 1 and "> " or "  ") .. "Saturation / Value")
  local selected_x = math.floor(session.s * (l.grid_width - 1) + 0.5)
  local selected_y = math.floor((1 - session.v) * (l.grid_height - 1) + 0.5)
  for y = 0, l.grid_height - 1 do
    local chunks = { string.rep(" ", l.x) }
    for x = 0, l.grid_width - 1 do
      local selected = x == selected_x and y == selected_y
      chunks[#chunks + 1] = selected and "+ " or "  "
      paint(l.rows.sv + y, l.x + x * 2, l.x + x * 2 + 2,
        C.hsv_to_rgb(session.h, x / (l.grid_width - 1), 1 - y / (l.grid_height - 1)), selected)
    end
    line(l.rows.sv + y, table.concat(chunks))
  end
  regions[#regions + 1] = { key = "sv", row = l.rows.sv, last_row = l.rows.sv + l.grid_height - 1,
    x = l.x, width = l.grid_width * 2 }

  local labels = { h = "Hue", r = "Red", g = "Green", b = "Blue", s = "Sat", v = "Value", a = "Alpha" }
  for index = 2, #controls do
    local key, channel = controls[index], nil
    local key_row = l.rows[key]
    if key == "h" then
      channel = session.h / 360
    elseif key == "s" or key == "v" then
      channel = session[key]
    else
      channel = current[key]
    end
    local marker = math.floor(channel * (l.bar_width - 1) + 0.5)
    local prefix = string.format("  %s %-5s ", session.selected == index and ">" or " ", labels[key])
    local chunks = { prefix }
    for x = 0, l.bar_width - 1 do
      local fraction = x / (l.bar_width - 1)
      local sample
      if key == "h" then
        sample = C.hsv_to_rgb(fraction * 360, 1, 1)
      elseif key == "s" or key == "v" then
        sample = C.hsv_to_rgb(session.h, key == "s" and fraction or session.s, key == "v" and fraction or session.v)
      else
        sample = vim.tbl_extend("force", {}, current, { [key] = fraction })
        if key == "a" then
          sample = blend(sample, math.floor(x / 2) % 2 == 0 and 0.35 or 0.65)
        end
      end
      chunks[#chunks + 1] = x == marker and "|" or " "
      paint(key_row, #prefix + x, #prefix + x + 1, sample, x == marker)
    end
    local number = key == "h" and string.format("%3d", math.floor(session.h + 0.5))
      or string.format("%3d", math.floor(channel * ((key == "r" or key == "g" or key == "b") and 255 or 100) + 0.5))
    line(key_row, table.concat(chunks) .. " " .. number .. ((key == "s" or key == "v" or key == "a") and "%" or ""))
    regions[#regions + 1] = { key = key, row = key_row, last_row = key_row, x = #prefix, width = l.bar_width }
  end
  line(l.rows.format, "  " .. session.format.kind:upper() .. "   f: format   e: enter color")
  line(l.rows.code, "  " .. value)
  line(l.rows.help, "  Tab/j/k select  h/l +/-  H/L +/-10")
  line(l.rows.help + 1, "  SV: arrows / J/K   r reset   y copy")
  line(l.rows.help + 2, "  Enter apply   Esc/q cancel   mouse: click")
  session.regions = regions
  vim.bo[session.buf].modifiable = true
  api.nvim_buf_set_lines(session.buf, 0, -1, false, lines)
  vim.bo[session.buf].modifiable = false
  api.nvim_buf_clear_namespace(session.buf, ns, 0, -1)
  for _, item in ipairs(highlights) do
    api.nvim_buf_add_highlight(session.buf, ns, item[1], item[2], item[3], item[4])
  end
  api.nvim_buf_add_highlight(session.buf, ns, "Title", l.rows.code, 2, -1)
  local row = session.selected == 1 and l.rows.sv + selected_y or l.rows[controls[session.selected]]
  api.nvim_win_set_cursor(session.win, { row + 1, 0 })
end

local function sync_rgb(session)
  session.color = C.hsv_to_rgb(session.h, session.s, session.v, session.color.a)
end

local function sync_hsv(session)
  local h, s, v = C.rgb_to_hsv(session.color)
  -- Keep the chosen hue when the color becomes gray or black.
  if s > 0 then
    session.h = h
  end
  session.s, session.v = s, v
end

function M.adjust(session, direction, coarse, vertical)
  if not alive(session) then
    return
  end
  local key = controls[session.selected]
  local step = direction * (coarse and 10 or 1)
  if key == "sv" then
    local component = vertical and "v" or "s"
    session[component] = C.clamp(session[component] + step / 100)
    sync_rgb(session)
  elseif key == "h" then
    session.h = (session.h + step) % 360
    sync_rgb(session)
  elseif key == "s" or key == "v" then
    session[key] = C.clamp(session[key] + step / 100)
    sync_rgb(session)
  else
    session.color[key] = C.clamp(session.color[key] + step / (key == "a" and 100 or 255))
    if key ~= "a" then
      sync_hsv(session)
    end
  end
  M.render(session)
end

function M.select(session, direction)
  session.selected = (session.selected - 1 + direction) % #controls + 1
  M.render(session)
end

function M.click(session, row, col)
  if not alive(session) then
    return
  end
  for _, region in ipairs(session.regions) do
    if row >= region.row and row <= region.last_row and col >= region.x and col < region.x + region.width then
      for index, key in ipairs(controls) do
        if key == region.key then
          session.selected = index
        end
      end
      local fraction = C.clamp((col - region.x) / (region.width - 1))
      if region.key == "sv" then
        session.s = math.floor((col - region.x) / 2) / (session.layout.grid_width - 1)
        session.v = 1 - (row - region.row) / (session.layout.grid_height - 1)
        sync_rgb(session)
      elseif region.key == "h" then
        session.h = fraction * 359.99
        sync_rgb(session)
      elseif region.key == "s" or region.key == "v" then
        session[region.key] = fraction
        sync_rgb(session)
      else
        session.color[region.key] = fraction
        if region.key ~= "a" then
          sync_hsv(session)
        end
      end
      M.render(session)
      return
    end
  end
end

function M.close(session)
  if session.closing then
    return
  end
  session.closing = true
  if M.active == session then
    M.active = nil
  end
  if session.augroup then
    api.nvim_del_augroup_by_id(session.augroup)
  end
  if api.nvim_buf_is_valid(session.source_buf) and session.mark then
    pcall(api.nvim_buf_del_extmark, session.source_buf, source_ns, session.mark)
  end
  if api.nvim_win_is_valid(session.win) then
    api.nvim_win_close(session.win, true)
  end
  if api.nvim_buf_is_valid(session.buf) then
    api.nvim_buf_delete(session.buf, { force = true })
  end
  if api.nvim_win_is_valid(session.source_win) and api.nvim_get_current_win() == session.source_win then
    pcall(api.nvim_win_set_cursor, session.source_win, session.cursor)
  end
end

function M.apply(session)
  if not alive(session) then
    return
  end
  if not api.nvim_buf_is_valid(session.source_buf) or not api.nvim_buf_is_loaded(session.source_buf)
      or not vim.bo[session.source_buf].modifiable or vim.bo[session.source_buf].readonly then
    notify("source buffer is unavailable or read-only")
    return
  end
  local mark = api.nvim_buf_get_extmark_by_id(session.source_buf, source_ns, session.mark, { details = true })
  if #mark == 0 then
    notify("source location is no longer available")
    return
  end
  local row, col, detail = mark[1], mark[2], mark[3]
  local end_row, end_col = detail.end_row or row, detail.end_col or col
  if session.target then
    -- Replacing the entire literal can invert an extmark's range because
    -- start and end have opposite gravity. Treat that as a source conflict.
    local readable, text = pcall(api.nvim_buf_get_text, session.source_buf, row, col, end_row, end_col, {})
    if not readable or table.concat(text, "\n") ~= session.target.text then
      notify("source color changed while the picker was open; reopen the picker")
      return
    end
  end
  local value = C.format(session.color, session.format)
  local ok, err = pcall(api.nvim_buf_set_text, session.source_buf, row, col, end_row, end_col, { value })
  if not ok then
    notify(tostring(err))
    return
  end
  session.cursor = { row + 1, col }
  M.close(session)
end

function M.edit(session)
  vim.ui.input({ prompt = "Color: ", default = C.format(session.color, session.format) }, function(input)
    if not input or not alive(session) then
      return
    end
    local color = C.parse(input)
    if not color then
      notify("invalid color: " .. input)
      return
    end
    session.color = color
    sync_hsv(session)
    M.render(session)
  end)
end

function M.cycle_format(session)
  local formats = { hex = "rgb", rgb = "hsl", hsl = "hex" }
  session.format = { kind = formats[session.format.kind], alpha = session.format.alpha }
  M.render(session)
end

local function mappings(session)
  local function map(key, callback)
    vim.keymap.set("n", key, callback, { buffer = session.buf, silent = true, nowait = true })
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    map(key, function() M.close(session) end)
  end
  map("<CR>", function() M.apply(session) end)
  for _, key in ipairs({ "j", "<Tab>" }) do
    map(key, function() M.select(session, 1) end)
  end
  for _, key in ipairs({ "k", "<S-Tab>" }) do
    map(key, function() M.select(session, -1) end)
  end
  for _, pair in ipairs({ { "h", -1 }, { "l", 1 }, { "H", -1, true }, { "L", 1, true },
    { "<Left>", -1 }, { "<Right>", 1 }, { "-", -1 }, { "+", 1 } }) do
    map(pair[1], function() M.adjust(session, pair[2], pair[3]) end)
  end
  for _, pair in ipairs({ { "<Up>", 1 }, { "<Down>", -1 }, { "K", 1 }, { "J", -1 } }) do
    map(pair[1], function()
      if session.selected == 1 then
        M.adjust(session, pair[2], false, true)
      else
        M.select(session, -pair[2])
      end
    end)
  end
  map("e", function() M.edit(session) end)
  map("f", function() M.cycle_format(session) end)
  map("r", function()
    session.color = vim.deepcopy(session.original)
    session.h, session.s, session.v = C.rgb_to_hsv(session.color)
    session.format = vim.deepcopy(session.original_format)
    M.render(session)
  end)
  map("y", function()
    vim.fn.setreg('"', C.format(session.color, session.format))
    vim.notify("ColorChooser: copied " .. C.format(session.color, session.format))
  end)
  for _, key in ipairs({ "<LeftMouse>", "<LeftDrag>" }) do
    map(key, function()
      local mouse = vim.fn.getmousepos()
      if mouse.winid == session.win then
        M.click(session, mouse.line - 1, mouse.column - 1)
      end
    end)
  end
  -- The scratch buffer is a control surface, never an editable text buffer.
  for _, key in ipairs({ "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "R", "v", "V", "<C-v>" }) do
    map(key, function() end)
  end
end

function M.open(context, config)
  local width, height = dimensions(config)
  if not width then
    notify("the picker needs 48 columns and at least " .. (23 + vim.o.cmdheight) .. " lines")
    return
  end
  local session = vim.tbl_extend("force", {}, context, { color = vim.deepcopy(context.color),
    original = vim.deepcopy(context.color), original_format = vim.deepcopy(context.format), format = vim.deepcopy(context.format),
    width = width, height = height, selected = 1, highlights = {}, cursor = { context.row + 1, context.col } })
  session.h, session.s, session.v = C.rgb_to_hsv(session.color)
  session.hl_ns = api.nvim_create_namespace("color-chooser-highlights")
  session.buf = api.nvim_create_buf(false, true)
  vim.bo[session.buf].bufhidden = "wipe"
  vim.bo[session.buf].swapfile = false
  vim.bo[session.buf].filetype = "color-chooser"
  session.win = api.nvim_open_win(session.buf, true, { relative = "editor", style = "minimal", border = config.border,
    width = width, height = height, row = math.floor((vim.o.lines - height - 2) / 2),
    col = math.floor((vim.o.columns - width - 2) / 2),
    title = " Color Chooser: " .. (context.target and "replace" or "insert") .. " ", title_pos = "center" })
  api.nvim_win_set_hl_ns(session.win, session.hl_ns)
  vim.wo[session.win].wrap = false
  vim.wo[session.win].cursorline = false
  vim.wo[session.win].cursorcolumn = false
  vim.wo[session.win].signcolumn = "no"
  vim.wo[session.win].foldenable = false
  vim.wo[session.win].list = false
  vim.wo[session.win].spell = false
  vim.wo[session.win].scrolloff = 0
  vim.wo[session.win].sidescrolloff = 0
  local start_col = context.target and context.target.start_col or context.col
  local end_col = context.target and context.target.end_col or context.col
  local mark_options = { right_gravity = true }
  if context.target then
    mark_options.end_row, mark_options.end_col, mark_options.end_right_gravity = context.row, end_col, false
  end
  session.mark = api.nvim_buf_set_extmark(context.source_buf, source_ns, context.row, start_col, mark_options)
  M.active = session
  layout(session)
  mappings(session)
  session.augroup = api.nvim_create_augroup("ColorChooserSession", { clear = true })
  api.nvim_create_autocmd("WinClosed", { group = session.augroup, pattern = tostring(session.win), callback = function()
    M.close(session)
  end })
  api.nvim_create_autocmd("BufWipeout", { group = session.augroup, buffer = session.buf, callback = function()
    M.close(session)
  end })
  api.nvim_create_autocmd("VimResized", { group = session.augroup, callback = function()
    local new_width, new_height = dimensions(config)
    if not new_width then
      M.close(session)
      return
    end
    session.width, session.height = new_width, new_height
    api.nvim_win_set_config(session.win, { relative = "editor", width = new_width, height = new_height,
      row = math.floor((vim.o.lines - new_height - 2) / 2), col = math.floor((vim.o.columns - new_width - 2) / 2) })
    layout(session)
    M.render(session)
  end })
  M.render(session)
  return session
end

return M
