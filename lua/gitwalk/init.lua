local config_mod = require("gitwalk.config")
local git = require("gitwalk.git")
local picker = require("gitwalk.ui.picker")

local M = {}

M.config = config_mod.options

---@param opts GitwalkConfig?
function M.setup(opts)
  M.config = config_mod.setup(opts)
end

local function cwd()
  return vim.uv.cwd()
end

local function refresh()
  git.collect({ cwd = cwd(), diff_context = M.config.diff_context }, function(ok, files, err)
    if not ok then
      vim.notify("gitwalk: " .. (err or "failed to read git diff"), vim.log.levels.ERROR)
      return
    end
    if picker.is_open() then
      picker.update(files)
    else
      picker.open(files, cwd(), M.config, M.on_action)
    end
  end)
end

---bufload()/bufadd() don't reliably run filetype detection the way :edit
---does, so force it once the buffer is loaded.
---@param abs string
---@return integer bufnr
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

---Jump: close the picker (which restores focus to whatever window was
---current before it opened, since it's built entirely from floating
---windows) and load the file at the hunk's line in that window.
---@param node TreeNode
local function jump(node)
  local file = node.file
  if not file then
    return
  end
  local bufnr = load_file_buf(cwd() .. "/" .. file.path)
  picker.close()
  vim.cmd("buffer " .. bufnr)
  local line = node.type == "hunk" and math.max(node.hunk.new_start, 1) or 1
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  pcall(vim.api.nvim_win_set_cursor, 0, { math.min(line, line_count), 0 })
  vim.cmd("normal! zz")
end

---@param action string
---@param node TreeNode?
function M.on_action(action, node)
  if action == "jump" then
    if node and node.file then
      jump(node)
    end
  elseif action == "refresh" then
    refresh()
  elseif action == "stage_hunk" then
    if node and node.type == "hunk" then
      git.stage_hunk(node.file, node.hunk, cwd(), function(ok, err)
        if ok then
          refresh()
        else
          vim.notify("gitwalk: stage hunk failed: " .. (err or "?"), vim.log.levels.ERROR)
        end
      end)
    end
  elseif action == "stage_file" then
    local file = node and node.file
    if file then
      git.stage_file(file.path, cwd(), function(ok, err)
        if ok then
          refresh()
        else
          vim.notify("gitwalk: stage file failed: " .. (err or "?"), vim.log.levels.ERROR)
        end
      end)
    end
  end
end

function M.open()
  refresh()
end

function M.toggle()
  if picker.is_open() then
    picker.close()
  else
    M.open()
  end
end

function M.refresh()
  refresh()
end

return M
