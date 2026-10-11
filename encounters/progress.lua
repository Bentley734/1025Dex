-- Use the native League-clear flag, not National Dex visibility (the mod
-- enables that UI from the beginning). Support imported and live sessions.
local M={}
function M.postgame()
  local Runtime=require("src.core.game3.runtime")
  local session=Runtime.getSession and Runtime.getSession()
  if not session then return false end
  local Profile=require("src.core.game3.profile")
  local C=require("src.core.game3.constants").of(Profile.forSession(session).id)
  local id=C:require("flags","FLAG_SYS_GAME_CLEAR")
  local Space=require("src.core.game3.scripting.space")
  local store=Space.isActive and Space.isActive() and Space.getStore() or session
  return (store and store.flags and store.flags.FLAG_SYS_GAME_CLEAR==true)
    or require("src.core.game3.scripting.flags").getFlag(store,nil,id)==true
end
return M
