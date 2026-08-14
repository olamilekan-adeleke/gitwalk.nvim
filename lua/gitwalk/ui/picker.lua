-- A Telescope-style modal: a filter prompt + list pane on the left, a full
-- diff preview pane on the right, all centered floating windows. Typing
-- filters a flattened file/hunk list (fuzzy, via vim.fn.matchfuzzy); an
-- empty query shows the collapsible dir/file/hunk tree instead. <CR> jumps
-- to the selection and closes the whole thing, like a fuzzy finder.

local tree_mod = require("gitwalk.tree")
local render = require("gitwalk.ui.render")
local diffview = require("gitwalk.diffview")
local patch = require("gitwalk.patch")

local M = {}

local ns = vim.api.nvim_create_namespace("gitwalk_picker")

---@class PickerState
---@field prompt_buf integer
---@field prompt_win integer
---@field list_buf integer
---@field list_win integer
---@field preview_buf integer
---@field preview_win integer
---@field files FileChange[]
---@field expanded table<string, boolean>
---@field index TreeNode[]  -- index[lnum] = node currently shown on that list line
---@field query string
---@field selected integer
---@field cwd string
---@field config GitwalkConfig
---@field on_action fun(action: string, node: TreeNode?)
M.state = nil

local redraw_list, update_preview, move, confirm, toggle, on_prompt_change

local function set_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, "GitwalkDir", { link = "Directory", default = true })
  hl(0, "GitwalkFile", { link = "Normal", default = true })
  hl(0, "GitwalkStat", { link = "Comment", default = true })
  hl(0, "GitwalkHunk", { link = "DiagnosticInfo", default = true })
  hl(0, "GitwalkSelected", { link = "PmenuSel", default = true })
end

function M.is_open()
  return M.state ~= nil
end

---@param config GitwalkConfig
local function geometry(config)
  local total_cols = vim.o.columns
  local total_lines = vim.o.lines - vim.o.cmdheight - 1
  local width = math.floor(total_cols * config.width)
  local height = math.floor(total_lines * config.height)
  local row = math.floor((total_lines - height) / 2)
  local col = math.floor((total_cols - width) / 2)
  local list_width = math.floor(width * config.list_ratio)
  local preview_width = width - list_width - 3

  return {
    col = col,
    list_width = list_width,
    preview_width = preview_width,
    preview_col = col + list_width + 3,
    prompt_row = row,
    list_row = row + 3,
    list_height = height - 3,
    height = height,
  }
end

---Flatten a fully-expanded tree into searchable {node, text} entries.
---Directories are only used to build the breadcrumb prefix, not listed
---themselves — jumping only makes sense for files/hunks.
---@param files FileChange[]
---@return { node: TreeNode, text: string }[]
local function flatten(files)
  local roots = tree_mod.build(files, {})
  local out = {}
  local function walk(nodes, prefix)
    for _, node in ipairs(nodes) do
      if node.type == "hunk" then
        table.insert(out, { node = node, text = prefix .. " › " .. node.name })
      elseif node.type == "file" then
        table.insert(out, { node = node, text = prefix .. node.name })
        walk(node.children, prefix .. node.name .. "/")
      else -- dir
        walk(node.children, prefix .. node.name .. "/")
      end
    end
  end
  walk(roots, "")
  return out
end

---@param state PickerState
---@return { node: TreeNode, text: string }[]?  nil means "show the tree instead"
local function filtered_entries(state)
  if state.query == "" then
    return nil
  end
  local candidates = flatten(state.files)
  local texts = {}
  local buckets = {}
  for i, c in ipairs(candidates) do
    texts[i] = c.text
    buckets[c.text] = buckets[c.text] or {}
    table.insert(buckets[c.text], c)
  end
  local matched = vim.fn.matchfuzzy(texts, state.query)
  local out = {}
  for _, text in ipairs(matched) do
    local bucket = buckets[text]
    if bucket and #bucket > 0 then
      table.insert(out, table.remove(bucket, 1))
    end
  end
  return out
end

update_preview = function()
  local state = M.state
  if not state then
    return
  end
  local node = state.index[state.selected]
  if not node or not node.file then
    vim.bo[state.preview_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, {})
    vim.bo[state.preview_buf].modifiable = false
    return
  end

  local text = node.type == "hunk" and patch.hunk(node.file, node.hunk) or patch.file(node.file)
  local old_buf = state.preview_buf
  state.preview_buf = diffview.render(state.preview_win, text, state.cwd)
  if old_buf ~= state.preview_buf and vim.api.nvim_buf_is_valid(old_buf) then
    pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
  end
  pcall(vim.api.nvim_win_set_config, state.preview_win, { title = " " .. node.file.path .. " ", title_pos = "center" })
end

redraw_list = function()
  local state = M.state
  if not state then
    return
  end

  local entries = filtered_entries(state)
  local lines, index, highlights

  if entries == nil then
    local roots = tree_mod.build(state.files, state.expanded)
    lines, index, highlights = render.render(roots)
  else
    lines, index, highlights = {}, {}, {}
    for _, e in ipairs(entries) do
      table.insert(lines, e.text)
      table.insert(index, e.node)
    end
    if #lines == 0 then
      lines = { "  (no matches)" }
      index = { false }
    end
  end

  state.index = index
  state.selected = math.min(math.max(state.selected, 1), #index)

  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.bo[state.list_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.list_buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.list_buf, ns, h.group, h.line, h.col_start, h.col_end)
  end
  if state.index[state.selected] then
    vim.api.nvim_buf_add_highlight(state.list_buf, ns, "GitwalkSelected", state.selected - 1, 0, -1)
  end

  pcall(vim.api.nvim_win_set_cursor, state.list_win, { state.selected, 0 })
  update_preview()
end

move = function(delta)
  local state = M.state
  if not state or #state.index == 0 then
    return
  end
  local n = #state.index
  state.selected = ((state.selected - 1 + delta) % n) + 1
  redraw_list()
end

toggle = function()
  local state = M.state
  if not state then
    return
  end
  local node = state.index[state.selected]
  if node and node.type ~= "hunk" then
    node.expanded = not node.expanded
    state.expanded[node.key] = node.expanded
    redraw_list()
  end
end

confirm = function()
  local state = M.state
  if not state then
    return
  end
  local node = state.index[state.selected]
  if not node then
    return
  end
  if node.type == "hunk" or node.type == "file" then
    state.on_action("jump", node)
  elseif node.type == "dir" then
    toggle()
  end
end

on_prompt_change = function()
  local state = M.state
  if not state then
    return
  end
  local line = vim.api.nvim_buf_get_lines(state.prompt_buf, 0, 1, false)[1] or ""
  if line ~= state.query then
    state.query = line
    state.selected = 1
    redraw_list()
  end
end

function M.close()
  local state = M.state
  if not state then
    return
  end
  M.state = nil -- set first: guards against a re-entrant BufLeave close below
  for _, win in ipairs({ state.prompt_win, state.list_win, state.preview_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  for _, buf in ipairs({ state.prompt_buf, state.list_buf, state.preview_buf }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

---@param files FileChange[]
function M.update(files)
  if not M.state then
    return
  end
  M.state.files = files
  redraw_list()
end

---@param files FileChange[]
---@param cwd string
---@param config GitwalkConfig
---@param on_action fun(action: string, node: TreeNode?)
function M.open(files, cwd, config, on_action)
  if M.state then
    M.update(files)
    return
  end

  set_highlights()
  local geo = geometry(config)

  local prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buf].buftype = "nofile"
  vim.bo[prompt_buf].swapfile = false
  vim.bo[prompt_buf].filetype = "gitwalk_prompt"
  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor",
    row = geo.prompt_row,
    col = geo.col,
    width = geo.list_width,
    height = 1,
    border = "rounded",
    style = "minimal",
    title = " gitwalk ",
    title_pos = "center",
  })
  vim.api.nvim_buf_set_extmark(prompt_buf, ns, 0, 0, {
    virt_text = { { "> ", "Comment" } },
    virt_text_pos = "inline",
  })

  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[list_buf].buftype = "nofile"
  vim.bo[list_buf].swapfile = false
  vim.bo[list_buf].filetype = "gitwalk_list"
  local list_win = vim.api.nvim_open_win(list_buf, false, {
    relative = "editor",
    row = geo.list_row,
    col = geo.col,
    width = geo.list_width,
    height = geo.list_height,
    border = "rounded",
    style = "minimal",
  })
  vim.wo[list_win].number = false
  vim.wo[list_win].signcolumn = "no"
  vim.wo[list_win].wrap = false

  local preview_placeholder = vim.api.nvim_create_buf(false, true)
  local preview_win = vim.api.nvim_open_win(preview_placeholder, false, {
    relative = "editor",
    row = geo.prompt_row,
    col = geo.preview_col,
    width = geo.preview_width,
    height = geo.height,
    border = "rounded",
    style = "minimal",
    title = " preview ",
    title_pos = "center",
  })

  M.state = {
    prompt_buf = prompt_buf,
    prompt_win = prompt_win,
    list_buf = list_buf,
    list_win = list_win,
    preview_buf = preview_placeholder,
    preview_win = preview_win,
    files = files,
    expanded = {},
    index = {},
    query = "",
    selected = 1,
    cwd = cwd,
    config = config,
    on_action = on_action,
  }

  local function map(modes, lhs, fn)
    if lhs and lhs ~= "" then
      vim.keymap.set(modes, lhs, fn, { buffer = prompt_buf, nowait = true, silent = true })
    end
  end

  local km = config.keymaps
  map({ "i", "n" }, km.jump, confirm)
  map({ "i", "n" }, km.close, M.close)
  map({ "i", "n" }, km.next, function()
    move(1)
  end)
  map({ "i", "n" }, km.prev, function()
    move(-1)
  end)
  map({ "i", "n" }, km.toggle, toggle)
  map({ "i", "n" }, km.refresh, function()
    on_action("refresh", nil)
  end)
  map({ "i", "n" }, km.stage_hunk, function()
    on_action("stage_hunk", M.state and M.state.index[M.state.selected])
  end)
  map({ "i", "n" }, km.stage_file, function()
    on_action("stage_file", M.state and M.state.index[M.state.selected])
  end)

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = prompt_buf,
    callback = on_prompt_change,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = prompt_buf,
    once = true,
    callback = M.close,
  })

  redraw_list()
  vim.cmd("startinsert!")
end

return M
