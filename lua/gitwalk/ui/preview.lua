local M = {}

local ns = vim.api.nvim_create_namespace("gitwalk_preview")

---Window to jump real editing focus into on <CR>. Remembered once, before
---the panel/preview take over the "previous window" slot.
M.target_win = nil

---The floating peek window shown while moving between nodes.
M.float_win = nil

function M.remember_target_win()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype ~= "gitwalk" then
    M.target_win = win
  end
end

---bufload()/bufadd() don't reliably run filetype detection the way :edit
---does, which is why the preview had no syntax highlighting — force it.
---@param bufnr integer
local function load_file_buf(abs)
  local bufnr = vim.fn.bufadd(abs)
  vim.fn.bufload(bufnr)
  if vim.bo[bufnr].filetype == "" then
    local ft = vim.filetype.match({ buf = bufnr })
    if ft then
      vim.bo[bufnr].filetype = ft
    end
  end
  return bufnr
end

---@param bufnr integer
---@param node TreeNode
---@return integer target_line
local function highlight_hunk(bufnr, node)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if node.type ~= "hunk" then
    return 1
  end
  local target_line = math.max(node.hunk.new_start, 1)
  local last = math.max(node.hunk.new_start + node.hunk.new_count - 1, target_line)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for l = target_line, math.min(last, line_count) do
    vim.api.nvim_buf_add_highlight(bufnr, ns, "GitwalkHunkActive", l - 1, 0, -1)
  end
  return target_line
end

---@param win integer
---@param bufnr integer
---@param line integer
local function place_cursor(win, bufnr, line)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local ok = pcall(vim.api.nvim_win_set_cursor, win, { math.min(line, line_count), 0 })
  if ok then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! zz")
    end)
  end
end

---@param panel_winid integer?
---@param position "left"|"right"
local function float_geometry(panel_winid, position)
  local total_cols = vim.o.columns
  local total_lines = vim.o.lines - vim.o.cmdheight - 1
  local panel_width = panel_winid and vim.api.nvim_win_get_width(panel_winid) or 0
  local col = position == "right" and 0 or panel_width + 3
  local width = total_cols - panel_width - 4
  return {
    relative = "editor",
    row = 1,
    col = col,
    width = math.max(width, 20),
    height = math.max(total_lines - 3, 5),
    border = "rounded",
    style = "minimal",
    title = " preview ",
    title_pos = "center",
  }
end

---Show a read-only floating peek of the file/hunk under the cursor. Does
---not move editing focus.
---@param cwd string
---@param node TreeNode
---@param panel_winid integer?
---@param position "left"|"right"
function M.show(cwd, node, panel_winid, position)
  local file = node.file
  if not file then
    return
  end

  local bufnr = load_file_buf(cwd .. "/" .. file.path)
  local target_line = highlight_hunk(bufnr, node)

  if not (M.float_win and vim.api.nvim_win_is_valid(M.float_win)) then
    M.float_win = vim.api.nvim_open_win(bufnr, false, float_geometry(panel_winid, position))
    vim.wo[M.float_win].number = true
    vim.wo[M.float_win].wrap = false
    vim.wo[M.float_win].signcolumn = "yes"
    vim.wo[M.float_win].cursorline = true
  else
    vim.api.nvim_win_set_buf(M.float_win, bufnr)
  end

  place_cursor(M.float_win, bufnr, target_line)
end

function M.close()
  if M.float_win and vim.api.nvim_win_is_valid(M.float_win) then
    vim.api.nvim_win_close(M.float_win, true)
  end
  M.float_win = nil
end

---Actually move editing focus: close the peek float and open the file for
---real editing in the remembered target window, cursor on the hunk.
---@param cwd string
---@param node TreeNode
function M.focus(cwd, node)
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

  local bufnr = load_file_buf(cwd .. "/" .. file.path)
  vim.api.nvim_win_set_buf(win, bufnr)
  local target_line = highlight_hunk(bufnr, node)
  place_cursor(win, bufnr, target_line)

  M.close()
  vim.api.nvim_set_current_win(win)
end

return M
