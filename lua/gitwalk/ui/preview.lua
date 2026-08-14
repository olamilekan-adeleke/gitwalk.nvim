local M = {}

local ns = vim.api.nvim_create_namespace("gitwalk_preview")

---Remember the last "normal" window (not the gitwalk panel) to jump into.
M.target_win = nil

function M.remember_target_win()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype ~= "gitwalk" then
    M.target_win = win
  end
end

---@param cwd string
---@param node TreeNode  file or hunk node
function M.show(cwd, node)
  local file = node.file
  if not file then
    return
  end

  local win = M.target_win
  if not win or not vim.api.nvim_win_is_valid(win) then
    vim.cmd("wincmd p")
    win = vim.api.nvim_get_current_win()
    M.target_win = win
  end

  local abs = cwd .. "/" .. file.path
  local bufnr = vim.fn.bufadd(abs)
  vim.fn.bufload(bufnr)
  vim.api.nvim_win_set_buf(win, bufnr)

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local target_line = 1
  if node.type == "hunk" then
    target_line = math.max(node.hunk.new_start, 1)
    local last = math.max(node.hunk.new_start + node.hunk.new_count - 1, target_line)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    for l = target_line, math.min(last, line_count) do
      vim.api.nvim_buf_add_highlight(bufnr, ns, "GitwalkHunkActive", l - 1, 0, -1)
    end
  end

  local ok = pcall(vim.api.nvim_win_set_cursor, win, { math.min(target_line, vim.api.nvim_buf_line_count(bufnr)), 0 })
  if ok then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! zz")
    end)
  end
end

---Focus the target window (used by <CR> to actually move editing focus).
function M.focus()
  if M.target_win and vim.api.nvim_win_is_valid(M.target_win) then
    vim.api.nvim_set_current_win(M.target_win)
  end
end

return M
