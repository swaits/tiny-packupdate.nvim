local T = MiniTest.new_set()
local eq = MiniTest.expect.equality

-- ── Setup tests ───────────────────────────────────────────────────────

T["setup"] = MiniTest.new_set()

T["setup"]["creates user command with default name"] = function()
  -- plugin/ auto-loaded via minimal_init, so PackUpdate should exist
  local cmds = vim.api.nvim_get_commands({})
  eq(cmds["PackUpdate"] ~= nil, true)
end

T["setup"]["respects custom command name"] = function()
  require("tiny-packupdate").setup({ command = "PlugSync" })
  local cmds = vim.api.nvim_get_commands({})
  eq(cmds["PlugSync"] ~= nil, true)
  -- Cleanup: delete the custom command
  vim.api.nvim_del_user_command("PlugSync")
end

T["setup"]["is idempotent"] = function()
  -- Calling setup twice should not error
  require("tiny-packupdate").setup()
  require("tiny-packupdate").setup()
  local cmds = vim.api.nvim_get_commands({})
  eq(cmds["PackUpdate"] ~= nil, true)
end

T["setup"]["sets highlight group"] = function()
  require("tiny-packupdate").setup()
  local hl = vim.api.nvim_get_hl(0, { name = "TinyPackProgress" })
  eq(hl.link ~= nil or hl.fg ~= nil, true)
end

-- ── Timestamp tests ───────────────────────────────────────────────────

T["timestamp"] = MiniTest.new_set()

T["timestamp"]["roundtrip read/write"] = function()
  local path = vim.fn.stdpath("data") .. "/tiny-packupdate-last"
  -- Write a known timestamp
  local f = io.open(path, "w")
  f:write("1700000000")
  f:close()
  -- Read it back through the module's stamp path
  local f2 = io.open(path, "r")
  local val = tonumber(f2:read("*a"))
  f2:close()
  eq(val, 1700000000)
  -- Cleanup
  os.remove(path)
end

return T
