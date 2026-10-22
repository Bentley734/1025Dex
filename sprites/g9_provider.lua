-- Adapt the supplied 1.5.4 indexed-colour pack into the existing 1025Dex baker.
-- No upstream battle hooks are installed. Decoding is lazy and bounded to two shards.
return function(mod,readData,dbk)
 local index=assert(readData('g9_gen3/data/atlas_index.lua'))
 local numbers=assert(readData('g9_gen3/data/numbers_index.lua'))
 local tuning=assert(readData('g9_gen3/data/sprite_scale.lua'))
 local M={records={},species={},version='1.5.4'}
 local aliases={UNOWN_EMARK='UNOWN_26',UNOWN_QMARK='UNOWN_27',SHELLOS_EAST='SHELLOS_1',GASTRODON_EAST='GASTRODON_1'}
 for i=1,25 do aliases['UNOWN_'..string.char(65+i)]='UNOWN_'..i end
 for _,base in ipairs({'FLABEBE','FLOETTE','FLORGES'})do for i,color in ipairs({'YELLOW','ORANGE','BLUE','WHITE'})do aliases[base..'_'..color]=base..'_'..i end end
 local ids={};for id in pairs(index.species)do ids[#ids+1]=id end;table.sort(ids)
 for _,id in ipairs(ids)do
  local rec=index.species[id];M.species[id]='G9@'..id;local stem=dbk.species[id]or aliases[id]or(dbk.stems[id]and id)
  if not stem and rec.female_of then
   local base=id:gsub('_FEMALE$','');stem=(dbk.species[base]or base)..'_female'
  end
  local entry={id=id,cells=rec,tuning=tuning[id]or{}};M.records['G9@'..id]=entry
  if stem then
    M.records[stem]=entry
    if rec.female_of then local base=id:gsub('_FEMALE$','');M.records[(dbk.species[base]or base)..'_female']=entry;M.records['G9@'..base..'_female']=entry end
  end
 end
 function M.stem(species)return M.species[species]end
 function M.select(stem,folder)
  local rec=M.records[stem];local cell=rec and rec.cells[folder]
  if cell then return {id=rec.id,cell=cell,variant=folder,tuning=rec.tuning,height=rec.cells.ht}end
 end
 local shards,order={},{};local palette
 local function image(path)
  local bytes=assert(mod:read('g9_gen3/assets/numbers/'..path..'.png'))
  return love.image.newImageData(love.filesystem.newFileData(bytes,path..'.png'))
 end
 function M.decode(rec)
  local c=rec.cell;local key=string.format('%s:%d:%d:%d:%d',rec.variant,c.sheet or 0,c.start or 0,c.ox or 0,c.oy or 0)
  local b=assert(numbers.blocks[key],'Missing G9 colour block '..key)
  local shard=shards[b[1]]
  if not shard then
   shard=image(assert(numbers.shards[b[1]+1]).file);shards[b[1]]=shard;order[#order+1]=b[1]
   if #order>2 then shards[table.remove(order,1)]=nil end
  end
  palette=palette or image(numbers.palette.file)
  local fs,frames=c.fs,c.frames;assert(b[3]==fs and b[4]==fs*frames,'G9 block geometry mismatch')
  local strip=love.image.newImageData(fs,b[4]);strip:paste(shard,0,0,0,b[2],fs,b[4])
  local raw=strip:getString();local pal=palette:getString():sub(b[5]*numbers.palette.w*4+1,(b[5]+1)*numbers.palette.w*4)
  local colors={};for i=0,numbers.palette.w-1 do colors[i]=pal:sub(i*4+1,i*4+4)end
  local chunks={}
  for start=1,fs*b[4],4096 do
   local pixels={};for p=start,math.min(fs*b[4],start+4095)do pixels[#pixels+1]=assert(colors[raw:byte((p-1)*4+1)],'G9 palette index')end
   chunks[#chunks+1]=table.concat(pixels)
  end
  local decoded=love.image.newImageData(fs,b[4],'rgba8',table.concat(chunks))
  local result=love.image.newImageData(fs*frames,fs)
  for f=0,frames-1 do result:paste(decoded,f*fs,0,0,f*fs,fs,fs)end
  return result
 end
 -- The reference pose's foot row and body centre remain stable across animation.
 function M.geometry(b)
  local r=b.g9Record;local c=r.cell;local back=r.variant:match('^back')~=nil
  local own=r.tuning;local fs=c.fs
  local cx=back and ((c.cx0 or 0)+(c.cx1 or fs))/2 or fs/2
  local foot=back and(c.bfr or c.cy1 or fs)or(c.ffr or fs)
  local origin=back and((c.bfl or 64)-foot)or(64-fs+(c.fy or 0))
  local dx=tonumber(own[back and 'back_dx'or'front_dx'])or 0
  local dy=tonumber(own[back and 'back_dy'or'front_dy'])or 0
  return cx,foot,origin,dx,dy
 end
 return M
end
