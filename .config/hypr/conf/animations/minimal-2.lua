-- HyprCandy animation preset: minimal-2
-- Converted from conf/animations/minimal-2.conf
hl.config({ animations = { enabled = yes } })
hl.curve("quart", { type = "bezier", points = { {0.25, 1}, {0.5, 1} } })
hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "quart", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 6, bezier = "quart" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 6, bezier = "quart" })
hl.animation({ leaf = "fade", enabled = true, speed = 6, bezier = "quart" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "quart" })

return true
