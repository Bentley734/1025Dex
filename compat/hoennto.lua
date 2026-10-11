-- Hoennto 0.2.0 projects into cartridge-sized boxes. Preserve that converter
-- and fill the extra 1025Dex boxes before treating compatible mons as reserve.
return function(mod)
  local peer=mod.find and mod:find('kanto_hoenn')
  local transfer=peer and peer.exports and peer.exports.transfer
  if not transfer or transfer.__completeDexBoxes then return end
  transfer.__completeDexBoxes=true
  local original=transfer.project
  transfer.project=function(raw,state)
    local old=raw.storage and raw.storage.boxes or raw.boxes or {}
    original(raw,state)
    if not state.collection then return end
    local gen=require('src.core.GameVersion').generation()
    local cap,count
    if gen==3 then
      local S=require('src.core.game3.storage');cap,count=S.IN_BOX_COUNT,S.TOTAL_BOXES_COUNT
    elseif gen==2 then
      local B=require('src.core.gen2.Boxes');cap,count=B.MONS_PER_BOX,B.NUM_BOXES
    else
      local B=require('src.pokemon.Boxes');cap,count=B.CAPACITY,B.COUNT
    end
    local boxes=gen==3 and raw.storage.boxes or raw.boxes
    for b=1,count do
      if not boxes[b] then
        local meta=old[b] or {}
        boxes[b]=gen==3 and {name=meta.name or 'BOX '..b,wallpaper=meta.wallpaper or 0,mons={}} or {}
      end
    end
    local placed=state.projected[raw.version]
    local reserve,slot=0,0
    for _,record in ipairs(state.collection.records)do
      if not placed[tostring(record.id)] then
        local mon=transfer.convert(record,raw.version)
        if mon then
          while slot<count*cap do
            slot=slot+1;local b=math.floor((slot-1)/cap)+1;local s=(slot-1)%cap+1
            local box=gen==3 and boxes[b].mons or boxes[b]
            if not box[s] then box[s]=mon;placed[tostring(record.id)]=true;break end
          end
        end
        if not placed[tostring(record.id)] then reserve=reserve+1 end
      end
    end
    state.reserveCount=reserve
  end
end
