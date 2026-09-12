-- LibrarianUIScale configuration.
--
-- `scale` is the UI scale used the first time the mod runs. After that the last
-- value chosen with the in-game slider is remembered in `scale.txt`.
-- 1.0 = vanilla (no change).
--
-- `focus` registers the injected row in the game's controller-focus lists so it
-- can be reached with a gamepad. Set to false to disable if it misbehaves.
return {
    scale = 1.0,
    min = 1.0,
    max = 2.0,
    step = 0.1,
    focus = true,
}
