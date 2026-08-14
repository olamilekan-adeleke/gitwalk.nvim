local M = {}

---Build a nested dir/file/hunk tree from a flat FileChange list.
---Directories are purely presentational: split each path on "/" and merge
---shared prefixes into single collapsed segments where a dir has one child.
---@param files FileChange[]
---@param expanded table<string, boolean>  path -> expanded?, keyed by node key
---@return TreeNode[] roots
function M.build(files, expanded)
  expanded = expanded or {}
  local root = { children = {}, by_name = {} }

  table.sort(files, function(a, b)
    return a.path < b.path
  end)

  for _, file in ipairs(files) do
    local parts = vim.split(file.path, "/", { plain = true })
    local node = root
    local acc = {}
    for i, part in ipairs(parts) do
      table.insert(acc, part)
      local key = table.concat(acc, "/")
      local is_last = i == #parts
      node.by_name = node.by_name or {}
      local child = node.by_name[part]
      if not child then
        child = {
          type = is_last and "file" or "dir",
          name = part,
          key = key,
          children = {},
          by_name = {},
          expanded = expanded[key] ~= false, -- default expanded
        }
        node.by_name[part] = child
        table.insert(node.children, child)
      end
      if is_last then
        child.file = file
        for _, hunk in ipairs(file.hunks) do
          table.insert(child.children, {
            type = "hunk",
            name = hunk.context or ("Changes around line " .. hunk.new_start),
            key = key .. "#" .. hunk.index,
            file = file,
            hunk = hunk,
            expanded = true,
            children = {},
          })
        end
      end
      node = child
    end
  end

  -- Collapse directory chains with exactly one dir child (a/b/c -> "a/b/c")
  local function collapse(node)
    for _, child in ipairs(node.children) do
      collapse(child)
    end
    while node.type == "dir" and #node.children == 1 and node.children[1].type == "dir" do
      local only = node.children[1]
      node.name = node.name .. "/" .. only.name
      node.key = only.key
      node.children = only.children
      node.by_name = only.by_name
    end
    table.sort(node.children, function(a, b)
      if a.type ~= b.type then
        return a.type == "dir"
      end
      return a.name < b.name
    end)
  end
  collapse(root)

  return root.children
end

return M
