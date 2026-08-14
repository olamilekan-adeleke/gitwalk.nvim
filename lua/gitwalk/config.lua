local M = {}

---@class GitwalkConfig
M.defaults = {
  width = 40,
  position = "left", -- "left" | "right"
  icons = true,
  sign_column = true,
  diff_context = 0,
  keymaps = {
    next = "j",
    prev = "k",
    jump = "<CR>",
    expand = "l",
    collapse = "h",
    toggle = "<Tab>",
    refresh = "r",
    stage_hunk = "s",
    stage_file = "S",
    close = "q",
  },
}

---@type GitwalkConfig
M.options = vim.deepcopy(M.defaults)

---@param opts GitwalkConfig?
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
