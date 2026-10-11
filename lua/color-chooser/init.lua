local M = {}
local color = require("color-chooser.color")

M.config = {
  default_color = "#ff8800",
  border = "rounded",
  width = 64,
  height = 30,
}

function M.setup(options)
  local config = vim.tbl_deep_extend("force", {}, M.config, options or {})
  assert(type(config.default_color) == "string" and color.parse(config.default_color), "color-chooser: invalid default_color")
  assert(type(config.width) == "number" and config.width >= 44, "color-chooser: width must be at least 44")
  assert(type(config.height) == "number" and config.height >= 19, "color-chooser: height must be at least 19")
  M.config = config
end

---Open the picker. An optional literal sets the starting color.
---@param initial? string
function M.open(initial)
  local ui = require("color-chooser.ui")
  if ui.active then
    if vim.api.nvim_win_is_valid(ui.active.win) then
      vim.api.nvim_set_current_win(ui.active.win)
      return
    end
    ui.close(ui.active)
  end
  local source_buf, source_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(source_win)
  local line = vim.api.nvim_buf_get_lines(source_buf, cursor[1] - 1, cursor[1], false)[1] or ""
  local target = color.find_at(line, cursor[2])
  local selected, format
  if initial and initial ~= "" then
    selected, format = color.parse(initial)
    if not selected then
      vim.notify("ColorChooser: invalid color: " .. initial, vim.log.levels.WARN)
      return
    end
  elseif target then
    selected, format = target.color, target.format
  else
    selected, format = color.parse(M.config.default_color)
  end
  return ui.open({ color = selected, format = target and target.format or format, target = target,
    source_buf = source_buf, source_win = source_win, row = cursor[1] - 1, col = cursor[2] }, M.config)
end

return M
