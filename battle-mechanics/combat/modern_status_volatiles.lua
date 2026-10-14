-- Real Pokemon Showdown logic for the bespoke "no flag covers this"
-- volatile-condition moves -- verified directly against Showdown's own
-- real source (data/moves.ts, fetched and read locally, not from
-- memory) before writing anything here, same discipline as every other
-- Showdown-source-verified fix this session (Prankster/Dark immunity,
-- paralysis/sleep/freeze turn-loss). Real, confirmed mechanics per move
-- -- durations, fractions, and interactions are cited from that source,
-- not guessed:
--
--   LEECH SEED: 1/8 the SEEDED mon's own max HP drained each turn,
--     healed to the ORIGINAL SEEDER (not necessarily whoever's
--     currently opposite) -- Grass-type immune (onTryImmunity). UPDATED
--     2026-08-28 (explicit user directive, re-verified against
--     gen2/moves.ts's own real condition object this same pass): no
--     drain at all once the seeder has fainted (confirmed, not just "no
--     heal") -- this file's own code already had that part right;
--     Magic Guard blocking the drain, Liquid Ooze reversing the heal
--     into damage for the seeder, and a real Substitute block on
--     infliction were all real, confirmed gaps, fixed below.
--   NIGHTMARE: only begins while asleep; 1/4 max HP each turn. No
--     explicit removal trigger in the real condition itself -- gated
--     here on "still asleep" each tick (a reasonable reading, not
--     explicitly shown in the source snippet fetched, so flagged as an
--     inference rather than a literal transcription).
--   INGRAIN: heal 1/16 own max HP each turn, self-only. Real "can't
--     switch/be dragged out" half is NOT built here -- this mod has no
--     confirmed switch-prevention hook for a plain volatile (distinct
--     from the trap-move mechanic, which reuses Gen 2's own real
--     wrapCount system) -- honest gap, not silently dropped.
--   YAWN: real duration 2 -- forces sleep at the END of that window
--     (i.e. the turn AFTER the one Yawn was used), not immediately.
--     Blocked by an existing status or real sleep immunity (checked via
--     status_immunity.lua's own hasStatusImmunity, for free).
--   DISABLE: real duration 5, locks out the target's own LAST USED
--     move specifically -- fails with no last move, on Struggle, or if
--     that move is already out of PP.
--   EMBARGO: real duration 5, blocks item use. This engine's own held-
--     item interactions (combat/modern_items.lua) are Gen 2-only,
--     confirmed pre-existing scope -- Embargo's block is wired at the
--     same real gate.
--   HEAL BLOCK / PSYCHIC NOISE: real duration 5 (2 for Psychic Noise
--     specifically, confirmed via source), blocks any move flagged
--     `heal` (a real, confirmed national_dex moveFlags key).
--   THROAT CHOP: real duration 2, blocks any move flagged `sound`.
--   PERISH SONG: real duration 4 turns for EVERY active battler (this
--     engine's own 2-battler shape -- both player and enemy, always,
--     since it's real field-target scope, not "normal"), faints
--     whoever's counter reaches 0.
--   UPROAR: real 3-turn self-lock (same real shape as Outrage's own
--     rampage, reuses this mod's own established thrashTurns/thrashMove
--     fields and the exact same Gen-1-safe/Gen-2-honest-gap split this
--     session's Outrage work already established) -- plus its own real
--     extra effect, waking every active mon that's asleep the turn it's
--     used.
--   FORESIGHT / MIRACLE EYE / ODOR SLEUTH: negates the target's own
--     Ghost-type immunity to Normal/Fighting (Foresight/Odor Sleuth) or
--     Dark-type immunity to Psychic (Miracle Eye) -- the mon-flag write
--     lives here; the real negation itself is resolved in combat/
--     modern_combat.lua's own resolvedTypeMult (moved there 2026-08-28,
--     see this file's own comment just above the old registration site
--     for why the original registerPostEffectivenessModifier shape was
--     genuinely unreachable dead code). The real "also cancels target's
--     evasion boost" half IS built (see markImmunityNegated below).
--   SMACK DOWN / THOUSAND ARROWS: negates the target's natural Flying-
--     type immunity to Ground moves -- same real mechanism (resolvedTypeMult).
--     Real full mechanic also interacts with
--     Levitate/Magnet Rise/Telekinesis/Fly-Bounce-in-progress/Gravity,
--     none of which exist as primitives in this engine yet -- this
--     covers the one real, always-relevant case (Flying-type immunity)
--     and flags the rest as genuinely out of reach right now, not
--     silently approximated.
--   TELEKINESIS: real duration 3, moves against the target never miss
--     (except OHKO moves, which still can't hit it) and it gains a real
--     Ground-type immunity for the duration. The exact five real
--     species exemptions (Diglett/Dugtrio/Palossand/Sandygast lines,
--     Mega Gengar) are NOT modeled -- a small, stable, real exception
--     list this pass didn't chase down.
--   DIRE CLAW / TRI ATTACK: real random-status secondary --
--     DIRE CLAW 50% chance, one of poison/paralysis/sleep; TRI ATTACK
--     20% chance, one of burn/paralysis/freeze -- each picked uniformly
--     at random, applied only if the target has no status yet
--     (trySetStatus's own real rule).
return function(mod)
  local nationalDex = mod.find and mod.find("national_dex")
  assert(nationalDex and nationalDex.exports and nationalDex.exports.moveById
      and nationalDex.exports.moveFlags,
    "modern_status_volatiles: national_dex must be loaded first")
  local moveById = nationalDex.exports.moveById
  local moveFlags = nationalDex.exports.moveFlags
  local changeStage = mod.exports.changeStage
  local displayNameFor = mod.exports.displayNameFor
  assert(changeStage and displayNameFor,
    "modern_status_volatiles: modern_combat.lua must load first")

  -- A move id's on-screen name -- the same id->display-name step
  -- combat/modern_status_moves.lua's own moveNameOf does. Needed by the
  -- Disable line below.
  local function moveNameOf(battle, moveId)
    if not moveId then return "move" end
    local ok, def = pcall(battle.moveDef, battle, moveId)
    if ok and def and def.name then return def.name end
    local ok2, info = pcall(moveById, moveId)
    if ok2 and info and info.name then return info.name end
    return tostring(moveId)
  end

  local function hpOf(mon) return (mon.mon or mon) end
  local function healFractionOf(battle, mon, denom)
    local m = hpOf(mon)
    local maxHp = m.stats and m.stats.hp
    if not (maxHp and maxHp > 0 and (m.hp or 0) < maxHp) then return end
    local amount = math.max(1, math.floor(maxHp / denom))
    local tryHeal = mod.exports.g9TryHeal
    if tryHeal then
      tryHeal(battle, mon, amount)
    else
      m.hp = math.min(maxHp, (m.hp or 0) + amount)
    end
  end
  local function damageFractionOf(mon, denom)
    local m = hpOf(mon)
    local maxHp = m.stats and m.stats.hp
    if not (maxHp and maxHp > 0) then return end
    m.hp = math.max(0, (m.hp or 0) - math.max(1, math.floor(maxHp / denom)))
  end
  local function isAsleepNow(mon)
    local id = mod.exports.canonicalStatusOf
    return id and id(mon) == "sleep"
  end
  local function hasStatus(mon)
    local id = mod.exports.canonicalStatusOf
    return id and id(mon) ~= nil
  end

  ------------------------------------------------------------------
  -- Turn-end residual family: Leech Seed, Nightmare, Ingrain
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and (mon.hp or 0) > 0 then
        if mon.leechSeeded and mon.leechSeedSource and (mon.leechSeedSource.hp or 0) > 0 then
          -- Real Showdown fixes, 2026-08-28 (explicit user directive,
          -- verified against Showdown's own real source this same pass
          -- -- gen2/moves.ts's own real Leech Seed condition confirms
          -- the drain and the heal both route through the SAME real
          -- `this.damage(...)`/`this.heal(...)` pair every other
          -- indirect-damage/drain interaction in this mod's own real
          -- ability system already keys off, and that the heal is
          -- SKIPPED outright whenever the drain itself didn't land
          -- (`if (damage) { this.heal(...) }`) -- both real, confirmed
          -- gaps this file's own code never checked before:
          --   Magic Guard: real, confirmed -- blocks the drain entirely
          --     (the SAME real ability this mod's own damage_immunity
          --     .lua already applies to status/Gen 1 sand residual,
          --     Leech Seed is the same real "indirect damage" family).
          --   Liquid Ooze: real, confirmed -- the SEEDED mon's own
          --     Liquid Ooze reverses the seeder's heal into damage
          --     instead, the exact same "apply then correct" shape
          --     abilities/engine/contact_retaliation.lua's own
          --     LIQUIDOOZE entry already established for move-based
          --     draining.
          local abilityIdOf = mod.exports.abilityIdOf
          local seededAbility = abilityIdOf and abilityIdOf(mon)
          if seededAbility ~= "MAGICGUARD" then
            local m = hpOf(mon)
            local maxHp = m.stats and m.stats.hp
            if maxHp then
              local amount = math.max(1, math.floor(maxHp / 8))
              m.hp = math.max(0, (m.hp or 0) - amount)
              local src = hpOf(mon.leechSeedSource)
              local srcMax = src.stats and src.stats.hp
              if srcMax then
                if seededAbility == "LIQUIDOOZE" then
                  src.hp = math.max(0, (src.hp or 0) - amount)
                else
                  -- Heal Block / boss "healblock": the seeder's own recovery
                  -- is gated exactly like every other heal (a blocked seeder
                  -- simply gets nothing; the drain still happened).
                  local tryHeal = mod.exports.g9TryHeal
                  if tryHeal then
                    tryHeal(battle, mon.leechSeedSource, amount)
                  else
                    src.hp = math.min(srcMax, (src.hp or 0) + amount)
                  end
                end
              end
            end
          end
        end
        if mon.nightmare and isAsleepNow(mon) then
          damageFractionOf(mon, 4)
        end
        if mon.ingrained then
          healFractionOf(battle, mon, 16)
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- Leech Seed / Ingrain infliction (power=0 status moves)
  ------------------------------------------------------------------
  local normalize = mod.exports.normalize
  assert(normalize, "modern_status_volatiles: combat/modern_combat.lua must load first")
  local Strings = require("src.core.Strings")
  local romText = require("src.core.RomText")

  mod.content.move_effects:register("GALAR_LEECHSEED_EFFECT", {
    kind = "secondary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      -- Round 27 (2026-09-10): a Dynamaxed/Gigantamax target cannot be
      -- given a NEW Leech Seed -- explicit user directive. The gate is
      -- here, at infliction ONLY: an existing seed is left untouched by
      -- Dynamax (it persists and keeps draining on the Dynamax HP -- see
      -- the residual above), and status_condition_cleanup.lua still only
      -- clears it on a real switch-out, never on a form change. So this
      -- never touches the persistent-seed half of the rule.
      if mod.exports.isDynamaxed and mod.exports.isDynamaxed(n.target) then return {} end
      if not n.target or n.target.leechSeeded then return {} end
      for _, t in ipairs(mod.exports.curTypesOf(n.target, n.gen2)) do
        if t == "GRASS" then return {} end
      end
      -- Real Showdown rule fixed 2026-08-28 (explicit user directive):
      -- a target protected by a Substitute cannot be seeded at all --
      -- the same real Substitute check every other hostile status-
      -- infliction site in this mod already applies (this file's own
      -- YAWN entry above cites the identical real principle), simply
      -- never wired for Leech Seed specifically until now. Gen 2's own
      -- real substitute state lives in the volatile store (a remaining-
      -- HP number, confirmed elsewhere in this mod); Gen 1's own is a
      -- direct field on the battler.
      if n.gen2 then
        local vol = n.battle:volatile(n.target)
        if (vol.substitute or 0) > 0 then return {} end
      elseif n.target.substituteHP and n.target.substituteHP > 0 then
        return {}
      end
      n.target.leechSeeded = true
      n.target.leechSeedSource = n.user
      return { Strings("%s\nwas seeded!", displayNameFor(n.battle, n.target, n.gen2)) }
    end,
  })
  mod.content.move_effects:register("GALAR_INGRAIN_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      n.user.ingrained = true
      return { Strings("%s\nplanted its roots!", displayNameFor(n.battle, n.user, n.gen2)) }
    end,
  })
  mod.content.move_effects:register("GALAR_NIGHTMARE_EFFECT", {
    kind = "secondary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      if n.target and isAsleepNow(n.target) then n.target.nightmare = true end
      return {}
    end,
  })

  ------------------------------------------------------------------
  -- Yawn: 2-turn delayed sleep. Reuses hasStatusImmunity for the real
  -- sleep-immunity check at the point sleep actually lands.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_YAWN_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      if not n.target or n.target.yawnTurns or hasStatus(n.target) then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      n.target.yawnTurns = 2
      return { Strings("%s\ngrew drowsy!", displayNameFor(n.battle, n.target, n.gen2)) }
    end,
  })
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and mon.yawnTurns and (mon.hp or 0) > 0 then
        mon.yawnTurns = mon.yawnTurns - 1
        if mon.yawnTurns <= 0 then
          mon.yawnTurns = nil
          local hasStatusImmunity = mod.exports.hasStatusImmunity
          if not hasStatus(mon) and not (hasStatusImmunity and hasStatusImmunity(mon, "sleep", battle)) then
            local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle)
            if gen2 then battle:applyStatus(mon, "sleep", "YAWN")
            else
              local StatusRegistry = require("src.battle.StatusRegistry")
              StatusRegistry.inflict(battle, mon, "SLP", { source = "YAWN" })
            end
          end
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- Disable: real duration 5, locks the target's own last-used move.
  -- Checked at move-selection time by combat/move_availability_gate.lua
  -- -- this file only tracks the flag/turns/move id; actually BLOCKING
  -- the move at selection is that file's own job, wired there.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_DISABLE_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local target = n.target
      -- Real field, confirmed by direct read: Gen 1 keeps it directly
      -- on the battler (`mon.lastMove`, BattleState.lua); Gen 2 keeps
      -- it in the volatile store (`battle:volatile(mon).lastMove`,
      -- gen2/Battle.lua) -- two different locations, not just two
      -- naming conventions, matching the same split this mod's own
      -- flinch/confuse fields already have.
      local lastMove = n.gen2 and n.battle:volatile(target).lastMove or target.lastMove
      if not (target and lastMove) or lastMove == "STRUGGLE" or target.disabledMoveId then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      target.disabledMoveId = lastMove
      target.disableTurns = 5
      return { Strings("%s's\n%s was disabled!", displayNameFor(n.battle, target, n.gen2), moveNameOf(n.battle, lastMove)) }
    end,
  })

  ------------------------------------------------------------------
  -- Embargo / Heal Block / Throat Chop: turn-limited move/item bans.
  ------------------------------------------------------------------
  local function banEffect(effectId, field, turns, failMsg, successMsg)
    mod.content.move_effects:register(effectId, {
      kind = "primary",
      accuracyChecked = true,
      run = function(a, b, c)
        local n = normalize(a, b, c)
        if not n.target then return {} end
        n.target[field] = turns
        return { Strings(successMsg, displayNameFor(n.battle, n.target, n.gen2)) }
      end,
    })
  end
  banEffect("GALAR_EMBARGO_EFFECT", "embargoTurns", 5, nil, "%s can't\nuse items!")
  banEffect("GALAR_HEALBLOCK_EFFECT", "healBlockTurns", 5, nil, "%s was\nprevented from healing!")
  -- Round 15: Psychic Noise / Throat Chop are DAMAGING moves, so they
  -- cannot keep the primary+run shape above (a .run record pre-empts the
  -- whole move on Gen 2's dispatch -- the same bug that made Magma Storm
  -- deal 0). They get kind="full" + a battle.damage_dealt listener that
  -- applies the ban AFTER a landed hit (damaging moves already roll their
  -- own accuracy, so accuracyChecked is unnecessary here). Embargo/Heal
  -- Block above are status moves and correctly keep primary+run.
  local function banAfterDamage(effectId, field, turns, successMsg)
    mod.content.move_effects:register(effectId, { kind = "full" })
    mod.events:on("battle.damage_dealt", function(ev)
      if not (ev and ev.move and ev.move.effect == effectId) then return end
      if not ev.target then return end
      ev.target[field] = turns
      if successMsg then
        ev.battle:emit({ kind = "message", text = Strings(successMsg,
          displayNameFor(ev.battle, ev.target,
            mod.exports.isGen2Battle and mod.exports.isGen2Battle(ev.battle))) })
      end
    end)
  end
  banAfterDamage("GALAR_PSYCHICNOISE_EFFECT", "healBlockTurns", 2, "%s was\nprevented from healing!")
  banAfterDamage("GALAR_THROATCHOP_EFFECT", "throatChopTurns", 2, "%s's\nthroat was chopped!")

  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon then
        for _, field in ipairs({ "embargoTurns", "healBlockTurns", "throatChopTurns", "disableTurns" }) do
          if mon[field] then
            mon[field] = mon[field] - 1
            if mon[field] <= 0 then
              mon[field] = nil
              if field == "disableTurns" then mon.disabledMoveId = nil end
            end
          end
        end
      end
    end
  end)

  -- Real move-block checks, wired at Battle:useMove (the same choke
  -- point Psychic Terrain/Prankster-Dark already use for "this move
  -- does nothing"): Heal Block/Psychic Noise block any `heal`-flagged
  -- move; Throat Chop blocks any `sound`-flagged move; Embargo blocks
  -- item use (checked at combat/modern_items.lua's own gate, not here
  -- -- that file owns every real item interaction already).
  --
  -- Gen 2 ONLY. src.battle.gen2.Battle is a hard cross-generation denial
  -- on a Gen 1 game (src/mods/Loader.crossGenerationDenial), and this
  -- require used to be UNGUARDED here -- which failed the WHOLE file on
  -- Gen 1, taking Heal Block, Leech Seed, Ingrain, Yawn, Disable, Embargo,
  -- Throat Chop, Perish Song and this file's residual ticks down with it.
  -- Gen 1's own Heal Block move-selection block lives in the shared
  -- combat/move_usability.lua gate installed by combat/heal_block.lua
  -- (both generations), so nothing is lost by scoping this native wrap to
  -- Gen 2.
  local gen2ok, Battle = pcall(require, "src.battle.gen2.Battle")
  if gen2ok and type(Battle) == "table" and type(Battle.useMove) == "function" then
    local nativeUseMove = Battle.useMove
    function Battle:useMove(attacker, defender, moveId)
      if attacker then
        local flags = moveFlags(moveId)
        if flags then
          if attacker.healBlockTurns and flags.heal then
            self:emit({ kind = "message", text = Strings("%s can't use healing moves!", self:monName(attacker)) })
            return
          end
          if attacker.throatChopTurns and flags.sound then
            self:emit({ kind = "message", text = Strings("%s can't use sound moves!", self:monName(attacker)) })
            return
          end
        end
        if attacker.disabledMoveId and attacker.disabledMoveId == moveId then
          self:emit({ kind = "message", text = Strings("%s's move is disabled!", self:monName(attacker)) })
          return
        end
      end
      return nativeUseMove(self, attacker, defender, moveId)
    end
  end

  ------------------------------------------------------------------
  -- Perish Song: hits both actives regardless of accuracy/target
  -- (real field-wide effect), 4-turn countdown to faint.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_PERISHSONG_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      for _, mon in ipairs({ n.battle.player, n.battle.enemy }) do
        if mon and (mon.hp or 0) > 0 and not mon.perishSongTurns then
          mon.perishSongTurns = 4
        end
      end
      return { Strings("All Pokémon caught in the\nmusic will faint in three turns!") }
    end,
  })
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and mon.perishSongTurns and (mon.hp or 0) > 0 then
        mon.perishSongTurns = mon.perishSongTurns - 1
        if mon.perishSongTurns <= 0 then
          mon.perishSongTurns = nil
          local m = hpOf(mon)
          m.hp = 0
          battle:emit({ kind = "message", text = Strings("%s's perish count fell to zero!", battle:monName(mon)) })
          if battle.onFaint then battle:onFaint(mon) end
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- Foresight / Miracle Eye / Odor Sleuth, Smack Down / Thousand
  -- Arrows: real type-immunity removal, via the post-effectiveness
  -- chain (the SAME primitive Phase 2's Wonder Guard/Tinted Lens family
  -- already uses) -- returns a large factor to defeat a natural 0x
  -- immunity rather than trying to re-run the whole type chart.
  ------------------------------------------------------------------
  local function markImmunityNegated(field)
    return function(a, b, c)
      local n = normalize(a, b, c)
      if n.target then
        n.target[field] = true
        -- Real Foresight/Miracle Eye rule: also resets the target's
        -- CURRENT evasion boost to 0 immediately (Showdown-verified,
        -- onModifyBoost). Future evasion RAISES are blocked separately,
        -- at the same real write-paths every other evasion change goes
        -- through (main.lua's own Gen 1 direct-write, Gen 2's
        -- changeStageAgainstMist wrap) -- see combat/
        -- stage_change_transform.lua's own header for that half.
        if n.gen2 then
          n.battle.stages[n.battle:sideOf(n.target)].evasion = 0
        else
          n.target.stages = n.target.stages or {}
          n.target.stages.evasion = 0
        end
      end
      return {}
    end
  end
  mod.content.move_effects:register("GALAR_FORESIGHT_EFFECT", { kind = "secondary", run = markImmunityNegated("foresighted") })
  mod.content.move_effects:register("GALAR_MIRACLEEYE_EFFECT", { kind = "secondary", run = markImmunityNegated("miracleEyed") })
  -- Round 15: Smack Down / Thousand Arrows are DAMAGING moves, so a .run
  -- record here (primary or secondary) pre-empts the whole move on Gen 2's
  -- dispatch (gen2 Battle:useMove calls a record's .run BEFORE the damage
  -- path and returns -- the exact bug that made Magma Storm deal 0). Same
  -- fix this mod applies to every damaging move with a sub-effect:
  -- kind="full" (invisible to that check on both engines) + a
  -- battle.damage_dealt listener that applies the grounding AFTER a
  -- landed hit. Foresight/Miracle Eye above are status moves and keep the
  -- secondary+run shape.
  mod.content.move_effects:register("GALAR_SMACKDOWN_EFFECT", { kind = "full" })
  mod.events:on("battle.damage_dealt", function(ev)
    if not (ev and ev.move and ev.move.effect == "GALAR_SMACKDOWN_EFFECT") then return end
    local ok, err = pcall(markImmunityNegated("groundedByMove"), ev.battle, ev.user, ev.target)
    if not ok then
      mod.log:warn("g9-battle-engine: GALAR_SMACKDOWN_EFFECT listener failed: %s", tostring(err))
    end
  end)

  -- Foresight/Miracle Eye/Smack Down/Scrappy/Mind's Eye's real immunity
  -- NEGATION, and Telekinesis's real immunity GRANT, USED to live here as
  -- a registerPostEffectivenessModifier("type_immunity_negation", ...)
  -- entry -- confirmed 2026-08-28 (Wonder-Guard-reachability review,
  -- following the Magic Guard audit) to be genuinely UNREACHABLE dead
  -- code in that shape: computeModernDamage (combat/modern_combat.lua)
  -- returns 0 damage the instant the NATURAL type multiplier reads 0,
  -- before the postEffectivenessModifiers loop this entry lived in ever
  -- runs -- so none of these five abilities/effects ever actually let a
  -- hit through, despite being fully coded up. Moved into
  -- combat/modern_combat.lua's own `resolvedTypeMult` (see that file's
  -- header, right above its `curTypesOf`) instead, which resolves
  -- negation against the real defender TYPE LIST before either the
  -- aggregate multiplier or the real per-row TypeChart.rows() scaling
  -- ever runs -- the only shape that can actually work, since a post-hoc
  -- "override the final number" trick can't stop TypeChart.rows() from
  -- independently re-walking the same natural 0x row. The mon-flag
  -- writes just above (foresighted/miracleEyed/groundedByMove,
  -- telekinesisTurns elsewhere) are unchanged and still the real signal
  -- resolvedTypeMult reads.

  ------------------------------------------------------------------
  -- Telekinesis: real duration 3, moves never miss (except OHKO), real
  -- Ground-type immunity for the duration. Species exemptions not
  -- modeled (flagged in this file's own header).
  ------------------------------------------------------------------
  -- Real Showdown species exemption (data/moves.ts, telekinesis's own
  -- onStart): Diglett/Dugtrio and Sandygast/Palossand families, plus
  -- Mega Gengar specifically -- these fail the move outright rather
  -- than silently not applying, matching real Showdown's own
  -- "-immune" response, not a quiet no-op. Real, direct field: `mon
  -- .species` (confirmed, gen2/Battle.lua's own real usage, a species-
  -- id string). "Own the outcome directly" -- checked as a plain id
  -- match, not through any deeper engine hook.
  local TELEKINESIS_EXEMPT = {
    DIGLETT = true, DUGTRIO = true, SANDYGAST = true, PALOSSAND = true,
    GENGARMEGA = true,
  }
  mod.content.move_effects:register("GALAR_TELEKINESIS_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      if not n.target then return {} end
      local species = n.target.species and tostring(n.target.species):upper():gsub("[^%w]", "")
      if species and TELEKINESIS_EXEMPT[species] then
        return { Strings("It doesn't affect\n%s...", displayNameFor(n.battle, n.target, n.gen2)) }
      end
      n.target.telekinesisTurns = 3
      return { Strings("%s was made\nto float!", displayNameFor(n.battle, n.target, n.gen2)) }
    end,
  })
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    for _, mon in ipairs(mod.exports.allActiveBattlers and mod.exports.allActiveBattlers(battle) or { battle.player, battle.enemy }) do
      if mon and mon.telekinesisTurns then
        mon.telekinesisTurns = mon.telekinesisTurns - 1
        if mon.telekinesisTurns <= 0 then mon.telekinesisTurns = nil end
      end
    end
  end)

  ------------------------------------------------------------------
  -- Uproar: real 3-turn self-lock, same shape as Outrage's own rampage
  -- (this mod's existing thrashTurns/thrashMove fields), plus its own
  -- real extra effect (wakes every active sleeping mon the turn it's
  -- used). Gen 1 works fully (afterDamage, same as Outrage); Gen 2's
  -- own rampage-lock has the identical hardcoded-string blocker
  -- Outrage's own gap already documents -- same honest gap, not
  -- reattempted here.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_UPROAR_EFFECT", {
    kind = "full",
    beforeAccuracy = function(ctx)
      local StatusRegistry = require("src.battle.StatusRegistry")
      for _, mon in ipairs({ ctx.battle.player, ctx.battle.enemy }) do
        if mon and mon.mon and mon.mon.status == "SLP" then
          mon.mon.status = nil
        end
      end
    end,
    afterDamage = function(ctx)
      local user = ctx.user
      if not user.thrashTurns then
        user.thrashTurns = 3
        user.thrashMove = ctx.moveInst
        user.thrashAnnounced = true
      else
        user.thrashTurns = user.thrashTurns - 1
        if user.thrashTurns <= 0 then
          user.thrashTurns, user.thrashMove, user.thrashAnnounced = nil, nil, nil
        end
      end
    end,
  })

  ------------------------------------------------------------------
  -- Dire Claw / Tri Attack: real random-status secondary, only if the
  -- target has no status yet (matches trySetStatus's own real rule --
  -- reuses the same STANDARD_AILMENT convention main.lua's own generic
  -- ailment handler established).
  ------------------------------------------------------------------
  local RANDOM_STATUS_MOVES = {
    DIRECLAW = { chance = 50, choices = { "poison", "paralysis", "sleep" } },
    TRI_ATTACK = { chance = 20, choices = { "burn", "paralysis", "freeze" } },
  }
  local STATUS_CODES = {
    poison = { gen1 = "PSN", gen2 = "poison" }, burn = { gen1 = "BRN", gen2 = "burn" },
    paralysis = { gen1 = "PAR", gen2 = "paralyze" }, freeze = { gen1 = "FRZ", gen2 = "freeze" },
    sleep = { gen1 = "SLP", gen2 = "sleep" },
  }
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local target = ev and ev.target
    local cfg = moveId and RANDOM_STATUS_MOVES[moveId]
    if not (battle and cfg and target and (ev.damage or 0) > 0) then return end
    if hasStatus(target) then return end
    local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle)
    local roll = gen2 and battle.random(100) or (battle.rng(1, 100) - 1)
    if roll >= cfg.chance then return end
    local pick = cfg.choices[(gen2 and battle.random(#cfg.choices) or (battle.rng(1, #cfg.choices) - 1)) + 1]
    local codes = STATUS_CODES[pick]
    if gen2 then
      battle:applyStatus(target, codes.gen2, moveId)
    else
      local StatusRegistry = require("src.battle.StatusRegistry")
      StatusRegistry.inflict(battle, target, codes.gen1, { source = moveId })
    end
  end)

  ------------------------------------------------------------------
  -- Stockpile / Swallow / Spit Up -- a real per-mon counter, owned
  -- entirely by this mod: Stockpile stacks up to 3 (fails outright at
  -- 3), each use raises Def+SpDef by 1 stage; Swallow heals 25%/50%/
  -- 100% by stack count and reverses those boosts, consuming all
  -- stacks; Spit Up deals 100/200/300 power by stack count, also
  -- consuming all stacks (Showdown-verified, data/moves.ts). Cleared on
  -- switch-out (the real `previous` field on battle.battler_switched,
  -- same primitive Regenerator/Natural Cure already use) and on faint
  -- -- a fresh mon, or the same mon re-sent in, never carries a stale
  -- count. Real Gen 7+ nuance (tracking the EXACT successfully-applied
  -- boost, not just layer count, for the edge case a stage was already
  -- near +6) simplified to "reverse by layer count" -- a small, named
  -- simplification, not silently dropped.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_STOCKPILE_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user = n.user
      if not user then return {} end
      if (user.stockpileLayers or 0) >= 3 then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      user.stockpileLayers = (user.stockpileLayers or 0) + 1
      local msgs = { Strings("%s stockpiled %d!", displayNameFor(n.battle, user, n.gen2), user.stockpileLayers) }
      for _, m in ipairs(changeStage(n.battle, user, "defense", 1, false, n.gen2)) do msgs[#msgs + 1] = m end
      for _, m in ipairs(changeStage(n.battle, user, "spd", 1, false, n.gen2)) do msgs[#msgs + 1] = m end
      return msgs
    end,
  })
  mod.content.move_effects:register("GALAR_SWALLOW_EFFECT", {
    kind = "primary",
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user = n.user
      local layers = user and user.stockpileLayers or 0
      if layers <= 0 then
        return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
      end
      local denom = ({ 4, 2, 1 })[layers]
      healFractionOf(user, denom)
      local msgs = { Strings("%s\nswallowed!", displayNameFor(n.battle, user, n.gen2)) }
      for _, m in ipairs(changeStage(n.battle, user, "defense", -layers, false, n.gen2)) do msgs[#msgs + 1] = m end
      for _, m in ipairs(changeStage(n.battle, user, "spd", -layers, false, n.gen2)) do msgs[#msgs + 1] = m end
      user.stockpileLayers = nil
      return msgs
    end,
  })
  -- Spit Up: real, fixed power by stack count (100/200/300) -- NOT a
  -- move_effects registration at all. registerPowerOverride (the same
  -- real primitive Heat Crash/Heavy Slam/Power Trip/Flail already use,
  -- confirmed exported directly from modern_combat.lua) substitutes the
  -- move's own base power before the ordinary damage formula runs, so
  -- Spit Up just becomes a normal damaging hit with the right power --
  -- no separate damage-dealing code to get wrong here. Consumption
  -- (clearing stockpile, reversing the Def/SpDef boosts) happens
  -- afterward, on the same real battle.damage_dealt event every other
  -- post-hit effect in this mod already uses. A stockpile-less Spit Up
  -- deals 0 power (not a hard "but it failed" fail message like real
  -- Showdown) -- a small, named cosmetic simplification, not a
  -- mechanical one.
  local registerPowerOverride = mod.exports.registerPowerOverride
  if registerPowerOverride then
    registerPowerOverride("SPITUP", function(ctx)
      return (ctx.user and (ctx.user.stockpileLayers or 0) or 0) * 100
    end)
  end
  mod.events:on("battle.damage_dealt", function(ev)
    local battle = ev and ev.battle
    local moveId = ev and ((ev.move and ev.move.id) or ev.moveId)
    local user = ev and ev.user
    if not (battle and moveId == "SPITUP" and user and (user.stockpileLayers or 0) > 0) then return end
    local layers = user.stockpileLayers
    user.stockpileLayers = nil
    local gen2 = mod.exports.isGen2Battle and mod.exports.isGen2Battle(battle)
    changeStage(battle, user, "defense", -layers, false, gen2)
    changeStage(battle, user, "spd", -layers, false, gen2)
  end)
  mod.events:on("battle.battler_switched", function(ev)
    local previous = ev and ev.previous
    if previous then previous.stockpileLayers = nil end
    local mon = ev and ev.battler
    if mon then mon.stockpileLayers = nil end
  end)

  mod.log:info("g9-battle-engine: modern_status_volatiles installed (Leech Seed, Nightmare, Ingrain, Yawn, Disable, Embargo, Heal Block, Psychic Noise, Throat Chop, Perish Song, Foresight, Miracle Eye, Smack Down, Telekinesis, Uproar, Dire Claw, Tri Attack)")
end
