if vim.g.loaded_color_chooser then
  return
end
vim.g.loaded_color_chooser = true

vim.api.nvim_create_user_command("ColorChooser", function(args)
  require("color-chooser").open(args.args ~= "" and args.args or nil)
end, { nargs = "?", desc = "Adjust a color in a floating window" })
