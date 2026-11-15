local primary_thickness=11.7 -- Previous 9px stroke +30%; outer radius stays fixed.
return {
    -- Verified in this installation's CT_CharactersAttributes.Hero_MaxStamina.
    base_capacity = 150,
    auto_base_capacity = true,
    bonus_ring_capacity = 150,
    -- Time to traverse 90% of a change, in seconds. Independent of frame rate.
    smoothing_seconds = 0.12,
    -- One multiplier scales the complete HUD: rings, hole, strokes and gaps.
    ui_scale = 1,
    -- Ring geometry is baked into the generated antialiased PNG masks.
    -- Visible stock-ring match, accounting for the game's render scale.
    -- Primary/second/third stroke weights follow 1 : 1/2 : 1/3.
    radius = 23.5-primary_thickness/2,
    base_thickness = primary_thickness,
    bonus_thickness = primary_thickness/2,
    outer_bonus_thickness = primary_thickness/3,
    ring_gap = 1.5,
    edge_softness = 1.25,
    -- Original monochrome surface; palette and warning tint remain dynamic.
    -- Available without rebuilding: flat / paint / hatch.
    surface_style = "paint",
    -- Prepared mask bank, not a three-ring display cap. More than native builds need.
    max_bonus_rings = 12,
    new_ring_min_capacity = 10,
    -- Green uses equipment/progression capacity; yellow uses actual timed effects.
    split_sources = true,
    source_poll_seconds = 0.35,
    initial_ring_scale = 1.15,
    temporary_ring_scale = 0.52,
    temporary_group_gap = 5,
    temporary_color = {R = 0.83, G = 0.60, B = 0.075, A = 1},
    -- Optional visual test; disabled after the user's in-game verification.
    -- Set false and reload to restore source-driven capacity/layout.
    visual_test_mode = false,
    test_permanent_capacity = 450,
    test_temporary_capacity = 150,
    -- Linear RGB; the main tint encodes approximately as sRGB #78AA35.
    color = {R = 0.188, G = 0.402, B = 0.0356, A = 1},
    critical_color = {R = 0.68, G = 0.258, B = 0.032, A = 1},
    background_color = {R = 0.008, G = 0.018, B = 0.006, A = 0.86},
    warning_start_fraction = 0.30,
    critical_fraction = 0.10,
    warning_smoothing_seconds = 0.14,
    enabled = true,
}
