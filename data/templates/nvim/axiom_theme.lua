-- Follows the axiom (quickshell) theme. axiom's nvim theme integration writes
-- the active theme to $XDG_STATE_HOME/axiom/nvim-theme.json and calls
-- reload() in every running Neovim over RPC.
--
-- Copied here by axiom's settings (Theme integrations → Neovim); yours to
-- edit. Call it once your plugins are loaded, e.g. in init.lua after your
-- plugin manager's setup:
--
--   require("axiom_theme").setup({
--     -- axiom theme file stem -> a colorscheme you have installed
--     -- (merged over the defaults in M.map below)
--     map = { ["tokyo-night"] = { colorscheme = "tokyonight-night", plugin = "tokyonight.nvim" } },
--   })
--
-- A theme without a map entry, or whose colorscheme isn't installed, is
-- built from its base16 palette: by mini.base16 when it's installed,
-- otherwise by the plain highlights below.
local M = {}

M.path = (vim.env.XDG_STATE_HOME or (vim.env.HOME .. "/.local/state")) .. "/axiom/nvim-theme.json"

-- axiom theme file stem -> { colorscheme = name, plugin = lazy.nvim plugin name (optional) }.
-- Each shipped theme's usual plugin; one you don't have installed falls back
-- to the palette, so these only take effect once you install the plugin.
-- Light/dark-by-'background' schemes rely on reload() setting it first.
local function scheme(plugin, colorscheme)
  return { plugin = plugin, colorscheme = colorscheme }
end
M.map = {
  -- catppuccin/nvim (name = "catppuccin")
  ["catppuccin-latte"] = scheme("catppuccin", "catppuccin-latte"),
  ["catppuccin-frappe"] = scheme("catppuccin", "catppuccin-frappe"),
  ["catppuccin-macchiato"] = scheme("catppuccin", "catppuccin-macchiato"),
  ["catppuccin-mocha"] = scheme("catppuccin", "catppuccin-mocha"),
  -- folke/tokyonight.nvim
  ["tokyo-night"] = scheme("tokyonight.nvim", "tokyonight-night"),
  ["tokyo-storm"] = scheme("tokyonight.nvim", "tokyonight-storm"),
  ["tokyo-moon"] = scheme("tokyonight.nvim", "tokyonight-moon"),
  ["tokyo-day"] = scheme("tokyonight.nvim", "tokyonight-day"),
  -- ellisonleao/gruvbox.nvim
  ["gruvbox-dark"] = scheme("gruvbox.nvim", "gruvbox"),
  ["gruvbox-light"] = scheme("gruvbox.nvim", "gruvbox"),
  -- sainnhe/gruvbox-material
  ["gruvbox-material-dark"] = scheme("gruvbox-material", "gruvbox-material"),
  ["gruvbox-material-light"] = scheme("gruvbox-material", "gruvbox-material"),
  -- maxmx03/solarized.nvim
  ["solarized-dark"] = scheme("solarized.nvim", "solarized"),
  ["solarized-light"] = scheme("solarized.nvim", "solarized"),
  -- rose-pine/neovim (name = "rose-pine")
  ["rose-pine"] = scheme("rose-pine", "rose-pine-main"),
  ["rose-pine-moon"] = scheme("rose-pine", "rose-pine-moon"),
  ["rose-pine-dawn"] = scheme("rose-pine", "rose-pine-dawn"),
  -- gbprod/nord.nvim (no light variant: nord-light uses the palette)
  ["nord"] = scheme("nord.nvim", "nord"),
  -- Mofiqul/dracula.nvim (no light variant: alucard uses the palette)
  ["dracula"] = scheme("dracula.nvim", "dracula"),
  -- sainnhe/everforest
  ["everforest-dark"] = scheme("everforest", "everforest"),
  ["everforest-light"] = scheme("everforest", "everforest"),
  -- rebelot/kanagawa.nvim
  ["kanagawa-wave"] = scheme("kanagawa.nvim", "kanagawa-wave"),
  ["kanagawa-dragon"] = scheme("kanagawa.nvim", "kanagawa-dragon"),
  ["kanagawa-lotus"] = scheme("kanagawa.nvim", "kanagawa-lotus"),
  -- olimorris/onedarkpro.nvim
  ["one-dark"] = scheme("onedarkpro.nvim", "onedark"),
  ["one-light"] = scheme("onedarkpro.nvim", "onelight"),
  -- Shatur/neovim-ayu
  ["ayu-dark"] = scheme("neovim-ayu", "ayu-dark"),
  ["ayu-mirage"] = scheme("neovim-ayu", "ayu-mirage"),
  ["ayu-light"] = scheme("neovim-ayu", "ayu-light"),
  -- EdenEast/nightfox.nvim
  ["nightfox"] = scheme("nightfox.nvim", "nightfox"),
  ["carbonfox"] = scheme("nightfox.nvim", "carbonfox"),
  ["nordfox"] = scheme("nightfox.nvim", "nordfox"),
  ["terafox"] = scheme("nightfox.nvim", "terafox"),
  ["dayfox"] = scheme("nightfox.nvim", "dayfox"),
  -- projekt0n/github-nvim-theme
  ["github-dark"] = scheme("github-nvim-theme", "github_dark"),
  ["github-light"] = scheme("github-nvim-theme", "github_light"),
  -- nyoom-engineering/oxocarbon.nvim
  ["oxocarbon-dark"] = scheme("oxocarbon.nvim", "oxocarbon"),
  ["oxocarbon-light"] = scheme("oxocarbon.nvim", "oxocarbon"),
}

-- Colorscheme when there's no axiom theme file (nil: leave it alone)
M.fallback = nil

local function read_theme()
  local fd = io.open(M.path, "r")
  if not fd then
    return nil
  end
  local ok, theme = pcall(vim.json.decode, fd:read("*a"))
  fd:close()
  if ok and type(theme) == "table" and type(theme.colors) == "table" then
    return theme
  end
end

local function apply_native(scheme)
  if not scheme then
    return false
  end
  if scheme.plugin then
    -- A lazily loaded colorscheme plugin (lazy.nvim). One lazy.nvim doesn't
    -- know isn't installed: skip it quietly (load() would notify an error)
    local ok, lazy_config = pcall(require, "lazy.core.config")
    if ok then
      if not lazy_config.plugins[scheme.plugin] then
        return false
      end
      pcall(function()
        require("lazy").load({ plugins = { scheme.plugin } })
      end)
    end
  end
  return pcall(vim.cmd.colorscheme, scheme.colorscheme)
end

-- The base16 styling guide's main groups, for configs without mini.base16
local function apply_plain(c)
  vim.cmd("highlight clear")
  if vim.fn.exists("syntax_on") == 1 then
    vim.cmd("syntax reset")
  end
  local groups = {
    Normal = { fg = c.base05, bg = c.base00 },
    NormalFloat = { fg = c.base05, bg = c.base01 },
    FloatBorder = { fg = c.base03, bg = c.base01 },
    Comment = { fg = c.base03, italic = true },
    Constant = { fg = c.base09 },
    String = { fg = c.base0B },
    Character = { fg = c.base08 },
    Number = { fg = c.base09 },
    Boolean = { fg = c.base09 },
    Identifier = { fg = c.base08 },
    Function = { fg = c.base0D },
    Statement = { fg = c.base0E },
    Keyword = { fg = c.base0E },
    Operator = { fg = c.base05 },
    PreProc = { fg = c.base0A },
    Type = { fg = c.base0A },
    Special = { fg = c.base0C },
    Delimiter = { fg = c.base0F },
    Todo = { fg = c.base0A, bg = c.base01 },
    Error = { fg = c.base08, bg = c.base00 },
    Title = { fg = c.base0D, bold = true },
    Directory = { fg = c.base0D },
    CursorLine = { bg = c.base01 },
    CursorLineNr = { fg = c.base04, bg = c.base01 },
    LineNr = { fg = c.base03 },
    SignColumn = { fg = c.base03 },
    ColorColumn = { bg = c.base01 },
    Visual = { bg = c.base02 },
    Search = { fg = c.base01, bg = c.base0A },
    IncSearch = { fg = c.base01, bg = c.base09 },
    MatchParen = { bg = c.base03 },
    Pmenu = { fg = c.base05, bg = c.base01 },
    PmenuSel = { fg = c.base01, bg = c.base05 },
    StatusLine = { fg = c.base04, bg = c.base02 },
    StatusLineNC = { fg = c.base03, bg = c.base01 },
    TabLine = { fg = c.base03, bg = c.base01 },
    TabLineSel = { fg = c.base0B, bg = c.base01 },
    WinSeparator = { fg = c.base02 },
    Folded = { fg = c.base03, bg = c.base01 },
    NonText = { fg = c.base03 },
    WarningMsg = { fg = c.base08 },
    ErrorMsg = { fg = c.base08 },
    DiffAdd = { fg = c.base0B, bg = c.base01 },
    DiffChange = { fg = c.base03, bg = c.base01 },
    DiffDelete = { fg = c.base08, bg = c.base01 },
    DiffText = { fg = c.base0D, bg = c.base01 },
    DiagnosticError = { fg = c.base08 },
    DiagnosticWarn = { fg = c.base0A },
    DiagnosticInfo = { fg = c.base0D },
    DiagnosticHint = { fg = c.base0C },
  }
  for name, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, name, spec)
  end
  return true
end

-- a over b by alpha, both "#rrggbb"
local function blend(a, b, alpha)
  local function rgb(h)
    return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
  end
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  local function mix(x, y)
    return math.floor(x * alpha + y * (1 - alpha) + 0.5)
  end
  return string.format("#%02x%02x%02x", mix(r1, r2), mix(g1, g2), mix(b1, b2))
end

-- The theme's own accent over the base16 groups, Material-style: base16
-- leaves a wallpaper theme's seed color (its accent) on delimiters only
local function apply_accents(theme)
  local s, t = theme.semantic, theme.text or {}
  if type(s) ~= "table" or not (s.accent and s.background and s.foreground) then
    return
  end
  local accent, alt = t.accent or s.accent, t.accentAlt or s.accentAlt or s.accent
  local bg, border = s.background, s.border or s.backgroundHighlight
  local function tint(alpha)
    return blend(s.accent, bg, alpha)
  end
  local groups = {
    Keyword = { fg = accent },
    Statement = { fg = accent },
    Conditional = { fg = accent },
    Repeat = { fg = accent },
    Exception = { fg = accent },
    ["@keyword"] = { link = "Keyword" },
    ["@keyword.function"] = { link = "Keyword" },
    ["@keyword.return"] = { link = "Keyword" },
    ["@keyword.conditional"] = { link = "Conditional" },
    ["@keyword.repeat"] = { link = "Repeat" },
    Title = { fg = accent, bold = true },
    Directory = { fg = alt },
    CursorLineNr = { fg = accent, bold = true },
    Visual = { bg = tint(0.25) },
    Search = { fg = s.foreground, bg = tint(0.35) },
    IncSearch = { fg = bg, bg = s.accent },
    CurSearch = { fg = bg, bg = s.accent },
    MatchParen = { fg = accent, bg = tint(0.2), bold = true },
    FloatBorder = { fg = border, bg = s.backgroundAlt },
    FloatTitle = { fg = accent, bg = s.backgroundAlt, bold = true },
    WinSeparator = { fg = border },
    PmenuSel = { fg = s.foreground, bg = tint(0.3), bold = true },
    PmenuThumb = { bg = s.accent },
    TabLineSel = { fg = accent, bg = s.backgroundAlt, bold = true },
  }
  for name, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, name, spec)
  end
end

local function apply_palette(theme)
  local ok = pcall(function()
    require("mini.base16").setup({ palette = theme.colors, use_cterm = true })
  end)
  if not ok then
    ok = pcall(apply_plain, theme.colors)
  end
  if not ok then
    return false
  end
  pcall(apply_accents, theme)
  vim.g.colors_name = "axiom-" .. theme.stem
  -- Neither fires ColorScheme itself; statuslines ('auto' themes) listen for it
  vim.api.nvim_exec_autocmds("ColorScheme", { pattern = vim.g.colors_name })
  return true
end

function M.reload()
  local theme = read_theme()
  if not theme then
    apply_native(M.fallback)
    return
  end
  vim.o.background = theme.variant == "light" and "light" or "dark"
  if apply_native(M.map[theme.stem]) then
    return
  end
  if not apply_palette(theme) then
    apply_native(M.fallback)
  end
end

function M.setup(opts)
  opts = opts or {}
  M.map = vim.tbl_extend("force", M.map, opts.map or {})
  if opts.fallback then
    M.fallback = opts.fallback
  end
  M.reload()
end

return M
