local config_mod = require("gitwalk.config")
local git = require("gitwalk.git")
local panel = require("gitwalk.ui.panel")
local preview = require("gitwalk.ui.preview")

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
    if panel.is_open() then
      panel.update(files)
    else
      preview.remember_target_win()
      panel.open(files, cwd(), M.config, M.on_action)
    end
  end)
end

---@param action string
---@param node TreeNode?
function M.on_action(action, node)
  if action == "preview" then
    if node and node.file then
      preview.show(cwd(), node, panel.get_winid(), M.config.position)
    end
  elseif action == "jump" then
    if node and node.file then
      preview.focus(cwd(), node)
    elseif node and node.type == "dir" then
      node.expanded = not node.expanded
      panel.redraw()
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
    local file = node and (node.file or (node.type == "dir" and nil))
    if file then
      git.stage_file(file.path, cwd(), function(ok, err)
        if ok then
          refresh()
        else
          vim.notify("gitwalk: stage file failed: " .. (err or "?"), vim.log.levels.ERROR)
        end
      end)
    end
  elseif action == "close" then
    preview.close()
    panel.close()
  end
end

function M.open()
  refresh()
end

function M.toggle()
  if panel.is_open() then
    preview.close()
    panel.close()
  else
    M.open()
  end
end

function M.refresh()
  refresh()
end

return M
