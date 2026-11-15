for _, r in ipairs(AXIOM_RULES or {}) do pcall(function() r:set_enabled(false) end) end
AXIOM_RULES = nil
AXIOM_RULES = {}
pcall(function() local r = hl.window_rule({ name = "axiom-rule-wine-0", match = { xwayland = true }, float = true, no_screen_share = true }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)
pcall(function() local r = hl.window_rule({ name = "axiom-rule-wine-1", match = { title = "\\A(?s:.*)(?:Wine)(?s:.*)\\z" }, float = true, no_screen_share = true }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)
pcall(function() local r = hl.window_rule({ name = "axiom-rule-steam-0", match = { class = "\\A(?:steam)\\z" }, monitor = "DP-1", workspace = "3", maximize = true }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)
pcall(function() local r = hl.window_rule({ name = "axiom-rule-calc-0", match = { class = "\\A(?:(?:org\\.gnome\\.Calculator)|(?:gnome-calculator))\\z" }, workspace = "special:calc silent", float = true, center = true }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)
pcall(function() local r = hl.window_rule({ name = "axiom-rule-files-0", match = { class = "\\A(?:org\\.gnome\\.Nautilus)\\z" }, opacity = "0.85 override", no_blur = true }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)
pcall(function() local r = hl.window_rule({ name = "axiom-rule-games-0", match = { class = "\\A(?s:.*)(?:\\Asteam_app_[0-9]+\\z)(?s:.*)\\z" }, workspace = "name:games silent", fullscreen = true, immediate = true }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)
pcall(function() local r = hl.window_rule({ name = "axiom-rule-games-1", match = { class = "negative:\\A(?:(?:steam))\\z", title = "\\A(?:Game)\\z" }, workspace = "name:games silent", fullscreen = true, immediate = true }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)
pcall(function() local r = hl.window_rule({ name = "axiom-rule-pip-0", match = { class = "\\A(?:firefox)\\z", title = "\\A(?s:.*)(?:Picture-in-Picture)(?s:.*)\\z" }, float = true, size = "640 360", pin = true, no_initial_focus = true }); r:set_enabled(true); AXIOM_RULES[#AXIOM_RULES + 1] = r end)
