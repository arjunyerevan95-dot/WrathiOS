from pathlib import Path
import subprocess,os,tempfile
root=Path(__file__).resolve().parents[2]
s=(root/'Gate5C/WrathZinkBridge.mm').read_text()
engine=(root/'Vendor/wrath-darkplaces/vid_sdl.c').read_text()
mode=engine[engine.index('drivername = NULL;'):]
assert mode.index('GL_GetProcAddress("glGetString")') < mode.index('SDL_GL_CreateContext(window)')
def body(name):
 a=s.index(name);a=s.index('{',a);depth=1;b=a+1
 while depth:
  depth+=(s[b]=='{')-(s[b]=='}');b+=1
 return s[a:b]
load=body('int WrathZinkLoadLibrary(')
proc=body('void *WrathZinkGetProcAddress(')
ensure=s[s.index('static int WrathZinkEnsureLibrary(void){'):s.index('SDL_GLContext WrathZinkCreateContext(')]
assert 'dlopen(' in ensure and 'OSMesaGetProcAddress' in ensure
assert 'createContext(attributes' not in ensure
h='''#include <cassert>
static int attempts=0; static bool fail=false; static void *(*getProc)(const char*)=nullptr;
static int token; static void *resolve(const char*){return &token;}
static int WrathZinkEnsureLibrary(){++attempts;if(fail)return -1;getProc=resolve;return 0;}
'''
h+='int WrathZinkLoadLibrary(const char*)'+load+'\nvoid *WrathZinkGetProcAddress(const char*n)'+proc
h+='''
int main(){
 assert(WrathZinkLoadLibrary(nullptr)==0);assert(attempts==1);
 assert(WrathZinkGetProcAddress("glGetString")==&token);
 getProc=nullptr;assert(WrathZinkGetProcAddress("glGetString")==&token);
 fail=true;assert(WrathZinkLoadLibrary(nullptr)==-1);
 assert(WrathZinkGetProcAddress("glGetString")==nullptr);
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td)/'test.cpp';p.write_text(h);exe=Path(td)/('test.exe' if os.name=='nt' else 'test')
 command=([os.environ.get('CXX','cl'),'/nologo','/EHsc','/W4','/WX',str(p),'/Fe:'+str(exe)] if os.name=='nt' else [os.environ.get('CXX','c++'),'-std=c++17','-Wall','-Wextra','-Werror',str(p),'-o',str(exe)])
 subprocess.run(command,check=True,cwd=td)
 subprocess.run([str(exe)],check=True)
print('Real production loader/proc entry bodies: pre-context lookup, lazy retry and load failure propagation passed')
