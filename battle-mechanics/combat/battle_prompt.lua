-- Two-choice in-battle prompt -- a PRIMITIVE any mod can raise, deliberately
-- not a policy. The caller supplies the question, the two labels and a
-- callback; nothing in this file knows or cares WHICH species, HP threshold,
-- trainer class or story flag made the question worth asking. Baking one
-- mod's trigger rule in here would impose that rule on every other consumer
-- of this mod, which is exactly the mistake the base engine already made and
-- that this file exists to work around (see the next paragraph). The
-- motivating case -- a boss at 1 HP offering "CATCH it" / "LEAVE it", both
-- answers ending the battle -- is implementable entirely as a caller: a
-- battle.damage/battle.fainted listener that checks its own condition and
-- calls askBattleChoice with its own two labels and its own callback. That
-- caller is NOT in this file, on purpose.
--
-- Why this has to be a mod-side reimplementation rather than "just set a
-- phase". Confirmed by direct engine source read before writing this, not
-- assumed: Gen 2's yes/no box is drawn only for a hardcoded list of five
-- phase names (src/ui/gen2/BattleState.lua:3822-3824, `local asking =
-- self.phase == "ask-nickname" or ... or self.phase == "ask-next-mon"`),
-- and each of those five phases has its own hand-rolled input branch in
-- :update (:2320 ask-nickname, :2356 ask-shift, :2377 ask-next-mon, :2470
-- ask-forget/stop-learning) hard-wired to its own answer handler
-- (:answerNickname, :openShiftParty, :answerUseNextMon,
-- :answerForgetPrompt). There is no phase-agnostic "ask a question" path,
-- and there is no input hook on the battle screen at all -- the engine's
-- nine battle.* hook names are accuracy, crit, damage, ended, fainted,
-- overlay, run, started, style (grepped the whole engine src/ tree), of
-- which exactly one (overlay) touches the battle screen and it is
-- draw-only.
--
-- Worse, a phase name the engine does not know is not merely undrawn: it is
-- unhandled. :update (src/ui/gen2/BattleState.lua:2113-2528) is a flat chain
-- of `if self.phase == "..." then ... return end` blocks with NO trailing
-- else -- an unrecognised phase falls off the end of the function every
-- frame, reading no input and advancing no queue, i.e. a hard softlock with
-- the message box still on screen. Everything below is built around that one
-- fact: this file's own phase name must never be visible to native :update,
-- and if one ever is (a save/load across a version change, a mod poking
-- .phase directly, this file's own bug) it must be recovered from rather
-- than sat in. See the watchdog in the update wrap.
--
-- REJECTED, and why:
--   * Patching the engine's `asking` list / adding an engine-side prompt
--     API. Correct long-term fix, wrong repo -- this is a mod and cannot
--     ship base-engine changes. Worth raising upstream separately; the
--     shape below is a reasonable sketch of what that API would look like.
--   * Reusing one of the engine's five existing ask-* phases. They are not
--     inert containers: answering "ask-shift" runs :openShiftParty, and
--     "ask-nickname" runs :answerNickname on the mon in .nicknameMon. A
--     borrowed phase means the engine's own handler fires on our answer.
--   * Driving the whole thing from battle.overlay. Overlay is draw-only and
--     fires inside :drawScene (:3876-3886), after the scene composites --
--     right for the BOX, useless for the ANSWER. Input has to be a class
--     wrap on :update, the same conclusion combat/move_availability_gate.lua
--     reached for the same reason (its own header, :15-24).
--   * A separate pushed screen (Screens.push, the way :openParty and
--     :openShiftParty open the party list). A real screen would need
--     registering in the engine's own screen table, and it suspends the
--     battle state's draw entirely. The cart's own yes/no box is five tiles
--     tall and sits OVER the battle (PlaceYesNoBox, home/menu.asm:392-410);
--     covering the whole field to ask one question is a bigger behaviour
--     change than the feature.
--   * Living inside combat/boss_fight.lua. Checked, and it does not belong
--     there: that file is a pure flag-set policy layer (setBossFightProtections
--     / bossFightHas) with no UI, no engine-class wrap and no per-frame code
--     at all, and its flags are boss-specific by definition. This primitive
--     is neither boss-specific nor policy. The boss capture case is a
--     CONSUMER of this file, not a reason to merge the two.
--
-- Gen 1 (src/battle/BattleState.lua) is deliberately NOT covered here. It has
-- no yes/no infrastructure whatsoever -- no PlaceYesNoBox equivalent, no
-- two-choice box in its drawTextArea, no ask-* phase of any kind (grepped:
-- its phases are menu/moveSelect/messages/... with no prompt among them), so
-- Gen 2's "reuse the box the engine already draws for five other questions"
-- shortcut has no counterpart there: it would mean drawing a box, a cursor
-- and two rows from scratch against a different font/chrome stack. This
-- mod's manifest is `"games": ["gen2"]` and the target is Crystal, so a
-- half-built Gen 1 arm would be untested surface, not coverage. It is a
-- follow-up, not a silent omission -- askBattleChoice returns false with a
-- reason on a Gen 1 boot rather than pretending.
return function(mod)
  local GameVersion = require("src.core.GameVersion")
  local isGen2Boot = GameVersion.generation(GameVersion.get()) == 2

  -- pcall-require + warn-only-on-a-gen-2-boot: a Gen 1 boot legitimately has
  -- neither of these and must not log a scary line about it.
  local chromeOk, Chrome = pcall(require, "src.ui.gen2.Chrome")
  Chrome = chromeOk and Chrome or nil
  if not chromeOk and isGen2Boot then
    mod.log:warn("g9-battle-engine: battle_prompt: src.ui.gen2.Chrome not available on a gen 2 boot: %s",
      tostring(Chrome))
  end

  local gen2Ok, Gen2BattleState = pcall(require, "src.ui.gen2.BattleState")
  Gen2BattleState = (gen2Ok and type(Gen2BattleState) == "table") and Gen2BattleState or nil
  if not Gen2BattleState and isGen2Boot then
    mod.log:warn("g9-battle-engine: battle_prompt: src.ui.gen2.BattleState not available on a gen 2 boot: %s",
      tostring(Gen2BattleState))
  end

  -- Namespaced with the mod id so it can never collide with an engine phase,
  -- including one the engine adds later. Nothing outside this file should
  -- ever compare against it -- battleChoiceActive is the supported query.
  local PROMPT_PHASE = "g9-battle-prompt"

  -- PlaceYesNoBox geometry, lifted straight off the engine's own draw
  -- (src/ui/gen2/BattleState.lua:3826-3838): a 5-row box whose top border is
  -- row 7, first label row 8, second label row 10, cursor one tile left of
  -- the label. Only the WIDTH is computed rather than fixed at 6 -- see
  -- boxWidth.
  local BOX_TOP, BOX_ROWS = 7, 5
  local FIRST_ROW, SECOND_ROW = 8, 10
  local LABEL_INSET, CURSOR_INSET = 2, 1
  -- SCREEN_WIDTH in tiles; the engine's own `lb bc, SCREEN_WIDTH - 6, 7`
  -- right-aligns the 6-wide box at column 14, which is 20 - 6.
  local SCREEN_TILES = 20
  -- Widest label that still leaves room for border + cursor + border.
  local MAX_LABEL = SCREEN_TILES - LABEL_INSET - 1

  -- src/ui/gen2/BattleState.lua:62. The engine never counts this down --
  -- grepped every read of .messageTimer, all of them are `> 0` / `<= 0`
  -- tests and the only writes are this constant and 0 -- so it is really a
  -- "line is held for an A/B press" flag and the literal value is
  -- cosmetic. Matched anyway so a reader diffing against the engine sees
  -- the same number.
  local MESSAGE_FRAMES = 48

  -- The only two phases a prompt may interrupt. Both are quiescent by
  -- definition: "menu" is the engine parked on the action menu waiting for
  -- the player (:2256), "resolving" is the queue pump between events
  -- (:2187) and is where it lands the frame it has nothing left to say.
  -- Everything else is either mid-question (the five ask-* phases, whose
  -- own state we would strand), mid-list (submenu/forced-switch/
  -- choose-forget, where a pushed Gen2PartyMenu owns the screen), or
  -- terminal (done/evolving, where :finishBattle has already run
  -- :clearAllVolatiles). "intro" is excluded for a second reason: the
  -- 72-frame BattleIntroSlidingPics loop (:2124) reads no input and owns
  -- the screen regardless of phase, and excluding "intro" is exactly
  -- equivalent to testing .slideFrame without needing BattleAnimView here.
  local INTERRUPTIBLE = { menu = true, resolving = true }

  -- The live Gen 2 battle screen, so a caller holding only a Battle (which
  -- is what every battle.* event payload gives it -- battle.damage and
  -- battle.fainted carry the model, never the screen) can still raise a
  -- prompt. Written by the update wrap rather than by a battle.started
  -- listener because the screen object is what :update has and what a
  -- listener does not.
  --
  -- Parked on the engine class table, NOT in a file-local upvalue, and that
  -- is load-bearing rather than stylistic. The :update wrap below installs
  -- once and is then guarded by a sentinel (the same __-flag idiom
  -- move_availability_gate.lua:36 uses), so a mod reload re-runs this file
  -- WITHOUT re-wrapping: the still-installed wrap goes on writing the first
  -- run's upvalues while the freshly-registered mod.exports closures read
  -- the second run's. An upvalue here would therefore be written by the
  -- wrap and read as permanently nil by askBattleChoice, and every
  -- resolve-by-Battle and resolve-by-nil call would fail with "no live gen
  -- 2 battle screen" after the first reload. The class table is the one
  -- object both runs demonstrably share.
  local function setLiveScreen(screen)
    if Gen2BattleState then Gen2BattleState.__g9LiveScreen = screen end
  end
  local function getLiveScreen()
    return Gen2BattleState and Gen2BattleState.__g9LiveScreen or nil
  end

  -- Everything :update's own guards check before it will let a phase branch
  -- run (src/ui/gen2/BattleState.lua:2129-2231), read back as "the screen is
  -- busy with something that owns the frame". Promoting a pending prompt
  -- while any of these is set would freeze a running animation mid-way (the
  -- wrap below returns instead of calling native, so .anim would simply stop
  -- stepping) or clobber a line the player has not read yet.
  local function screenBusy(screen)
    return screen.anim ~= nil or screen.hpAnim ~= nil or screen.expAnim ~= nil
      or screen.faintSlide ~= nil or screen.winSliding ~= nil
      or screen.trainerSlide ~= nil or screen.waitSfx ~= nil
      or screen.messagePages ~= nil
      or (screen.messageDelay or 0) > 0 or (screen.messageTimer or 0) > 0
  end

  local function isScreen(value)
    return Gen2BattleState ~= nil and type(value) == "table"
      and getmetatable(value) == Gen2BattleState
  end

  -- target may be: the Gen 2 battle screen itself (what battle.overlay hands
  -- a mod), a Battle model (what every other battle.* payload hands it), or
  -- nil for "whichever battle is on screen". A Battle only resolves while it
  -- is the one actually being played -- resolving a backgrounded or finished
  -- battle to the live screen would put the prompt on the wrong fight.
  local function resolveScreen(target)
    local live = getLiveScreen()
    if target == nil then return live end
    if isScreen(target) then return target end
    if live ~= nil and live.battle == target then return live end
    return nil
  end

  -- Character count, not pixel width: the engine budgets its own boxes the
  -- same way ("YES" is 3 characters in a 6-wide box at :3830-3832, i.e.
  -- width = label + border + cursor + border), and Font's proportional
  -- advances only ever make a string NARROWER than its tile budget, so this
  -- can over-reserve but never clip.
  local function boxWidth(labels)
    local widest = 0
    for _, label in ipairs(labels) do
      if #label > widest then widest = #label end
    end
    return math.max(6, math.min(SCREEN_TILES, widest + LABEL_INSET + 1))
  end

  -- Right-aligned, which reproduces the engine's default box exactly for
  -- two 3-character labels (20 - 6 = 14, its own hardcoded left) and slides
  -- a wider box leftwards off the same edge. The engine's second position
  -- (column 1, used by OfferSwitch, :3828-3829) is deliberately NOT offered
  -- as an option: it exists in the cart because that box is a fixed 6 tiles
  -- and long trainer text needed the right-hand side free, and auto-width
  -- already solves the only problem a caller would reach for it to solve.
  local function boxLeft(width)
    return math.max(0, SCREEN_TILES - width)
  end

  -- Puts back every field raise() wrote, so the two are exact inverses.
  -- Restoring .phase alone is not enough: raising from "menu" displaces the
  -- standing "What will X do?" line, and raising from anywhere displaces
  -- .messageTimer, which the engine reads as "this line is still held".
  -- .messagePages/.messagePage are in here for symmetry rather than because
  -- a paginated run can currently be interrupted -- screenBusy refuses to
  -- promote while .messagePages is set, so raise() always sees nil there
  -- today. Kept because raise() nevertheless writes both fields, and a
  -- restore that is not the exact inverse of the raise is the kind of thing
  -- that quietly stops being true when the promotion gate is next widened.
  local function restore(screen, ask)
    screen.phase = ask.savedPhase
    screen.message = ask.savedMessage
    screen.messageTimer = ask.savedMessageTimer
    screen.messagePages = ask.savedPages
    screen.messagePage = ask.savedPage
  end

  -- Restore FIRST, then call onAnswer -- ordering matters and this one was
  -- chosen deliberately over its inverse ("call, then restore only if the
  -- callback did not move .phase"). Restoring first means:
  --   * a callback that ends the battle (screen:finishBattle()), opens a
  --     list, or pushes events + advanceQueue simply writes over a valid
  --     phase, and needs no cooperation from this file;
  --   * a callback that does nothing at all leaves the battle exactly where
  --     the question interrupted it;
  --   * a callback that THROWS still cannot strand the battle, because the
  --     screen was already back in a phase native :update handles before the
  --     callback ever ran. The inverse ordering has no such guarantee: it
  --     has to inspect .phase after an error to decide what the callback
  --     half-did, which is unknowable.
  -- The pcall is the same "a broken mod degrades to not-installed rather
  -- than breaking the pipeline" contract the engine's own hook chain states
  -- (src/mods/Hooks.lua:34-42).
  local function answer(screen, index)
    local ask = screen.__g9Prompt
    if ask == nil then return end
    screen.__g9Prompt = nil
    restore(screen, ask)
    local ok, err = pcall(ask.onAnswer, index, screen, ask.request)
    if not ok then
      mod.log:warn("g9-battle-engine: battle_prompt: %s onAnswer(%d) errored: %s",
        tostring(ask.id), index, tostring(err))
    end
  end

  local function raise(screen, ask)
    ask.savedPhase = screen.phase
    ask.savedMessage = screen.message
    ask.savedMessageTimer = screen.messageTimer
    ask.savedPages = screen.messagePages
    ask.savedPage = screen.messagePage
    screen.__g9Prompt = ask
    screen.phase = PROMPT_PHASE
    screen.message = ask.text
    -- Held for one A/B press before the box opens, which is what all five
    -- engine prompts do (:askNickname sets MESSAGE_FRAMES at :3055,
    -- :showPages at :3065 for ask-shift/ask-forget/stop-learning) and what
    -- the draw path keys the box off (`asking and (self.messageTimer or 0)
    -- <= 0`, :3825). Not made optional: a question the player has not been
    -- given a frame to read is a worse default than one extra press, and
    -- matching native here means the prompt feels like the four the game
    -- already asks.
    screen.messageTimer = MESSAGE_FRAMES
    -- The prompt is always a single page -- it is one question, and a
    -- question the player has to page through before answering is a worse
    -- prompt. Written unconditionally rather than asserted: screenBusy
    -- already refuses to promote while .messagePages is set, so this is
    -- nil-to-nil today and stays correct if that gate is ever widened,
    -- because restore() puts back whatever was here (see its own note).
    screen.messagePages = nil
    screen.messagePage = 1
  end

  -- ------------------------------------------------------------------
  -- Input: a class wrap on :update, installed outermost (see main.lua).
  -- ------------------------------------------------------------------
  -- Same __-sentinel idempotency guard combat/move_availability_gate.lua:36
  -- and gigantamax/gimmick_dynamax.lua:749 use, for the same reason: mod
  -- reloads re-run this file against a class table that is a live engine
  -- singleton, and a second wrap would double every intercept.
  if Gen2BattleState and not Gen2BattleState.__g9BattlePromptWrapped then
    Gen2BattleState.__g9BattlePromptWrapped = true
    local nativeUpdate = Gen2BattleState.update

    function Gen2BattleState:update(dt)
      setLiveScreen(self)

      if self.phase == PROMPT_PHASE then
        local ask = self.__g9Prompt
        -- WATCHDOG. The phase is set but the record is not: the only ways
        -- here are a bug in this file, another mod writing .phase directly,
        -- or a screen rebuilt around a stale phase. Native :update has no
        -- branch for it and no trailing else (:2113-2528), so leaving it
        -- alone is a permanent softlock. Fall back to "resolving", which is
        -- the engine's own universal re-entry point -- every one of its
        -- answer handlers (:2366, :2370, :2522, :2998, :3033) uses exactly
        -- this pair to hand control back to the queue.
        if ask == nil then
          mod.log:warn("g9-battle-engine: battle_prompt: recovered a stranded prompt phase")
          self.phase = "resolving"
          self.messageTimer = 0
          self.messagePages = nil
          return nativeUpdate(self, dt)
        end

        local input = self.game and self.game.input
        -- No input device at all (a headless/driverless screen) can never
        -- answer, so answer it here rather than hold the battle forever.
        -- The engine takes the same view of the same situation one branch
        -- over -- :2437-2441's "No stack to open a list on (headless)"
        -- falls back instead of waiting -- and B's own answer is the
        -- honest choice to fall back to, since B is what a player who
        -- refuses to engage with the box presses.
        if not input then
          mod.log:warn("g9-battle-engine: battle_prompt: %s answered %d, no input device",
            tostring(ask.id), ask.cancel or ask.index)
          answer(self, ask.cancel or ask.index)
          return
        end

        -- The question's own line is held for A/B first, exactly as the
        -- five native ask-* branches do (:2323-2328, :2357-2362, ...).
        if (self.messageTimer or 0) > 0 then
          if input:wasPressed("a") or input:wasPressed("b") then
            self.messageTimer = 0
          end
          return
        end

        if input:wasPressed("up") or input:wasPressed("down") then
          -- Two rows, so up and down are the same toggle -- :2363-2364.
          ask.index = ask.index == 1 and 2 or 1
        elseif input:wasPressed("b") then
          -- YesNoMenuHeader carries no STATICMENU_DISABLE_B, so B answers
          -- rather than being swallowed (:2332, :2480). A caller that
          -- genuinely must not be escaped passes cancel = false, which is
          -- the STATICMENU_DISABLE_B case; B is then inert, matching the
          -- engine's own treatment of a disabled-B menu.
          if ask.cancel then return answer(self, ask.cancel) end
        elseif input:wasPressed("a") then
          return answer(self, ask.index)
        end
        -- No :playSfx here on purpose: the engine's ask-* branches are the
        -- only input branches in the whole file with no click sound (the
        -- "menu" and "moves" branches do call it, :2273 and :2309), because
        -- PlaceYesNoBox's own answer plays none.
        return
      end

      -- A prompt record with the phase already moved off ours means
      -- something outside this file took the screen over mid-question. The
      -- record is dropped rather than forced back: whatever moved the phase
      -- owns the screen now, and re-raising over it would be this file
      -- doing to another mod what the engine's hardcoded list did to us.
      if self.__g9Prompt ~= nil then
        mod.log:warn("g9-battle-engine: battle_prompt: %s dropped, phase moved to %s",
          tostring(self.__g9Prompt.id), tostring(self.phase))
        self.__g9Prompt = nil
      end

      local result = nativeUpdate(self, dt)

      -- Promotion runs AFTER native, never before: native is what settles
      -- .phase and the busy flags for this frame, so asking before it has
      -- run tests last frame's screen. The cost is a one-frame delay
      -- between askBattleChoice and the box appearing, which is invisible
      -- and is the price of never having to duplicate native's own
      -- ownership guards.
      local pending = self.__g9PromptPending
      if pending ~= nil then
        if self.phase == "done" or self.phase == "evolving" then
          -- The battle ended before the question could be asked. Dropped
          -- with a log rather than answered with an invented index: a
          -- caller cannot tell a real answer from a synthetic one, and
          -- "CATCH it" fired at a battle that is already over is worse
          -- than silence. battleChoiceActive is how a caller checks.
          self.__g9PromptPending = nil
          mod.log:warn("g9-battle-engine: battle_prompt: %s dropped, battle ended first",
            tostring(pending.id))
        elseif INTERRUPTIBLE[self.phase] and not screenBusy(self) then
          self.__g9PromptPending = nil
          raise(self, pending)
        end
      end

      -- A finished battle stops being resolvable by nil or by its Battle:
      -- :finishBattle has already run :clearAllVolatiles (:1954) and the
      -- overworld is about to take the screen back, so a prompt aimed at it
      -- would land on a corpse.
      if self.phase == "done" then setLiveScreen(nil) end
      return result
    end
  end

  -- ------------------------------------------------------------------
  -- Draw: battle.overlay (the per-frame overlay hook, fired inside the
  -- active transform and after the scene body).
  -- ------------------------------------------------------------------
  -- :drawScene fires battle.overlay unconditionally every frame (src/ui/
  -- gen2/BattleState.lua:3884-3885), already inside whichever transform is
  -- active, and it fires AFTER :drawSceneBody -- so the box lands on top of
  -- the message box native already drew, which is the layering the cart has
  -- (PlaceYesNoBox opens over the standing text). Nothing here draws the
  -- question text itself: native :drawPanel's own trailing else branch
  -- (:3816-3818) prints .message for any phase it does not recognise, so an
  -- unknown phase already gets a correctly wrapped two-row message box for
  -- free. Only the choice box is missing, and only that is added.
  mod.hooks:wrap("battle.overlay", function(next, ctx)
    next(ctx)
    if not (Chrome and ctx ~= nil and ctx.phase == PROMPT_PHASE) then return end
    local ask = ctx.__g9Prompt
    if ask == nil then return end
    -- The box only opens once the question's own line has been read, which
    -- is the `asking and (self.messageTimer or 0) <= 0` gate at :3825.
    if (ctx.messageTimer or 0) > 0 then return end
    -- A mod that hid the bottom UI through battle.bottom_ui_visible (:218)
    -- made native :drawPanel return before it drew the message box at all
    -- (:3745-3748); drawing a choice box over a deliberately bare field
    -- would be this mod overriding that one. The input side stays live, so
    -- the question is still answerable -- it just is not painted.
    if ctx.bottomUIVisible and not ctx:bottomUIVisible() then return end

    local ok, err = pcall(function()
      local width = boxWidth(ask.choices)
      local left = boxLeft(width)
      Chrome.box(left, BOX_TOP, width, BOX_ROWS)
      Chrome.printThrough(ask.choices[1], left + LABEL_INSET, FIRST_ROW,
        Chrome.DEFAULT_BOX_PALETTE)
      Chrome.printThrough(ask.choices[2], left + LABEL_INSET, SECOND_ROW,
        Chrome.DEFAULT_BOX_PALETTE)
      Chrome.cursorThrough(left + CURSOR_INSET,
        ask.index == 1 and FIRST_ROW or SECOND_ROW, Chrome.DEFAULT_BOX_PALETTE)
      -- Chrome.box and the print helpers all leave the draw colour black for
      -- the next string; :drawPanel resets to white at its own tail (:3844)
      -- and this draws after that, so it has to do the same or every later
      -- overlay link inherits black.
      love.graphics.setColor(1, 1, 1, 1)
    end)
    if not ok then
      mod.log:warn("g9-battle-engine: battle_prompt: box draw errored: %s", tostring(err))
    end
  end)

  -- ------------------------------------------------------------------
  -- Exports
  -- ------------------------------------------------------------------
  -- askBattleChoice(target, request) -> true | false, reason
  --
  --   target   the Gen 2 battle screen (battle.overlay's payload), a Battle
  --            (every other battle.* payload), or nil for the live battle.
  --   request  { text     = "WOOPER is down to its last!",   -- required
  --              choices  = { "CATCH it", "LEAVE it" },      -- required, 2
  --              onAnswer = function(index, screen, request) end, -- required
  --              default  = 1,      -- optional, row the cursor opens on
  --              cancel   = 2,      -- optional, index B answers with;
  --                                 -- false makes B inert (the cart's own
  --                                 -- STATICMENU_DISABLE_B case)
  --              id       = "..." } -- optional, appears in this file's logs
  --
  -- onAnswer gets the 1-based index of the chosen label and the screen, and
  -- is called with the battle already back in the phase the question
  -- interrupted -- so it may do nothing (the battle carries on), end the
  -- battle (screen:finishBattle()), or push events and pump the queue, and
  -- needs no cooperation from this file for any of them. It is called for a
  -- real answer only; a prompt the battle outlived is dropped with a log,
  -- never synthesised.
  --
  -- Returns false plus a reason string rather than throwing, because every
  -- refusal here is a condition a caller can legitimately hit at runtime (a
  -- Gen 1 boot, a battle that ended a frame earlier, a second prompt while
  -- one is up) and none of them is a programming error worth killing a
  -- battle over.
  mod.exports.askBattleChoice = function(target, request)
    if not Gen2BattleState then return false, "gen 2 battle screen unavailable" end
    if type(request) ~= "table" then return false, "request must be a table" end
    local choices = request.choices
    if type(choices) ~= "table" or #choices ~= 2
        or type(choices[1]) ~= "string" or type(choices[2]) ~= "string" then
      return false, "request.choices must be exactly two strings"
    end
    if type(request.onAnswer) ~= "function" then
      return false, "request.onAnswer must be a function"
    end
    if type(request.text) ~= "string" or request.text == "" then
      return false, "request.text must be a non-empty string"
    end
    local screen = resolveScreen(target)
    if screen == nil then return false, "no live gen 2 battle screen" end
    if screen.phase == "done" or screen.phase == "evolving" then
      return false, "battle is over"
    end
    -- One question at a time. Stacking would mean the second raise saving
    -- the first prompt's own phase as the context to restore to, which puts
    -- the screen back into PROMPT_PHASE with no record -- the exact
    -- stranded state the watchdog exists to clean up after.
    if screen.__g9Prompt ~= nil or screen.__g9PromptPending ~= nil then
      return false, "a prompt is already up"
    end

    local ask = {
      id = request.id or "unnamed",
      request = request,
      text = request.text,
      -- Copied, not aliased: the caller's table is theirs to mutate, and a
      -- label changing between raise and draw would resize the box under
      -- the cursor. Truncated to what the screen can hold rather than
      -- rejected, so a long label degrades to a clipped one instead of a
      -- silently missing prompt.
      choices = { choices[1]:sub(1, MAX_LABEL), choices[2]:sub(1, MAX_LABEL) },
      index = request.default == 2 and 2 or 1,
      onAnswer = request.onAnswer,
    }
    -- cancel = false disables B; anything else (including nil) defaults to
    -- 2, matching YesNoBox, where B is NO (:2332's own note).
    if request.cancel == false then
      ask.cancel = nil
    elseif request.cancel == 1 then
      ask.cancel = 1
    else
      ask.cancel = 2
    end

    -- Parked rather than raised on the spot: the update wrap promotes it on
    -- the first frame the screen is genuinely idle, so a caller may ask from
    -- anywhere -- a battle.damage listener mid-animation, a faint handler
    -- mid-HP-drain -- without having to know whether the screen is busy.
    screen.__g9PromptPending = ask
    return true
  end

  -- "pending" (asked for, waiting for an idle frame) and "active" (box is
  -- up) are distinguished because they mean different things to a caller: a
  -- pending prompt may still be dropped if the battle ends first, an active
  -- one will always reach onAnswer.
  mod.exports.battleChoiceActive = function(target)
    local screen = resolveScreen(target)
    if screen == nil then return nil end
    if screen.__g9Prompt ~= nil then return "active" end
    if screen.__g9PromptPending ~= nil then return "pending" end
    return nil
  end

  -- Withdraws a question without answering it -- for a caller whose own
  -- reason for asking evaporated (the boss fainted to residual damage while
  -- the box was up). onAnswer is NOT called: there was no answer. The
  -- displaced phase and message context are put back exactly as an answer
  -- would put them back, so this is always safe to call.
  mod.exports.cancelBattleChoice = function(target)
    local screen = resolveScreen(target)
    if screen == nil then return false end
    if screen.__g9PromptPending ~= nil then
      screen.__g9PromptPending = nil
      return true
    end
    local ask = screen.__g9Prompt
    if ask == nil then return false end
    screen.__g9Prompt = nil
    restore(screen, ask)
    return true
  end

  mod.log:info("g9-battle-engine: battle_prompt installed (askBattleChoice, battleChoiceActive, cancelBattleChoice)")
end
