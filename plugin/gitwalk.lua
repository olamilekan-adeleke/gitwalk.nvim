if vim.g.loaded_gitwalk then
  return
end
vim.g.loaded_gitwalk = true

vim.api.nvim_create_user_command("Gitwalk", function()
  require("gitwalk").open()
end, { desc = "Open the gitwalk hunk-tree panel" })

vim.api.nvim_create_user_command("GitwalkToggle", function()
  require("gitwalk").toggle()
end, { desc = "Toggle the gitwalk hunk-tree panel" })

vim.api.nvim_create_user_command("GitwalkRefresh", function()
  require("gitwalk").refresh()
end, { desc = "Refresh the gitwalk hunk-tree panel" })
