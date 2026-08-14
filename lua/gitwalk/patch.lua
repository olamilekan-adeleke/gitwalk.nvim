-- Builds unified-diff patch text from parsed FileChange/Hunk data. Pure and
-- shared by git.lua (staging) and ui/preview.lua (diff rendering) so both
-- construct patches the same way.

local M = {}

---@param file FileChange
---@param hunk Hunk
---@return string
function M.hunk(file, hunk)
  return (file.diff_header or "") .. table.concat(hunk.lines, "\n") .. "\n"
end

---All hunks of a file, concatenated under its diff header.
---@param file FileChange
---@return string
function M.file(file)
  local parts = { file.diff_header or "" }
  for _, h in ipairs(file.hunks) do
    table.insert(parts, table.concat(h.lines, "\n"))
  end
  return table.concat(parts, "\n") .. "\n"
end

return M
