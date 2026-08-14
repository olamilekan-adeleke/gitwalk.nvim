local render = require("gitwalk.ui.render")
local tree_mod = require("gitwalk.tree")

local M = {}

---@class PanelState
---@field bufnr integer
---@field winid integer
---@field files FileChange[]
---@field roots TreeNode[]
---@field index TreeNode[]
---@field expanded table<string, boolean>
---@field cwd string
M.state = nil

local ns = vim.api.nvim_create_namespace("gitwalk_panel")

local function set_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, "GitwalkDir", { link = "Directory", default = true })
  hl(0, "GitwalkFile", { link = "Normal", default = true })
  hl(0, "GitwalkStat", { link = "Comment", default = true })
  hl(0, "GitwalkHunk", { link = "DiagnosticInfo", default = true })
  hl(0, "GitwalkHunkActive", { link = "DiffChange", default = true })
end

---@return integer bufnr
local function ensure_buf()
  if M.state and vim.api.nvim_buf_is_valid(M.state.bufnr) then
    return M.state.bufnr
  end
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "gitwalk"
  vim.api.nvim_buf_set_name(bufnr, "gitwalk://panel")
  return bufnr
end

---@param config GitwalkConfig
local function ensure_win(config, bufnr)
  if M.state and vim.api.nvim_win_is_valid(M.state.winid) then
    return M.state.winid
  end
  local split_cmd = config.position == "right" and "botright vsplit" or "topleft vsplit"
  vim.cmd(split_cmd)
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.api.nvim_win_set_width(winid, config.width)
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true
  return winid
end

local function current_node()
  if not M.state then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(M.state.winid)[1]
  local node = M.state.index[lnum]
  return node or nil
end
M.current_node = current_node

local function redraw()
  local lines, index, highlights = render.render(M.state.roots)
  M.state.index = index
  vim.bo[M.state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, lines)
  vim.bo[M.state.bufnr].modifiable = false
  vim.api.nvim_buf_clear_namespace(M.state.bufnr, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(M.state.bufnr, ns, h.group, h.line, h.col_start, h.col_end)
  end
end
M.redraw = redraw

---Find the next/prev "selectable" line (any rendered node is selectable;
---hunk-awareness comes from the tree only showing hunks once a file is
---expanded, so plain line-by-line movement already does the right thing).
---@param dir 1|-1
local function move(dir)
  if not M.state then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(M.state.winid)[1]
  local last = #M.state.index
  local next_line = lnum + dir
  if next_line < 1 or next_line > last then
    return
  end
  vim.api.nvim_win_set_cursor(M.state.winid, { next_line, 0 })
end

local function toggle_node(node)
  if not node or node.type == "hunk" then
    return
  end
  node.expanded = not node.expanded
  M.state.expanded[node.key] = node.expanded
  redraw()
end

---@param files FileChange[]
---@param cwd string
---@param config GitwalkConfig
---@param on_action fun(action: string, node: TreeNode?)
function M.open(files, cwd, config, on_action)
  set_highlights()
  local bufnr = ensure_buf()
  local expanded = (M.state and M.state.expanded) or {}
  M.state = {
    bufnr = bufnr,
    winid = ensure_win(config, bufnr),
    files = files,
    roots = tree_mod.build(files, expanded),
    index = {},
    expanded = expanded,
    cwd = cwd,
  }
  redraw()

  local function map(lhs, fn, desc)
    if lhs and lhs ~= "" then
      vim.keymap.set("n", lhs, fn, { buffer = bufnr, nowait = true, silent = true, desc = desc })
    end
  end

  local km = config.keymaps
  map(km.next, function()
    move(1)
    on_action("preview", current_node())
  end, "gitwalk: next")
  map(km.prev, function()
    move(-1)
    on_action("preview", current_node())
  end, "gitwalk: prev")
  map(km.jump, function()
    on_action("jump", current_node())
  end, "gitwalk: jump to hunk")
  map(km.expand, function()
    local node = current_node()
    if node and node.type ~= "hunk" and not node.expanded then
      toggle_node(node)
    elseif node then
      on_action("preview", node)
    end
  end, "gitwalk: expand")
  map(km.collapse, function()
    local node = current_node()
    if node and node.type ~= "hunk" and node.expanded then
      toggle_node(node)
    end
  end, "gitwalk: collapse")
  map(km.toggle, function()
    toggle_node(current_node())
  end, "gitwalk: toggle")
  map(km.refresh, function()
    on_action("refresh", nil)
  end, "gitwalk: refresh")
  map(km.stage_hunk, function()
    on_action("stage_hunk", current_node())
  end, "gitwalk: stage hunk")
  map(km.stage_file, function()
    on_action("stage_file", current_node())
  end, "gitwalk: stage file")
  map(km.close, function()
    on_action("close", nil)
  end, "gitwalk: close")

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = bufnr,
    callback = function()
      on_action("preview", current_node())
    end,
  })

  -- initial preview
  on_action("preview", current_node())
end

---@param files FileChange[]
function M.update(files)
  if not M.state then
    return
  end
  M.state.files = files
  M.state.roots = tree_mod.build(files, M.state.expanded)
  redraw()
end

function M.close()
  if M.state and vim.api.nvim_win_is_valid(M.state.winid) then
    vim.api.nvim_win_close(M.state.winid, true)
  end
  M.state = nil
end

function M.is_open()
  return M.state ~= nil and vim.api.nvim_win_is_valid(M.state.winid)
end

return M
