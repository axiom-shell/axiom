for _, id in ipairs(AXIOM_PAUSED or {}) do do local b = AXIOM_BINDS and AXIOM_BINDS[id]; if b then pcall(function() b:set_enabled(true) end) end end end
AXIOM_PAUSED = nil
hl.define_submap("axiom_paused", function()
  for _, key in ipairs(AXIOM_PAUSE_KEYS or {}) do hl.unbind(key) end
  hl.bind("SUPER + F", hl.dsp.window.fullscreen(), { description = "Window: Fullscreen" })
  hl.bind("SUPER + C", hl.dsp.window.close(), { description = "Window: Close window" })
end)
AXIOM_PAUSE_KEYS = { "SUPER + F", "SUPER + C" }
hl.dispatch(hl.dsp.submap("axiom_paused"))
