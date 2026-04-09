-- tiny-packupdate.nvim: minimal vim.pack updater with progress bar & results picker
-- Requires Neovim 0.12+ (vim.pack API)

local M = {}
local state = nil -- nil = idle; table = running
local cfg = { command = "PackUpdate", auto = "manual" }
local ns = vim.api.nvim_create_namespace("tiny-packupdate")
local BAR_W = 40
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

-- ── Progress bar UI ───────────────────────────────────────────────────

local function progress_draw()
  if not state or not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  local elapsed = (vim.uv.hrtime() - state.t0) / 1e9
  local pct = state.complete and 1.0 or (0.9 * (1 - math.exp(-elapsed / 5)))
  local tag = state.changed > 0 and string.format(" %d new ", state.changed) or ""
  local bw = BAR_W - 2 - #tag
  local filled = math.floor(pct * bw)
  local line = " " .. string.rep("█", filled) .. string.rep("░", bw - filled) .. tag
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { line })
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  if filled > 0 then
    -- █ is 3 bytes in UTF-8
    vim.api.nvim_buf_add_highlight(state.buf, ns, "TinyPackProgress", 0, 1, 1 + filled * 3)
  end
end

local function progress_open()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  state.buf = buf
  state.win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = math.floor(vim.o.lines / 3),
    col = math.floor((vim.o.columns - BAR_W) / 2),
    width = BAR_W,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " " .. cfg.command .. " ",
    title_pos = "center",
    noautocmd = true,
  })
  state.t0 = vim.uv.hrtime()
  state.anim = vim.uv.new_timer()
  state.anim:start(0, 16, vim.schedule_wrap(progress_draw))
end

local function progress_close()
  if not state then
    return
  end
  if state.anim then
    state.anim:stop()
    state.anim:close()
    state.anim = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
end

-- ── Results display ───────────────────────────────────────────────────

local function show_results(results)
  progress_close()
  if #results == 0 then
    vim.notify("All plugins up to date", vim.log.levels.INFO)
    state = nil
    return
  end
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

-- ── Completion detection ──────────────────────────────────────────────

local function on_complete()
  write_stamp()
  state.complete = true
  progress_draw()
  vim.defer_fn(collect_and_show, 400)
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

  state = { snapshot = snapshot, total = #names, changed = 0 }
  progress_open()

  local timer = vim.uv.new_timer()
  local au_id
  local function reset_debounce()
    timer:stop()
    timer:start(
      2000,
      0,
      vim.schedule_wrap(function()
        pcall(vim.api.nvim_del_autocmd, au_id)
        timer:close()
        on_complete()
      end)
    )
  end

  au_id = vim.api.nvim_create_autocmd("PackChanged", {
    callback = function()
      if not state then
        return pcall(vim.api.nvim_del_autocmd, au_id)
      end
      state.changed = state.changed + 1
      progress_draw()
      reset_debounce()
    end,
  })

  reset_debounce()
  vim.pack.update(names, { force = true })
end

-- ── Setup ─────────────────────────────────────────────────────────────

function M.setup(opts)
  vim.g.tiny_packupdate_loaded = true
  cfg = vim.tbl_extend("force", cfg, opts or {})
  vim.api.nvim_set_hl(0, "TinyPackProgress", { default = true, link = "DiagnosticOk" })
  vim.api.nvim_create_user_command(cfg.command, M.update, { desc = "Update all plugins" })
  local interval = auto_intervals[cfg.auto]
  if interval and os.time() - read_stamp() >= interval then
    vim.schedule(M.update)
  end
end

return M
