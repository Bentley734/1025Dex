-- Reuse the existing dex's canonical species movepool. This supplies an
-- accessible route for tutor/egg/machine moves without inventing TM items.
return function(mod)
 local E=mod.exports
 local function choices(mon)
  if mod.options:get('moves')~='all' or mon.isEgg or mon.egg then return{}end
  local info=E.statsBySpecies(mon.species)
  if not info then return{}end
  local out,seen={},{}
  local function add(row,method)
   local id=row.move and E.registeredMoveId(row.move)
   if not id or seen[id] or not E.isMoveUsable(id)then return end
   for _,slot in ipairs(mon.moves or {})do if slot.id==id then return end end
   if method=='level-up' and (row.level or 0)>(mon.level or 1)then return end
   local def=mod.content.moves:get(id)
   seen[id]=true
   out[#out+1]={label=def.name,value=id,right=method=='level-up' and 'LEVEL' or method:upper()}
  end
  for _,row in ipairs(info.movesFull or {})do add(row,'level-up')end
  for _,method in ipairs({'machine','tutor','egg'})do
   for _,row in ipairs(info.movesByMethod and info.movesByMethod[method] or {})do add(row,method)end
  end
  table.sort(out,function(a,b)return a.label<b.label end)
  return out
 end
 E.learnableMoves=choices
 E.teachModernMove=function(mon,id,slot)
  local allowed=false
  for _,entry in ipairs(choices(mon))do if entry.value==id then allowed=true;break end end
  if not allowed then return false end
  mon.moves=mon.moves or{}
  slot=slot or (#mon.moves<4 and #mon.moves+1)
  if not slot or slot<1 or slot>4 or slot>#mon.moves+1 then return false end
  local def=mod.content.moves:get(id)
  mon.moves[slot]={id=id,pp=def.pp,maxPP=def.pp}
  return true
 end
 local function open(mon,game)
  local entries=choices(mon)
  if #entries==0 then game.stack:push(mod.ui.TextBox.new(game,'No new moves available.'));return end
  local list
  list=mod.ui.ListMenu.new(game,'LEARN MOVE',entries,{onChoose=function(entry)
   game.stack:pop()
   if #mon.moves<4 then E.teachModernMove(mon,entry.value);return end
   local slots={}
   for i,mv in ipairs(mon.moves)do
    local def=mod.content.moves:get(mv.id)
    slots[i]={label=def and def.name or mv.id,value=i}
   end
   game.stack:push(mod.ui.ListMenu.new(game,'REPLACE WHICH MOVE?',slots,{onChoose=function(chosen)
    game.stack:pop();E.teachModernMove(mon,entry.value,chosen.value)
   end,onCancel=function()game.stack:pop()end}))
  end,onCancel=function()game.stack:pop()end})
  game.stack:push(list)
 end
 mod.hooks:wrap('ui.party.submenu',function(next,game,items,mon,ctx)
  local rows=next(game,items,mon,ctx)
  if type(rows)~='table' or (ctx and ctx.battle)or mod.options:get('moves')~='all' then return rows end
  for _,row in ipairs(rows)do if row.id=='DEX_LEARN_MOVE'then return rows end end
  local copy={};for i,row in ipairs(rows)do copy[i]=row end
  for i,row in ipairs(copy)do
   if row.id=='DEX_ABILITY'then
    local ability=row.onSelect
    copy[i]={id='DEX_TOOLS',label='1025DEX',onSelect=function(selected,currentGame)
     currentGame.stack:push(mod.ui.ListMenu.new(currentGame,'1025DEX',{
      {label='ABILITY',value='ability'},{label='LEARN MOVE',value='learn'}
     },{onChoose=function(entry)
      currentGame.stack:pop()
      if entry.value=='ability'then ability(selected,currentGame)else open(selected,currentGame)end
     end,onCancel=function()currentGame.stack:pop()end}))
    end}
    return copy
   end
  end
  table.insert(copy,math.max(1,#copy),{id='DEX_LEARN_MOVE',label='LEARN MOVE',onSelect=open})
  return copy
 end,100)
end
