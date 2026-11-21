-- Linked-channel audio gate. The original separation stays reusable in cache.
local M={}
function M.settings(value)
  value=type(value)=='table'and value or{}
  local db=tonumber(value.threshold_db);if not db or db~=db then db=-25 end
  return {enabled=value.enabled~=false,threshold_db=math.max(-60,math.min(0,db))}
end
function M.enabled(settings)return type(settings)=='table'and settings.enabled==true end
function M.decode(raw,spec)
  local samples,at={},1
  for i=1,#raw//(spec.bits//8)do
    local n;if spec.format==1 then n,at=string.unpack('<i2',raw,at);n=n/32768 else n,at=string.unpack('<f',raw,at)end
    samples[i]=(n==n and math.abs(n)<1e10)and n or 0
  end;return samples
end
function M.plan(path,spec,first,count,settings,yield_fn)
  if not M.enabled(settings)then return end
  local threshold=10^(settings.threshold_db/20);local hold=math.floor(spec.rate*.025+.5)
  local attack=math.max(1,math.floor(spec.rate*.003+.5));local release=math.max(1,math.floor(spec.rate*.040+.5))
  local f=assert(io.open(path,'rb'));f:seek('set',spec.offset+first*spec.alignment)
  local ok,result=xpcall(function()
    local intervals,last={},nil;local done=0
    while done<count do
      local n=math.min(4096,count-done);local raw=assert(f:read(n*spec.alignment));assert(#raw==n*spec.alignment,'AITN-725: WAV обрезан.')
      local samples=M.decode(raw,spec)
      for frame=0,n-1 do
        local level=0;for c=1,spec.channels do level=math.max(level,math.abs(samples[frame*spec.channels+c]))end
        if level>=threshold then
          local at=first+done+frame
          if not last or at-last.last>hold then last={first=at,last=at};intervals[#intervals+1]=last else last.last=at end
        end
      end
      done=done+n;if yield_fn then yield_fn()end
    end
    for _,v in ipairs(intervals)do v.rise=math.max(first,v.first-attack);v.full=v.last+hold;v.finish=v.full+release end
    return {intervals=intervals,cursor=1,attack=attack,release=release}
  end,debug.traceback)
  f:close();assert(ok,result);return result
end
function M.gain(plan,frame)
  if not plan then return 1 end
  local list=plan.intervals
  while list[plan.cursor]and frame>=list[plan.cursor].finish do plan.cursor=plan.cursor+1 end
  local gain=0
  for i=plan.cursor,#list do
    local v=list[i];if frame<v.rise then break end
    local g=1
    if frame<v.first then g=(frame-v.rise)/math.max(1,v.first-v.rise)
    elseif frame>v.full then g=(v.finish-frame)/plan.release end
    gain=math.max(gain,g)
  end;return math.max(0,math.min(1,gain))
end
function M.apply(samples,frames,channels,first,plan)
  if not plan then return samples end
  for frame=0,frames-1 do
    local gain=M.gain(plan,first+frame)
    for c=1,channels do local i=frame*channels+c;samples[i]=gain==0 and 0 or samples[i]*gain end
  end;return samples
end
function M.encode(samples,spec)
  local blocks={}
  for first=1,#samples,512 do
    local last=math.min(#samples,first+511)
    if spec.format==1 then
      for i=first,last do local n=samples[i]*32768;samples[i]=math.max(-32768,math.min(32767,n<0 and math.ceil(n-.5)or math.floor(n+.5)))end
    end
    blocks[#blocks+1]=string.pack('<'..string.rep(spec.format==1 and'i2'or'f',last-first+1),table.unpack(samples,first,last))
  end;return table.concat(blocks)
end
function M.allowed(bank,time,settings)
  if not M.enabled(settings)then return true end
  local dt=bank.hop/bank.rate;local index=(time-(bank.origin or 0))/dt+1;local level=0
  for i=math.max(1,math.floor(index-.001/dt)),math.min(#bank.peaks,math.ceil(index+.008/dt))do level=math.max(level,bank.peaks[i])end
  return level>=10^(settings.threshold_db/20)
end
return M
