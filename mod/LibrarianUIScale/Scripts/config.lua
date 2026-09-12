-- LibrarianUIScale configuration.
--
-- The UI scale is chosen with the Settings slider between 0.25x and 2.00x in
-- 0.25 steps. Moving the slider only previews the value in the row; the scale is
-- applied when you press the game's Apply button. `scale` selects the starting
-- value the first time the mod runs; after that the last applied value is
-- remembered in `scale.txt`. 1.0 = vanilla (no change).
--
-- `menu_cap` limits how large the UI is drawn while a full-screen menu is open
-- (a high scale would push the menu's own controls off the bottom). Your chosen
-- scale still applies in game.
--
-- `focus` registers the injected row in the game's controller-focus lists.
return {
    scale = 1.0,
    min = 0.25,
    max = 2.0,
    step = 0.25,
    menu_cap = 1.25,
    focus = true,
}
