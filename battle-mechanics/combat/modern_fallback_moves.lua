-- combat/modern_fallback_moves.lua -- the engine's own hardcoded move
-- records for moves the game data may not supply.
--
-- WHY THIS EXISTS
-- The move data this engine runs on comes from national_dex (a hard
-- dependency), but national_dex does not carry every move. The clearest
-- case is PIKA_PAPOW, the fourth Let's Go partner-Pikachu move: the build
-- this repo references registers ZIPPYZAP, FLOATYFALL and SPLISHYSPLASH
-- but NOT PIKA_PAPOW, so a mon built carrying it (g9-battle-sample's
-- LEAGUE ACES Red does exactly that) would hold a move id with no record
-- at all -- no name, no type, no damage. This file supplies the record
-- when the registry has none, and leaves an existing, authoritative
-- record alone.
--
-- WHAT A RECORD CANNOT SAY, and this file adds
-- Pika Papow's power is not a fixed number: it is computed from the
-- user's FRIENDSHIP (Bulbapedia, Generation VII):
--
--   Power = floor(Friendship / 2.5)
--
-- which varies between 1 (friendship 0) and 102 (friendship 255). That is
-- a runtime formula, so it goes through registerPowerOverride -- the same
-- base-power substitution seam Heavy Slam / Return / Fury Cutter use --
-- and NOT into the record's static `power`. The record keeps the
-- placeholder 1 this codebase uses for a move whose real power is
-- computed at runtime, exactly like national_dex's own computed-power
-- moves (modern_combat.lua's own header calls `power = 1` "the base
-- game's placeholder for computed at runtime"); the override always
-- answers, so a hit never actually uses the placeholder.
--
-- The move also bypasses the accuracy check and always hits (the dex
-- text's own "Ignores accuracy and evasion modifiers"), which is the
-- `sureHit` flag modern_crit_override.lua's battle.accuracy wrap already
-- honours on BOTH generations -- Gen 1's percent-domain threshold would
-- otherwise turn a 0-accuracy record into a ~255/256 miss.
--
-- POWER-OVERRIDE CHAIN NOTE
-- registerPowerOverride is one function per move id (modern_combat.lua),
-- so this file's entry is the single owner of PIKA_PAPOW's power. It
-- reads friendship with the same fallback RETURN/FRUSTRATION use
-- (mon.happiness, default 70) so an older mon with no friendship field
-- still plays as an ordinary move.
return function(mod)
  local registerPowerOverride = mod.exports.registerPowerOverride
  assert(registerPowerOverride,
    "modern_fallback_moves: combat/modern_combat.lua must load first")

  -- name/type/category/power/accuracy/pp/effect/priority are the move
  -- schema's record shape (Schemas.lua R.moves). `sureHit` is an engine
  -- extension read off the live record by modern_crit_override.lua -- the
  -- same unknown-but-preserved key wireMovepoolSubEffects patches onto a
  -- critRate>=6 move, so the top-level record stays extensible and the
  -- key survives the loader's validation.
  local FALLBACK_MOVES = {
    PIKA_PAPOW = {
      id = "PIKA_PAPOW", name = "Pika Papow", type = "ELECTRIC",
      category = "special", power = 1, accuracy = 100, pp = 20,
      priority = 0, effect = "NO_ADDITIONAL_EFFECT", sureHit = true,
    },
  }

  local registered = {}
  for id, record in pairs(FALLBACK_MOVES) do
    local exists = false
    if mod.content and mod.content.moves
        and type(mod.content.moves.get) == "function" then
      local ok, live = pcall(mod.content.moves.get, mod.content.moves, id)
      exists = ok and live ~= nil
    end
    if not exists then
      mod.content.moves:register(id, record)
      registered[#registered + 1] = id
    end
  end

  -- Pika Papow: power = floor(friendship / 2.5), clamped to [1, 102].
  -- `ctx.user` is the real mon on Gen 2 and the battler wrapper on Gen 1
  -- (the mon hangs under .mon) -- exactly the shape RETURN/FRUSTRATION
  -- normalize in combat/modern_power_conditions.lua, whose rawMon helper
  -- this mirrors so the friendship read is identical across both files.
  local function rawMon(who, gen2)
    if gen2 then return who end
    return who and who.mon
  end
  local PIKA_PAPOW_MIN, PIKA_PAPOW_MAX = 1, 102
  registerPowerOverride("PIKA_PAPOW", function(ctx)
    local mon = rawMon(ctx and ctx.user, ctx and ctx.gen2)
    local friendship = (mon and tonumber(mon.happiness)) or 70
    local power = math.floor(friendship / 2.5)
    if power < PIKA_PAPOW_MIN then power = PIKA_PAPOW_MIN end
    if power > PIKA_PAPOW_MAX then power = PIKA_PAPOW_MAX end
    return power
  end)

  if #registered > 0 and mod.log and type(mod.log.info) == "function" then
    mod.log:info(string.format(
      "g9-battle-engine: modern_fallback_moves: registered %d hardcoded "
        .. "fallback move record(s) [%s]",
      #registered, table.concat(registered, ", ")))
  end
  return true
end
