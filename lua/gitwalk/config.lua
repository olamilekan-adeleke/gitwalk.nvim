local M = {}

---@class GitwalkConfig
M.defaults = {
  width = 0.9, -- fraction of columns for the whole modal
  height = 0.85, -- fraction of lines for the whole modal
  list_ratio = 0.4, -- fraction of the modal width given to the list pane
  diff_context = 0,
  keymaps = {
    next = "<C-n>",
    prev = "<C-p>",
    jump = "<CR>",
    toggle = "<Tab>", -- expand/collapse the node under the selection (browse mode)
    refresh = "<C-r>",
    stage_hunk = "<C-s>",
    stage_file = "<C-x>",
    close = "<Esc>",
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
