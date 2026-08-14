local M = {}

local ICONS = {
  dir_open = "▼",
  dir_closed = "▶",
  file_open = "▼",
  file_closed = "▶",
}

local HUNK_GLYPHS = { "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨" }

local function hunk_glyph(i)
  return HUNK_GLYPHS[i] or ("[" .. i .. "]")
end

---Flatten a tree into render lines + a parallel array mapping line -> node.
---@param roots TreeNode[]
---@return string[] lines
---@return TreeNode[] index  -- index[lnum] = node (1-based)
---@return table[] highlights  -- { line, col_start, col_end, group }
function M.render(roots)
  local lines = {}
  local index = {}
  local highlights = {}

  local function add_hl(lnum, col_start, col_end, group)
    table.insert(highlights, { line = lnum, col_start = col_start, col_end = col_end, group = group })
  end

  local function walk(node, depth)
    local indent = string.rep("  ", depth)
    local lnum = #lines -- 0-based for extmarks

    if node.type == "dir" then
      local icon = node.expanded and ICONS.dir_open or ICONS.dir_closed
      local line = string.format("%s%s %s", indent, icon, node.name)
      table.insert(lines, line)
      table.insert(index, node)
      add_hl(lnum, #indent, #line, "GitwalkDir")
    elseif node.type == "file" then
      local icon = node.expanded and ICONS.file_open or ICONS.file_closed
      local stat = string.format("[+%d -%d]", node.file.additions, node.file.deletions)
      local count = string.format("[%d]", #node.file.hunks)
      local line = string.format("%s%s %s %s %s", indent, icon, node.name, stat, count)
      table.insert(lines, line)
      table.insert(index, node)
      add_hl(lnum, #indent, #indent + 1 + 1 + #node.name, "GitwalkFile")
      add_hl(lnum, #line - #stat - #count - 1, #line - #count, "GitwalkStat")
    elseif node.type == "hunk" then
      local glyph = hunk_glyph(node.hunk.index)
      local loc = string.format("L%d", node.hunk.new_start)
      local line = string.format("%s├─ %s %-24s %s", indent, glyph, node.name, loc)
      table.insert(lines, line)
      table.insert(index, node)
      add_hl(lnum, 0, #line, "GitwalkHunk")
    end

    if node.expanded and node.children then
      for _, child in ipairs(node.children) do
        walk(child, depth + 1)
      end
    end
  end

  for _, root in ipairs(roots) do
    walk(root, 0)
  end

  if #lines == 0 then
    table.insert(lines, "  (no changes)")
    table.insert(index, false)
  end

  return lines, index, highlights
end

return M
