for _, id in ipairs(AXIOM_PAUSED or {}) do do local b = AXIOM_BINDS and AXIOM_BINDS[id]; if b then pcall(function() b:set_enabled(true) end) end end end
AXIOM_PAUSED = nil
AXIOM_PAUSED = { "super-ctrl-s", "super-c", "super-z", "super-mouse-272" }
for _, id in ipairs(AXIOM_PAUSED) do do local b = AXIOM_BINDS and AXIOM_BINDS[id]; if b then pcall(function() b:set_enabled(false) end) end end end
if hl.get_current_submap() == "axiom_paused" then hl.dispatch(hl.dsp.submap("reset")) end
