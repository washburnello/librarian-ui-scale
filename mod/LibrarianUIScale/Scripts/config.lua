-- LibrarianUIScale configuration.
--
-- The UI scale is chosen in game with the Settings slider between 0.25x and
-- 3.00x in 0.25 steps. `scale` selects the starting value the first time the
-- mod runs; after that the last chosen value is remembered in `scale.txt`.
-- 1.0 = vanilla (no change).
--
-- `menu_cap` limits how large the UI is drawn while the Settings menu is open.
-- A high scale makes the menu taller than the screen and its controls (including
-- this setting) get pushed off the bottom, so the menu is capped to keep it
-- usable. Your chosen scale still applies in game.
--
-- `focus` registers the injected row in the game's controller-focus lists.
return {
    scale = 1.0,
    min = 0.25,
    max = 3.0,
    step = 0.25,
    menu_cap = 1.25,
    focus = true,
}
