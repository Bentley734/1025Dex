-- Recent Game3 builds keep a caught-mon portrait layer after registration.
-- Return to the ordinary battle text/menu pass once its fade finishes.
-- Clear before the callback so nickname-skipping mods and PC transfers also
-- get the normal message pass used by the HD background compatibility mods.
return function()
  local Ui=require('src.core.game3.battle.ui')
  local Battle=require('src.core.game3.battle')
  if Ui.__completeDexCatchReturn or type(Ui.askYesNo)~='function' then return end
  Ui.__completeDexCatchReturn=true
  if type(Ui.updateCaughtDexScene)=='function' then
    local update=Ui.updateCaughtDexScene
    Ui.updateCaughtDexScene=function(...)
      local ready=update(...)
      if ready and Battle._phase=='catch_dex_return'
        and type(Ui.clearCaughtDexScene)=='function' then Ui.clearCaughtDexScene() end
      return ready
    end
  end
  local ask=Ui.askYesNo
  Ui.askYesNo=function(...)
    if Battle._phase=='catch_nickname_prompt' and Ui._caughtDexScene
      and type(Ui.clearCaughtDexScene)=='function' then Ui.clearCaughtDexScene() end
    return ask(...)
  end
end
