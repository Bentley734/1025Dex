-- Dispatch engine for abilities/data/other_misc2.lua -- see that file's
-- own header for the full real-mechanic grounding.
return function(mod, data)
  local Strings = require("src.core.Strings")
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveFlags,
    "other_misc2: national_dex must be loaded first")
  local moveFlags = nationalDex.exports.moveFlags
  local abilityIdOf = mod.exports.abilityIdOf
  local makesContact = mod.exports.makesContact
  local registerDamageModifier = mod.exports.registerDamageModifier
  assert(abilityIdOf and makesContact and registerDamageModifier,
    "other_misc2: ability_dispatch.lua, long_reach.lua, and modern_combat.lua must all load first")

  ------------------------------------------------------------------
  -- PERISH BODY -- see this file's own data header for the real gate.
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local battle, user, target, move = ev and ev.battle, ev and ev.user, ev and ev.target, ev and ev.move
    if not (battle and user and target and move and (ev.damage or 0) > 0) then return end
    if not (data.PERISHBODY and abilityIdOf(target) == "PERISHBODY") then return end
    if (target.hp or 0) <= 0 then return end -- doesn't trigger if the holder itself fainted
    if not makesContact(move.id, user) then return end
    if target.perishSongTurns or user.perishSongTurns then return end -- real gate: neither side already counting down
    target.perishSongTurns = 3
    user.perishSongTurns = 3
    battle:emit({ kind = "message", text = Strings("Both Pokémon will faint in two turns!") })
  end)

  ------------------------------------------------------------------
  -- PUNK ROCK -- own sound moves 1.3x dealt, sound moves taken 0.5x.
  -- One shared modifier: ctx carries both user and target, so both
  -- halves read off the same ctx rather than two separate registrations
  -- racing on priority order.
  ------------------------------------------------------------------
  registerDamageModifier("punkrock", 90, function(ctx)
    local flags = ctx.move and moveFlags(ctx.move.id)
    if not (flags and flags.sound) then return 1.0 end
    local mult = 1.0
    if data.PUNKROCK and abilityIdOf(ctx.user) == "PUNKROCK" then mult = mult * 1.3 end
    if data.PUNKROCK and abilityIdOf(ctx.target) == "PUNKROCK" then mult = mult * 0.5 end
    return mult
  end)

  mod.log:info("g9-battle-engine: other_misc2 installed (PERISHBODY, PUNKROCK)")
end
