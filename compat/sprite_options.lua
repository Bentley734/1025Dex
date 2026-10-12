-- Convert obsolete global artwork and 3DB controls into independent selections.
-- Only the mod option bucket is changed; sprite layout and playthrough data stay intact.
return function(values)
  if type(values) ~= "table" then return end
  local function style(value)
    value = tonumber(value)
    if value and value >= 0 and value <= 4 and value == math.floor(value) then return value end
  end
  local legacy = style(values.sprite_style) or 3
  for _, key in ipairs({"enemy_sprite_style", "player_sprite_style"}) do
    values[key] = style(values[key]) or legacy
  end
  local view = tonumber(values.player_sprite_view)
  if view ~= 0 and view ~= 1 and view ~= 2 then
    view = values.battle_frontal == true and (values.battle_front_flip == true and 2 or 1) or 0
  end
  values.player_sprite_view = view
  for _, key in ipairs({"sprite_style", "enable_battle_sprites", "animate_sprites", "battle_frontal", "battle_front_flip"}) do
    values[key] = nil
  end
end
