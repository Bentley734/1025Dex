-- Preserve the dex's ruleset option and use live effect support, including
-- alternate forms. Never turn a missing record into a teachable move.
return function(mod)
 local baseUsable=assert(mod.exports.isMoveUsable)
 local gaps={}
 for _,id in ipairs(mod.exports.statusCoverageGaps or {})do gaps[id]=true end
 local function usable(id)
  local live=mod.content.moves:get(id)
  return live~=nil and not gaps[id] and baseUsable(id)
 end
 mod.exports.isMoveUsable=usable
 local original=mod.exports.reapplyLearnsets
 mod.exports.reapplyLearnsets=function()
  if mod.options:get('moves')~='all' then return end
  -- Mark gaps before the underlying pass; clear its early memoized answers.
  mod.exports.resetMoveSupportCache()
  original()
 end
 mod.exports.moveSupportGaps=gaps
 -- Publish the live support marker so native Metronome uses the implemented
 -- roster, rather than the old data-only build's static placeholder flags.
 for id in mod.content.moves:each()do
  mod.content.moves:patch(id,{effectModeled=usable(id)})
 end
end
