-- SPDX-License-Identifier: GPL-3.0-or-later
-- String-type API for modern combat over the existing dex chart.
return function(data)
 local T={TYPES={}};local chart,index
 function T.load(value)
  chart=assert(value.type_chart);index={}
  for _,row in ipairs(chart.matchups)do
   index[row.attacker]=index[row.attacker]or{}
   index[row.attacker][row.defender]=row.multiplier
  end
 end
 function T.rows(attacker,defenders)
  local out={}
  for _,row in ipairs(chart.matchups)do
   if row.attacker==attacker then
    for _,defender in ipairs(defenders)do
     if row.defender==defender then out[#out+1]=row.multiplier;break end
    end
   end
  end
  return out
 end
 function T.effectiveness(attacker,defenders)
  local result=10;local row=index[attacker]or{}
  for _,defender in ipairs(defenders)do result=math.floor(result*(row[defender]or 10)/10)end
  return result
 end
 function T.category(id)local record=chart.types[id];return record and record.category end
 function T.displayName(id)local record=chart.types[id];return record and record.name or id end
 T.load(data)
 return T
end
