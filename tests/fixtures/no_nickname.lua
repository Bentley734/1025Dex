return function(mod)
  if mod.generation ~= 3 then return end
  mod.options:define({
    { key = "nickname_prompts", label = "Nickname prompts", type = "choice",
      default = false, choices = {{"OFF", false}, {"ON", true}},
      description = "OFF skips nickname questions for caught and received Pokemon." },
  })

  local function skip() return mod.options:get("nickname_prompts") == false end

  -- Only the acquisition question: Name Rater dialogue uses 'name',
  -- not this 'give ... nickname' wording. Species names remain untouched.
  local function isPrompt(text)
    if type(text) ~= "string" then return false end
    local s = text:lower():gsub("\\[nlp]", " "):gsub("%s+", " ")
    return s:find("give", 1, true) ~= nil
      and s:find("nickname", 1, true) ~= nil
      and s:find("?", 1, true) ~= nil
  end

  local Ui = require("src.core.game3.battle.ui")
  -- Keep a single wrapper across reloads; use the current mod's option.
  Ui._noNicknameSkip = skip
  if not Ui._noNicknameWrapped then
    local original = Ui.askYesNo
    Ui.askYesNo = function(a, b)
      if Ui._noNicknameSkip() and isPrompt(a) then
        if b then b(false) end
        return
      end
      return original(a, b)
    end
    Ui._noNicknameWrapped = true
  end

  local Adapters = require("src.core.game3.scripting.adapters")
  Adapters._noNicknameSkip = skip
  if not Adapters._noNicknameWrapped then
    local originalHost = Adapters.host
    Adapters.host = function(...)
      local a = originalHost(...)
      local pending = false
      for _, key in ipairs({"openMessage", "openMessageAsync", "openMessageStay"}) do
        local original = a[key]
        if original then
          a[key] = function(text, done, ...)
            pending = Adapters._noNicknameSkip() and isPrompt(text)
            if pending then
              -- Let waitmessage complete without creating a text box.
              if type(done) == "function" then done() end
              return
            end
            return original(text, done, ...)
          end
        end
      end
      local originalAsk = a.askYesNo
      a.askYesNo = function(cb, ...)
        if pending then
          pending = false
          if cb then cb(false) end
          return
        end
        return originalAsk(cb, ...)
      end
      local originalClose = a.closeMessage
      a.closeMessage = function(...)
        pending = false
        if originalClose then return originalClose(...) end
      end
      return a
    end
    Adapters._noNicknameWrapped = true
  end
end
