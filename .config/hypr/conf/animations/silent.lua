-- HyprCandy animation preset: silent
-- Converted from conf/animations/silent.conf
hl.config({ animations = { enabled = true } })
hl.curve("linear", { type = "bezier", points = { {0, 0}, {0, 1} } })
hl.animation({ leaf = "windows", enabled = true, speed = 1, bezier = "default" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1, bezier = "default", style = "popin 1%" })
hl.animation({ leaf = "border", enabled = true, speed = 1, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 1, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 1, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1, bezier = "default" })

return true
