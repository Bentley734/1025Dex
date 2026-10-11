"""Exercise production ZIP installation and media routing in Lua 5.3/LuaJIT."""
import hashlib, os, sys, time, zipfile, json, zlib
from pathlib import Path
w=Path(__file__).resolve().parents[2];root=w/'1025Dex'
sys.path.insert(0,str(w/'.tools/lua-test'))
from lupa import lua53, luajit21

def vm(module):
    lua=module.LuaRuntime(unpack_returned_tuples=True,encoding='latin-1')
    if module is luajit21:
        lua.execute('''local native=load;load=function(s,n,m,e) if type(s)=='string' then local f,err=loadstring(s,n);if f and e then setfenv(f,e)end;return f,err end;return native(s,n)end;table.unpack=unpack''')
    return lua

os.chdir(w/'gen1recomp-0.3.54')
for module in [lua53,luajit21]:
    lua=vm(module);lua.globals().arg=lua.table_from([str(root)])
    lua.execute((root/'tests/asset_bridge.lua').read_text())

os.chdir(root)
for module in [lua53,luajit21]:
    lua=vm(module)
    lua.execute((root/'tests/asset_manager_ui.lua').read_bytes().decode('latin-1'))
os.chdir(w/'gen1recomp-0.3.54')

def installer(module, archive, *, write_failure=False, cached=None):
    lua=vm(module);cache={} if cached is None else cached;handles={};temporary={}
    lua.globals().source=(root/'compat/asset_download_manager.lua').read_bytes().decode('latin-1')
    lua.globals().jsonsource=(w/'gen1recomp-0.3.54/src/link/Json.lua').read_bytes().decode('latin-1')
    lua.globals().catalogsource=(root/'compat/asset_catalog.lua').read_text()
    lua.globals().configsource=(root/'compat/asset_config.lua').read_text()
    def read(k):return cache.get(k)
    def write(k,v):
        if write_failure and '/files/' in k:return None,'disk full'
        cache[k]=v;return True
    def info(k):return lua.table_from({'type':'file','size':len(cache[k])}) if k in cache else None
    def delete(k):cache.pop(k,None);return True
    def newfile(name):
        f=archive.open('rb');handles[name]=f
        return lua.table_from({'open':lambda *_:True,'getSize':lambda *_:archive.stat().st_size,
            'seek':lambda _,n:f.seek(int(n))>=0,'read':lambda _,n:f.read(int(n)).decode('latin-1'),
            'close':lambda *_:f.close()})
    def download(url,name,options):temporary[name]=archive;return lua.table_from({})
    def fsinfo(name):return lua.table_from({'size':archive.stat().st_size}) if name in temporary else None
    def fsremove(name):temporary.pop(name,None);return True
    g=lua.globals()
    g.cacheRead=read;g.cacheWrite=write;g.cacheInfo=info;g.cacheDelete=delete
    g.newFile=newfile;g.fsInfo=fsinfo;g.fsRemove=fsremove;g.download=download
    g.hashBytes=lambda _,s:hashlib.sha256(s.encode('latin-1')).hexdigest()
    g.inflate=lambda _,__,s:zlib.decompress(s.encode('latin-1'),-15).decode('latin-1')
    g.clock=lambda:time.monotonic()
    lua.execute('''
local Json=assert(load(jsonsource))()
local fs={newFile=function(n)return newFile(n)end,getInfo=function(n)return fsInfo(n)end,remove=function(n)return fsRemove(n)end}
local modules={['src.link.Json']=Json,['src.core.SaveData']={persistenceFs=function()return fs end},
 ['src.net.Fetch']={download=function(u,n,o)return download(u,n,o)end,poll=function()return {status='ok'}end,release=function()end,cancel=function()end}}
mod={generation=3,path='fixture',content={screens={register=function()end}},info=function()return nil end,list=function()return {}end,
 cache={read=function(_,k)return cacheRead(k)end,write=function(_,k,v)return cacheWrite(k,v)end,
 info=function(_,k)return cacheInfo(k)end,delete=function(_,k)return cacheDelete(k)end}}
config=assert(load(configsource))();config.embedded=true;config.expectedFiles=assert(load(catalogsource))()
local env=setmetatable({require=function(n)return assert(modules[n],n)end,
 love={timer={getTime=function()return clock()end},data={hash=function(a,s)return hashBytes(a,s)end,
 encode=function(_,__,s)return s end,decompress=function(a,b,s)return inflate(a,b,s)end}}},{__index=_G})
manager=assert(load(source,'production 1025Dex installer','t',env))()(mod,config)
''')
    return lua,cache,temporary

pack=w/'1025Dex-assets-v1.0.0.zip'
lua,cache,temp=installer(lua53,pack)
lua.execute('manager:start()')
assert lua.globals().manager.state=='downloading'
for i in range(50000):
    lua.execute('manager:update()')
    if lua.globals().manager.state in ['done','error']:break
assert lua.globals().manager.state=='done',lua.globals().manager.error
with zipfile.ZipFile(pack) as z:
    meta=json.loads(z.read('asset-pack.json'))
    for path,record in meta['files'].items():
        value=cache['dex_assets/files/'+path].encode('latin-1')
        assert len(value)==record['size'] and hashlib.sha256(value).hexdigest()==record['sha256']
assert cache['dex_assets/complete.txt']=='zip:1.0.0' and not temp
print('PASS complete real pack extraction and SHA-256 verification:',len(meta['files']),'files',flush=True)
# Replacing the core creates a new manager while retaining the installation cache.
lua2,_,temp2=installer(luajit21,pack,cached=cache)
assert lua2.globals().manager.isComplete(lua2.globals().manager)
lua2.execute('manager:start()')
assert lua2.globals().manager.state=='done' and not temp2
print('PASS LuaJIT core update reuses assets without network or extraction',flush=True)

# Tiny production ZIP rejection cases use the pinned production catalog.
fixtures=w/'.work/dex-asset-tests';fixtures.mkdir(exist_ok=True)
first,nextrecord=next(iter(meta['files'].items()))
for case in ['missing','wrong-id','wrong-version','tampered','duplicate','traversal','write-failure','cancel']:
    a=fixtures/(case+'.zip');m=dict(meta);m['files']={first:nextrecord}
    if case=='wrong-id':m['id']='other_mod'
    if case=='wrong-version':m['version']='9.9.9'
    with zipfile.ZipFile(a,'w',zipfile.ZIP_STORED) as z,zipfile.ZipFile(pack) as source:
        z.writestr('asset-pack.json',json.dumps(m))
        content=source.read(first)
        z.writestr(first,b'bad' if case=='tampered' else content)
        if case=='duplicate':z.writestr(first,content)
        if case=='traversal':z.writestr('assets/../outside.png',b'bad')
    v,c,t=installer(luajit21,a,write_failure=case=='write-failure')
    # Test content checks with a one-file pack; separate missing case retains full count.
    if case!='missing':v.globals().config.legacyExpectedFiles=1
    v.execute('manager:start()')
    if case=='cancel':
        v.execute('manager:cancel()');assert v.globals().manager.state=='idle' and not t
        assert 'dex_assets/complete.txt' not in c
    else:
        for i in range(10):v.execute('manager:update()')
        assert v.globals().manager.state=='error',(case,v.globals().manager.state)
        assert 'dex_assets/complete.txt' not in c
    print('PASS installer case:',case,flush=True)
lua2.execute('manager:beginDelete()')
for i in range(50000):
    lua2.execute('manager:update()')
    if lua2.globals().manager.state!='deleting':break
assert lua2.globals().manager.state=='deleted'
assert not any(k.startswith('dex_assets/files/') for k in cache)
assert cache['dex_assets/deferred.txt']=='1.0.0'
print('PASS scoped removal and deferred re-download',flush=True)

# Migrate an existing full bundled install without contacting GitHub.
directories={}
for path in meta['files']:
    parent,name=path.rsplit('/',1)
    while '/' in parent:
        directories.setdefault(parent,set()).add(name)
        parent,name=parent.rsplit('/',1)
for case in ['complete','partial','corrupt']:
    v,c,t=installer(luajit21,pack)
    def localinfo(path):
        if path in meta['files'] and not (case=='partial' and path==first):
            return v.table_from({'type':'file','size':meta['files'][path]['size']})
        if path in directories:return v.table_from({'type':'directory'})
    def localread(path):
        if case=='corrupt' and path==first:return 'incorrect local bytes'
        return (root/path.removeprefix('assets/')).read_bytes().decode('latin-1')
    v.globals().localInfo=localinfo;v.globals().localRead=localread
    v.globals().localList=lambda path:v.table_from(sorted(directories.get(path,[])))
    v.execute('''mod.info=function(_,p)return localInfo(p)end;mod.read=function(_,p)return localRead(p)end;
mod.list=function(_,p)return localList(p)end;config.legacyFiles=config.expectedFiles;manager:start()''')
    if case=='partial':
        assert v.globals().manager.state=='downloading'
        v.execute('manager:cancel()');assert 'dex_assets/complete.txt' not in c
    else:
        assert v.globals().manager.state=='migrating' and not t
        for i in range(50000):
            v.execute('manager:update()')
            if v.globals().manager.state!='migrating':break
        if case=='complete':
            assert v.globals().manager.state=='done',v.globals().manager.error
            assert c['dex_assets/complete.txt']=='zip:1.0.0'
            assert len([k for k in c if k.startswith('dex_assets/files/')])==len(meta['files'])
        else:
            assert v.globals().manager.state=='error' and 'dex_assets/complete.txt' not in c
    print('PASS legacy migration:',case,flush=True)
