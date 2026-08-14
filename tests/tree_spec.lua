local tree = require("gitwalk.tree")

local function file_change(path, hunks)
  return { path = path, status = "M", additions = 0, deletions = 0, hunks = hunks or {} }
end

describe("gitwalk.tree", function()
  it("collapses single-child directory chains", function()
    local roots = tree.build({
      file_change("lib/auth/login.dart"),
    }, {})

    assert.equals(1, #roots)
    assert.equals("lib/auth", roots[1].name)
    assert.equals("dir", roots[1].type)
    assert.equals(1, #roots[1].children)
    assert.equals("login.dart", roots[1].children[1].name)
  end)

  it("keeps siblings separate when a directory has multiple children", function()
    local roots = tree.build({
      file_change("lib/auth/login.dart"),
      file_change("lib/home/home.dart"),
    }, {})

    assert.equals(1, #roots)
    assert.equals("lib", roots[1].name)
    assert.equals(2, #roots[1].children)
  end)

  it("attaches hunks as children of the file node", function()
    local roots = tree.build({
      file_change("a.txt", {
        { index = 1, new_start = 5, new_count = 1, additions = 1, deletions = 0, lines = {} },
        { index = 2, new_start = 9, new_count = 1, additions = 1, deletions = 0, lines = {} },
      }),
    }, {})

    local file_node = roots[1]
    assert.equals("file", file_node.type)
    assert.equals(2, #file_node.children)
    assert.equals("hunk", file_node.children[1].type)
  end)
end)
