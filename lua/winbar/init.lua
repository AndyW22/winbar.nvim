local utils = require("winbar.utils")
local config = require("winbar.config")
local M = {}

local function augroup(name)
  return vim.api.nvim_create_augroup("winbar_" .. name, { clear = true })
end

local function get_folders()
  local levels = config.options.dir_levels
  if levels <= 0 then
    return ""
  end

  local path = vim.fn.expand("%:p:h")

  local parts = {}
  for part in string.gmatch(path, "[^/]+") do
    table.insert(parts, part)
  end

  local result = {}

  local start = math.max(#parts - config.options.dir_levels + 1, 0)
  for i = start, #parts do
    if i > 0 then
      table.insert(result, parts[i])
    end
  end
  local folders = table.concat(result, "/")

  return (folders ~= "" and folders .. "/" or "")
end

local function git_status_type()
  local gs = vim.b.gitsigns_status_dict
  if not gs then
    return nil
  end
  if gs.untracked then
    return "untracked"
  end
  if (gs.added and gs.added ~= 0) or (gs.changed and gs.changed ~= 0) or (gs.removed and gs.removed ~= 0) then
    return "modified"
  end
  return nil
end

---@return string
function M.get_winbar(opts)
  local diagnostics = {}
  local icon, hl = "", ""
  local should_dim = not opts.active and config.options.dim_inactive.enabled

  if config.options.diagnostics then
    diagnostics = utils.get_diagnostics(opts.diagnostics)
  end

  if config.options.icons then
    icon, hl = utils.get_icon(M.icons_by_filename, M.icons_by_extension)
  end

  -- don't highlight icon if the window is not active
  if should_dim and config.options.dim_inactive.icons then
    hl = config.options.dim_inactive.highlight
  end

  local sectionA = "  %#" .. hl .. "#" .. icon
  local sectionBhl = "WinBar"
  local sectionC = ""

  if vim.api.nvim_get_option_value("mod", {}) and config.options.buf_modified_symbol then
    if diagnostics.level == "other" then
      sectionBhl = "BufferCurrentMod"
      sectionC = "%#" .. sectionBhl .. "# " .. config.options.buf_modified_symbol
    else
      sectionC = " " .. config.options.buf_modified_symbol
    end
  end

  if diagnostics.level == "error" then
    sectionBhl = "DiagnosticError"
  elseif diagnostics.level == "warning" then
    sectionBhl = "DiagnosticWarn"
  elseif diagnostics.level == "info" then
    sectionBhl = "DiagnosticInfo"
  elseif diagnostics.level == "hint" then
    sectionBhl = "DiagnosticHint"
  end

  local git_section = ""
  local gstype = git_status_type()
  if gstype == "untracked" and config.options.git_untracked_symbol then
    git_section = " " .. config.options.git_untracked_symbol
  elseif gstype == "modified" and config.options.git_modified_symbol then
    git_section = " " .. config.options.git_modified_symbol
  end

  -- don't highlight name if the window is not active
  if should_dim and config.options.dim_inactive.name then
    sectionBhl = config.options.dim_inactive.highlight
  end

  local sectionB = "  " .. "%#" .. sectionBhl .. "#" .. get_folders() .. "%t" .. sectionC .. git_section
  return sectionA .. sectionB .. "%*"
end

function M.register()
  local events = { "VimEnter", "BufEnter", "BufModifiedSet", "WinEnter", "WinLeave" }
  if config.options.diagnostics then
    table.insert(events, "DiagnosticChanged")
  end

  vim.api.nvim_create_autocmd(events, {
    group = augroup("winbar"),
    callback = function(args)
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = 0 })
      for _, pattern in ipairs(config.options.filetype_exclude) do
        if vim.fn.match(filetype, pattern) ~= -1 then
          local ok, winbar_set_by_plugin = pcall(vim.api.nvim_buf_get_var, 0, "winbar_set_by_winbar_nvim")
          if ok and winbar_set_by_plugin then
            vim.opt_local.winbar = nil
            vim.api.nvim_buf_set_var(0, "winbar_set_by_winbar_nvim", false)
          end
          return
        end
      end

      local win_number = vim.api.nvim_get_current_win()
      local win_config = vim.api.nvim_win_get_config(win_number)

      if win_config.relative == "" then
        local bar = " " .. "%*" .. M.get_winbar({ active = args.event ~= "WinLeave", diagnostics = args.data }) .. "%*"
        vim.api.nvim_set_option_value("winbar", bar, { scope = "local", win = win_number })
        vim.api.nvim_buf_set_var(0, "winbar_set_by_winbar_nvim", true)
      else
        vim.opt_local.winbar = nil
        vim.api.nvim_buf_set_var(0, "winbar_set_by_winbar_nvim", false)
      end
    end,
  })
end

function M.setup(options)
  config.setup(options)

  if config.options.icons then
    local has_devicons, devicons = pcall(require, "nvim-web-devicons")
    if has_devicons and devicons then
      M.icons_by_filename = devicons.get_icons_by_filename()
      M.icons_by_extension = devicons.get_icons_by_extension()
    else
      error("Icons is set to true but dependency nvim-web-devicons is missing")
    end
  end

  M.register()
end

return M
