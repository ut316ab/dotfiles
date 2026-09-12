-- Pin specific apps to specific workspaces.
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/

o.window("^steam$", { workspace = "9" })
-- Steam's main window opens small and floating by default; size it up and center it.
-- Steam runs under XWayland and re-requests its own size after mapping, so the
-- resize gets fought unless we suppress its X11 configure requests.
o.window("^steam$", { size = { "monitor_w * 0.85", "monitor_h * 0.85" }, center = true, suppress_event = "x11configurerequest" })
o.window("^org\\.mozilla\\.Thunderbird$", { workspace = "8" })
o.window("^chrome-discord\\.com__channels_@me-Default$", { workspace = "7 silent" })
o.window("^zen$", { workspace = "2" })
o.window("^qemu$", { workspace = "6 silent" })
