-- Our pictures already have a bottom-centred canvas. Cartridge padding and
-- elevation describe the original art, so cancel them only for replaced pics.
return function()
  local Ui = require('src.core.game3.battle.ui')
  if Ui.__completeDexLift then return end
  Ui.__completeDexLift = true
  local original = assert(Ui.bounceOffset, 'Missing FireRed battle offset API')
  local Pokemon = require('src.core.game3.pokemon')
  local function liftFor(id)
    local Battle = package.loaded['src.core.game3.battle']
    local st = Ui._st or (Battle and Battle._st)
    if not st then return 0 end
    local numeric = tonumber(id)
    local back = id == 'player' or (numeric and numeric % 2 == 0)
    numeric = numeric or (back and 0 or 1)
    local side = back and 'player' or 'enemy'
    local b = numeric and ((numeric == 0 and st.player) or
      (numeric == 1 and st.enemy) or (st.battlers and st.battlers[numeric])) or st[side]
    local Anim = package.loaded['src.core.game3.battle.anim']
    local key = st.double and (numeric or id) or side
    if Anim and Anim.shownBattler then b = Anim.shownBattler(key, b) or b end
    if not b then return 0 end
    local pres = Anim and Anim.present and Anim.present(key)
    -- These are native substitute/ghost pictures, not the replaced mon art.
    if (pres and pres.substitute) or (Ui.showsGhost and Ui.showsGhost(side, st)) then return 0 end
    local mon = b.mon
    local species = b.species or (mon and Pokemon.speciesOf and Pokemon.speciesOf(mon))
      or (mon and (mon.species or mon.speciesId))
    if b.expTransform then
      local transformed = pres and pres.transformSpecies
      if not transformed and not (pres and pres.pendingTransform) then transformed = b.expTransform.species end
      species = transformed or species
    end
    if not species then return 0 end
    local form = Ui.castformForm and Ui.castformForm(side, b) or 0
    local picSpecies, shiny, personality = species, false, mon and mon.personality
    if Ui.picArgs then picSpecies, shiny, personality = Ui.picArgs(b, species) end
    local provider = back and Pokemon.backPic or Pokemon.frontPic
    local pic = provider and provider(picSpecies, form, shiny, personality)
    -- Zero marks a completed replacement; pending/native pictures have no marker.
    if not pic or pic.__completeDexBattleLift == nil then return 0 end
    if not Ui.battlerSpriteCenter then return 0 end
    local Coords = require('src.core.game3.battle.pic_coords')
    local base = Anim and Anim.coords and st.double and Anim.coords(st, numeric)
      or Coords.battlerCoords(st.double, numeric)
    if not base then return 0 end
    local _, nativeY = Ui.battlerSpriteCenter(st.double and numeric or side, species, base, form, false)
    -- Field ends at y=112. Keep the complete back art above the command panel,
    -- including the lower double-battle ally, without a species-height lift.
    local wantedY = back and math.min(base.y, 80) or base.y
    return wantedY - nativeY
  end
  Ui.bounceOffset = function(kind,id)
    local offset = original(kind,id) or 0
    if kind ~= 'mon' then return offset end
    local ok, lift = pcall(liftFor, id)
    return offset + (ok and lift or 0)
  end
end
