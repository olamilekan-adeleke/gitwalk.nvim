-- Run with: plenary.nvim's PlenaryBustedDirectory, e.g.
--   nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

local parser = require("gitwalk.parser")

local function read_fixture(name)
  local path = debug.getinfo(1, "S").source:sub(2):match("(.*/)") .. "fixtures/" .. name
  local f = assert(io.open(path, "r"))
  local content = f:read("*a")
  f:close()
  return content
end

describe("gitwalk.parser", function()
  it("parses multiple files with multiple hunks each", function()
    local files = parser.parse(read_fixture("two_files.diff"))

    assert.equals(2, #files)

    local login = files[1]
    assert.equals("lib/auth/login.dart", login.path)
    assert.equals(2, #login.hunks)
    assert.equals(6, login.additions) -- 4 + 2
    assert.equals(1, login.deletions)

    local h1 = login.hunks[1]
    assert.equals(1, h1.index)
    assert.equals(16, h1.new_start)
    assert.equals(4, h1.new_count)
    assert.equals("class Login {", h1.context)
    assert.equals(4, h1.additions)
    assert.equals(0, h1.deletions)

    local h2 = login.hunks[2]
    assert.equals(2, h2.index)
    assert.equals(51, h2.new_start)
    assert.equals("Future<void> login()", h2.context)
    assert.equals(2, h2.additions)
    assert.equals(1, h2.deletions)

    local register = files[2]
    assert.equals("lib/auth/register.dart", register.path)
    assert.equals(1, #register.hunks)
    assert.equals(23, register.hunks[1].new_start)
  end)

  it("returns an empty list for an empty diff", function()
    assert.same({}, parser.parse(""))
  end)

  it("captures a reusable diff_header for later hunk staging", function()
    local files = parser.parse(read_fixture("two_files.diff"))
    assert.truthy(files[1].diff_header:match("^diff %-%-git a/lib/auth/login%.dart"))
  end)
end)
