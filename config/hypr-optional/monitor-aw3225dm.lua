
-- resume.sh: Alienware AW3225DM 180Hz + VRR
-- Its preferred mode is 60Hz, so ask for 180Hz explicitly. Matched by model
-- name rather than port, so it follows the monitor to whichever output it's on.
hl.monitor({ output = "desc:Dell Inc. AW3225DM", mode = "2560x1440@180", position = "auto", scale = omarchy_monitor_scale })

-- VRR: 0 = off, 1 = always, 2 = fullscreen only.
hl.config({
  misc = {
    vrr = 2,
  },
})
