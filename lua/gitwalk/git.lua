local parser = require("gitwalk.parser")

local M = {}

---@param cmd string[]
---@param cwd string?
---@param cb fun(ok: boolean, stdout: string, stderr: string)
local function run(cmd, cwd, cb)
  vim.system(cmd, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      cb(res.code == 0, res.stdout or "", res.stderr or "")
    end)
  end)
end

---Build a synthetic single-hunk FileChange for an untracked file.
---@param path string
---@param cwd string
---@return FileChange
local function untracked_file_change(path, cwd)
  local abs = cwd .. "/" .. path
  local lines = {}
  local f = io.open(abs, "r")
  if f then
    for l in f:lines() do
      table.insert(lines, "+" .. l)
    end
    f:close()
  end
  return {
    path = path,
    status = "?",
    additions = #lines,
    deletions = 0,
    hunks = {
      {
        index = 1,
        old_start = 0,
        old_count = 0,
        new_start = 1,
        new_count = #lines,
        context = nil,
        additions = #lines,
        deletions = 0,
        lines = lines,
      },
    },
  }
end

---Collect changed files (tracked + untracked) with parsed hunks.
---@param opts { cwd: string?, staged: boolean?, diff_context: integer? }
---@param cb fun(ok: boolean, files: FileChange[], err: string?)
function M.collect(opts, cb)
  opts = opts or {}
  local cwd = opts.cwd or vim.uv.cwd()
  local context = opts.diff_context or 0
  local diff_cmd = { "git", "diff", "--unified=" .. context }
  if opts.staged then
    table.insert(diff_cmd, "--cached")
  end

  run(diff_cmd, cwd, function(ok, out, err)
    if not ok then
      cb(false, {}, err)
      return
    end
    local files = parser.parse(out)

    if opts.staged then
      cb(true, files, nil)
      return
    end

    run({ "git", "ls-files", "--others", "--exclude-standard" }, cwd, function(ok2, out2)
      if ok2 then
        for path in out2:gmatch("[^\r\n]+") do
          table.insert(files, untracked_file_change(path, cwd))
        end
      end
      cb(true, files, nil)
    end)
  end)
end

---Stage a single hunk via `git apply --cached --unidiff-zero`.
---@param file FileChange
---@param hunk Hunk
---@param cwd string?
---@param cb fun(ok: boolean, err: string?)
function M.stage_hunk(file, hunk, cwd, cb)
  if not file.diff_header then
    cb(false, "missing diff header for " .. file.path)
    return
  end
  local patch = file.diff_header .. table.concat(hunk.lines, "\n") .. "\n"
  local job = vim.system(
    { "git", "apply", "--cached", "--unidiff-zero", "-" },
    { cwd = cwd or vim.uv.cwd(), stdin = patch, text = true },
    function(res)
      vim.schedule(function()
        cb(res.code == 0, res.code ~= 0 and res.stderr or nil)
      end)
    end
  )
  if not job then
    cb(false, "failed to spawn git apply")
  end
end

---@param path string
---@param cwd string?
---@param cb fun(ok: boolean, err: string?)
function M.stage_file(path, cwd, cb)
  run({ "git", "add", "--", path }, cwd or vim.uv.cwd(), function(ok, _, err)
    cb(ok, ok and nil or err)
  end)
end

return M
