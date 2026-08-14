local diffview = require("gitwalk.diffview")
local patch = require("gitwalk.patch")

local M = {}

local ns = vim.api.nvim_create_namespace("gitwalk_preview")

---Window to jump real editing focus into on <CR>. Remembered once, before
---the panel/preview take over the "previous window" slot.
M.target_win = nil

---The floating peek window/buffer shown while moving between nodes.
M.float_win = nil
M.float_buf = nil

local function is_floating(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
end

function M.remember_target_win()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype ~= "gitwalk" and not is_floating(win) then
    M.target_win = win
  end
end

---Resolve a real (non-floating, non-panel) window to jump edits into,
---falling back to any such window in the tabpage, then to a fresh split.
---Never returns the preview float itself — remembering it as the target
---would leave focus() unable to actually move editing focus anywhere.
---@return integer win
local function find_target_win()
  if M.target_win and vim.api.nvim_win_is_valid(M.target_win) and not is_floating(M.target_win) then
    return M.target_win
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not is_floating(win) and win ~= M.float_win then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype ~= "gitwalk" then
        return win
      end
    end
  end
  vim.cmd("botright vsplit")
  return vim.api.nvim_get_current_win()
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
  local total_lines = vim.o.lines - vim.o.cmdheight - 2
  local panel_width = panel_winid and vim.api.nvim_win_get_width(panel_winid) or 0
  local available_col = position == "right" and 0 or panel_width + 3
  local available_width = total_cols - panel_width - 4

  -- A hunk is usually a handful of lines, not a full screen — cap the peek
  -- to a comfortable reading size instead of filling all remaining space.
  local width = math.min(available_width, 90)
  local height = math.min(math.floor(total_lines * 0.5), 20)
  height = math.max(height, 8)

  local col = available_col + math.floor((available_width - width) / 2)
  local row = math.floor((total_lines - height) / 2)

  return {
    relative = "editor",
    row = math.max(row, 1),
    col = math.max(col, 0),
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
    title = " preview ",
    title_pos = "center",
  }
end

---Show a read-only floating peek of just the hunk's diff (not the whole
---file), rendered through `delta` when available for syntax-highlighted,
---colorized output — plain `filetype=diff` otherwise. Does not move editing
---focus; see focus() for that.
---@param cwd string
---@param node TreeNode
---@param panel_winid integer?
---@param position "left"|"right"
function M.show(cwd, node, panel_winid, position)
  local file = node.file
  if not file then
    return
  end

  if not (M.float_win and vim.api.nvim_win_is_valid(M.float_win)) then
    local placeholder = vim.api.nvim_create_buf(false, true)
    M.float_win = vim.api.nvim_open_win(placeholder, false, float_geometry(panel_winid, position))
  end

  local text = node.type == "hunk" and patch.hunk(file, node.hunk) or patch.file(file)
  local old_buf = M.float_buf
  M.float_buf = diffview.render(M.float_win, text, cwd)
  if old_buf and old_buf ~= M.float_buf and vim.api.nvim_buf_is_valid(old_buf) then
    pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
  end
end

---pcall'd: nvim_win_close can throw in edge cases (e.g. terminal-job
---quirks), and an uncaught error here previously aborted focus() before it
---reached nvim_set_current_win() — leaving the float visibly stuck open
---*and* focus never actually moved to the real editing window.
function M.close()
  if M.float_win and vim.api.nvim_win_is_valid(M.float_win) then
    pcall(vim.api.nvim_win_close, M.float_win, true)
  end
  if M.float_buf and vim.api.nvim_buf_is_valid(M.float_buf) then
    pcall(vim.api.nvim_buf_delete, M.float_buf, { force = true })
  end
  M.float_win = nil
  M.float_buf = nil
end

---Actually move editing focus: open the file for real editing in a real
---window, cursor on the hunk, THEN close the peek float — in that order,
---so a failure while closing the float can never prevent focus from
---landing in the real window.
---@param cwd string
---@param node TreeNode
function M.focus(cwd, node)
  local file = node.file
  if not file then
    return
  end

  local win = find_target_win()
  M.target_win = win

  local bufnr = load_file_buf(cwd .. "/" .. file.path)
  vim.api.nvim_win_set_buf(win, bufnr)
  local target_line = highlight_hunk(bufnr, node)
  place_cursor(win, bufnr, target_line)

  vim.api.nvim_set_current_win(win)
  M.close()
end

return M
