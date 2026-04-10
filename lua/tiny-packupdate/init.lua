-- tiny-packupdate.nvim: minimal vim.pack updater with results picker
-- Requires Neovim 0.12+ (vim.pack API)

local M = {}
local state = nil -- nil = idle; table = running
local cfg = { command = "PackUpdate", auto = "manual" }
local LOG_FMT = "--pretty=format:commit %h%nAuthor: %an%nDate:   %cr%n%n    %s%n"

-- ── Timestamp persistence (for auto-update cadence) ───────────────────

local stamp_path = vim.fn.stdpath("data") .. "/tiny-packupdate-last"
local auto_intervals = { daily = 86400, weekly = 604800, monthly = 2592000 }

local function read_stamp()
  local f = io.open(stamp_path, "r")
  if not f then
    return 0
  end
  local t = tonumber(f:read("*a")) or 0
  f:close()
  return t
end

local function write_stamp()
  local f = io.open(stamp_path, "w")
  if f then
    f:write(tostring(os.time()))
    f:close()
  end
end

-- ── Results display ───────────────────────────────────────────────────

local function show_results(results)
  if #results == 0 then
    vim.notify("All plugins already up to date", vim.log.levels.INFO)
    state = nil
    return
  end
  local n = #results
  vim.notify(string.format("Updated %d plugin%s", n, n == 1 and "" or "s"), vim.log.levels.INFO)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    local items = {}
    for i, r in ipairs(results) do
      items[i] = {
        idx = i,
        score = i,
        text = r.name,
        preview = { text = r.log ~= "" and r.log or "(no commits)", ft = "git" },
      }
    end
    snacks.picker({
      title = cfg.command .. " Results",
      items = items,
      preview = "preview",
      layout = { preset = "ivy" },
      format = function(item)
        return { { item.text } }
      end,
      confirm = function() end, -- viewer only, no action on select
    })
  else
    -- Fallback: floating markdown window
    local lines = { "# " .. cfg.command .. " Results", "" }
    for _, r in ipairs(results) do
      lines[#lines + 1] = "## " .. r.name
      lines[#lines + 1] = ""
      lines[#lines + 1] = "```gitlog"
      for l in (r.log or ""):gmatch("[^\n]+") do
        lines[#lines + 1] = l
      end
      lines[#lines + 1] = "```"
      lines[#lines + 1] = ""
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "markdown"
    vim.bo[buf].modifiable = false
    local w = math.floor(vim.o.columns * 0.8)
    local h = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = math.floor((vim.o.lines - h) / 2),
      col = math.floor((vim.o.columns - w) / 2),
      width = w,
      height = h,
      border = "rounded",
      title = " " .. cfg.command .. " Results ",
      title_pos = "center",
      footer = " (q) close ",
      footer_pos = "center",
    })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
    vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf })
  end
  state = nil
end

-- ── Collect changed plugins and their commit logs ─────────────────────

local function collect_and_show()
  local current = {}
  for _, p in ipairs(vim.pack.get(nil, { info = false })) do
    if p.active then
      current[p.spec.name] = { rev = p.rev, path = p.path }
    end
  end
  local changed = {}
  for name, snap in pairs(state.snapshot) do
    local cur = current[name]
    if cur and snap.rev and cur.rev ~= snap.rev then
      changed[#changed + 1] = { name = name, path = cur.path, old = snap.rev, new = cur.rev }
    elseif cur and not snap.rev and cur.rev then
      changed[#changed + 1] = { name = name, path = cur.path }
    end
  end
  if #changed == 0 then
    return show_results({})
  end
  local pending, results = #changed, {}
  for _, c in ipairs(changed) do
    local function on_log(label, r)
      local log = vim.trim(r.stdout or "")
      if label then
        log = label .. "\n" .. log
      end
      results[#results + 1] = { name = c.name, log = log }
      pending = pending - 1
      if pending == 0 then
        table.sort(results, function(a, b)
          return a.name < b.name
        end)
        vim.schedule(function()
          show_results(results)
        end)
      end
    end
    if not c.old then
      vim.system({ "git", "-C", c.path, "log", LOG_FMT, "-20" }, {}, function(r)
        on_log("(new)", r)
      end)
    else
      -- Forward update; if empty, it's a rollback
      vim.system({ "git", "-C", c.path, "log", LOG_FMT, c.old .. ".." .. c.new }, {}, function(r)
        if vim.trim(r.stdout or "") ~= "" then
          on_log(nil, r)
        else
          vim.system(
            { "git", "-C", c.path, "log", LOG_FMT, c.new .. ".." .. c.old },
            {},
            function(r2)
              on_log("(rolled back past)", r2)
            end
          )
        end
      end)
    end
  end
end

-- ── Main update ───────────────────────────────────────────────────────

function M.update()
  if state then
    return vim.notify("Update already in progress", vim.log.levels.WARN)
  end
  local plugins = vim.pack.get(nil, { info = false })
  local snapshot, names = {}, {}
  for _, p in ipairs(plugins) do
    if p.active then
      snapshot[p.spec.name] = { rev = p.rev, path = p.path }
      names[#names + 1] = p.spec.name
    end
  end
  if #names == 0 then
    return vim.notify("No active plugins", vim.log.levels.INFO)
  end

  state = { snapshot = snapshot, changed = 0 }

  local timer = vim.uv.new_timer()
  local au_id
  local function on_done()
    pcall(vim.api.nvim_del_autocmd, au_id)
    timer:close()
    write_stamp()
    collect_and_show()
  end

  au_id = vim.api.nvim_create_autocmd("PackChanged", {
    callback = function(ev)
      if not state then
        return pcall(vim.api.nvim_del_autocmd, au_id)
      end
      state.changed = state.changed + 1
      local name = ev.data and ev.data.spec and ev.data.spec.name or "plugin"
      vim.notify(string.format("Updated %s (%d)", name, state.changed), vim.log.levels.INFO)
      timer:stop()
      timer:start(2000, 0, vim.schedule_wrap(on_done))
    end,
  })

  timer:start(2000, 0, vim.schedule_wrap(on_done))
  vim.pack.update(names, { force = true })
end

-- ── Setup ─────────────────────────────────────────────────────────────

function M.setup(opts)
  vim.g.tiny_packupdate_loaded = true
  cfg = vim.tbl_extend("force", cfg, opts or {})
  vim.api.nvim_create_user_command(cfg.command, M.update, { desc = "Update all plugins" })
  local interval = auto_intervals[cfg.auto]
  if interval and os.time() - read_stamp() >= interval then
    vim.schedule(M.update)
  end
end

return M
