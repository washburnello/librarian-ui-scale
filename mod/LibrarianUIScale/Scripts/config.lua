-- LibrarianUIScale configuration.
--
-- The UI scale is chosen in game with left/right arrows between the values
-- 0.25x and 3.00x in 0.25 steps. `scale` selects the starting value the first
-- time the mod runs; after that the last chosen value is remembered in
-- `scale.txt`. 1.0 = vanilla (no change).
--
-- `focus` registers the injected row in the game's controller-focus lists so it
-- can be reached with a gamepad. Set to false to disable if it misbehaves.
return {
    scale = 1.0,
    min = 0.25,
    max = 3.0,
    step = 0.25,
    focus = true,
}
