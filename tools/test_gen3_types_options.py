"""Regress Gen 3 type encoding and missing Ruby/Sapphire options text."""
import os, sys
from pathlib import Path
workspace = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(workspace / '.tools/lua-test'))
from lupa.lua53 import LuaRuntime
os.chdir(workspace / 'gen1recomp-0.3.54')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().root = str(workspace / '1025Dex')
lua.execute(r'''
local function read(p) return assert(loadfile(root..'/'..p))() end
local shape=read('dex/src/gen3shape.lua')
local national=read('dex/data/species/generated/national.lua')
local Schemas=require('src.mods.Schemas')
local target={_names={},_types={},_stats={},_abilities={},_moveNames={}}
local rows={};local ops={}
local count,slot=0,1000
for id,source in pairs(national.register) do
  if source.types then
    local row=shape.romPatch(source)
    for i,t in ipairs(source.types) do
      assert(row.types[i]~='PSYCHIC_TYPE')
      if t=='PSYCHIC_TYPE' then assert(row.types[i]=='PSYCHIC');count=count+1 end
    end
    -- Native patches and added records both pass through the engine writer.
    slot=slot+1
    target._names[slot]=id
    row.index=slot;rows[id]=row;ops[id]=true
  end
end
Schemas.REGISTRIES.pokemon.gen3Write(target,{ops=ops,get=function(_,id)return rows[id]end})
for id,row in pairs(rows) do
  if row.types[1]=='PSYCHIC' then assert(target._types[row.index][1]==14,id) end
end
assert(count>100)
assert(shape.romPatch(national.register.GARDEVOIR).types[1]=='PSYCHIC')
assert(shape.romPatch(national.register.DEOXYS).types[1]=='PSYCHIC')
print('PASS all Psychic source types use numeric Gen 3 Psychic (14): '..count)
local GV=require('src.core.GameVersion')
local bundle={text={},textTables={}}
package.loaded['src.core.game3.scripting.space']={ensureBundle=function()return bundle end}
local Text=require('src.core.game3.rom_text')
read('compat/rse_option_text.lua')()
for _,game in ipairs({'ruby','sapphire'}) do
 GV.set(game)
 for _,name in ipairs({'sOptionMenuItemsNames','sTextSpeedOptions','sBattleSceneOptions','sBattleStyleOptions','sSoundOptions','sButtonTypeOptions'}) do
   for i=0,Text.count(name)-1 do assert(Text.at(name,i)~='?') end
 end
 assert(Text.plain('gText_FrameType')=='TYPE ')
 assert(Text.plain('gText_MenuOption')=='OPTION')
 local IR=require('src.core.game3.scripting.text_ir')
 bundle.text['sOptionMenuItemsNames[0]']=IR.fromAscii('ROM LABEL')
 assert(Text.at('sOptionMenuItemsNames',0)=='ROM LABEL')
 bundle.text={}
 print('PASS '..game..' missing labels, values, and ROM precedence')
end
GV.set('emerald');assert(not pcall(Text.at,'sOptionMenuItemsNames',0))
GV.set('firered');assert(not pcall(Text.at,'sOptionMenuItemsNames',0))
print('PASS Emerald/FireRed text behavior unchanged')
''')
