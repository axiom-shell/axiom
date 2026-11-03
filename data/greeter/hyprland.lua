-- The greeter's Hyprland (greeter-session.sh starts it as greetd's user):
-- nothing but axiom's greeter. Monitors and, when the user's axiom manages
-- Hyprland, their keyboard, mouse and touchpad settings come from the
-- bundle once the greeter starts (GreetdManager); these are what holds
-- until then, and without a bundle.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.config({
  input = { numlock_by_default = true },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
  animations = { enabled = false },
})

hl.on("hyprland.start", function()
  hl.exec_cmd("/usr/share/axiom-greeter/scripts/greeter/greeter-session.sh shell")
end)
