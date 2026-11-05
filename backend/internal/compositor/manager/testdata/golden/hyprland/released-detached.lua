-- Given back by axiom when it stopped managing Hyprland: this file is yours
-- now, and axiom won't write it again. It starts axiom and loads
-- /nonexistent/home/.config/hypr/user/*.lua, as axiom's managed one did.
hl.on("hyprland.start", function() hl.exec_cmd("'/home/user/.local/bin/axiom' run") end) -- axiom

-- Not when it's required as one of those files itself (a managed takeover
-- adopts it into user/): the file requiring it loads them
if select("#", ...) == 0 then
  -- Your files, through require (as user.<name>) so Hyprland reloads when
  -- one changes. Shared modules go in user/lib/ (require("user.lib.x")),
  -- which isn't loaded here. A failing file doesn't stop the rest; the
  -- errors are raised together at the end (hyprctl configerrors).
  local errors = {}
  local files = io.popen("cd " .. "'/nonexistent/home/.config/hypr/user'" .. " 2>/dev/null && ls -1 *.lua 2>/dev/null")
  if files then
    for file in files:lines() do
      local name = file:gsub("%.lua$", "")
      if name:find(".", 1, true) then
        errors[#errors + 1] = "user/" .. file .. ": not loaded: a dot in its name reads as a folder to require, so rename it"
      else
        local ok, err = pcall(require, "user." .. name)
        if not ok then errors[#errors + 1] = tostring(err) end
      end
    end
    files:close()
  end
  if #errors > 0 then error(table.concat(errors, "\n")) end
end