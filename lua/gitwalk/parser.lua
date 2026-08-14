-- Parses `git diff --unified=0` text into FileChange[]/Hunk[].
-- Pure function of a diff string; no git calls here, so it's unit-testable
-- against captured fixtures without a live repo.

local M = {}

local HUNK_HEADER = "^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@ ?(.-)%s*$"
local FILE_HEADER = "^diff %-%-git a/(.-) b/(.-)$"

---@param text string  raw output of `git diff --unified=<n>`
---@return FileChange[]
function M.parse(text)
  local files = {}
  local current = nil ---@type FileChange?
  local current_hunk = nil ---@type Hunk?
  local header_lines = nil ---@type string[]?

  local function close_hunk()
    if current and current_hunk then
      table.insert(current.hunks, current_hunk)
      current.additions = current.additions + current_hunk.additions
      current.deletions = current.deletions + current_hunk.deletions
    end
    current_hunk = nil
  end

  local function close_file()
    close_hunk()
    if current then
      for i, h in ipairs(current.hunks) do
        h.index = i
      end
      table.insert(files, current)
    end
    current = nil
  end

  for line in (text .. "\n"):gmatch("(.-)\n") do
    local a, b = line:match(FILE_HEADER)
    if a then
      close_file()
      current = {
        path = b ~= "" and b or a,
        status = "M",
        additions = 0,
        deletions = 0,
        hunks = {},
      }
      header_lines = { line }
    elseif current then
      -- Only pre-hunk lines (index/---/+++) belong in the file's diff
      -- header; the "@@" line itself is captured separately in each hunk's
      -- own `lines`, so it must not also land in header_lines or the patch
      -- text built from diff_header .. hunk.lines would duplicate it.
      if not current_hunk and not line:match("^@@ ") then
        table.insert(header_lines, line)
      end
      if line == "--- /dev/null" then
        current.status = "A"
      elseif line == "+++ /dev/null" then
        current.status = "D"
      elseif line:match("^%-%-%- ") or line:match("^%+%+%+ ") then
        -- part of the file header, already captured
      elseif line:match("^@@ ") then
        close_hunk()
        local os_, oc, ns, nc, ctx = line:match(HUNK_HEADER)
        if os_ then
          current.diff_header = current.diff_header or table.concat(header_lines, "\n") .. "\n"
          current_hunk = {
            old_start = tonumber(os_),
            old_count = oc ~= "" and tonumber(oc) or 1,
            new_start = tonumber(ns),
            new_count = nc ~= "" and tonumber(nc) or 1,
            context = ctx ~= "" and ctx or nil,
            additions = 0,
            deletions = 0,
            lines = { line },
          }
        end
      elseif current_hunk then
        table.insert(current_hunk.lines, line)
        local prefix = line:sub(1, 1)
        if prefix == "+" then
          current_hunk.additions = current_hunk.additions + 1
        elseif prefix == "-" then
          current_hunk.deletions = current_hunk.deletions + 1
        end
      end
    end
  end
  close_file()

  return files
end

return M
