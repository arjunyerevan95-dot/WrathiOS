#!/usr/bin/env python3
"""Execute production font registration/size selection with bitmap-upload stubs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]

def function(text,signature):
    start=text.index(signature)
    brace=text.index('{',start)
    depth=1
    i=brace+1
    while depth:
        depth+=(text[i]=='{')-(text[i]=='}')
        i+=1
    return text[start:i]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine-source',type=Path,default=ROOT/'Vendor/wrath-darkplaces')
    parser.add_argument('--artifacts',type=Path,default=ROOT/'Artifacts/font-atlas-demand')
    parser.add_argument('--compiler',default=os.environ.get('CXX','c++'))
    args=parser.parse_args()
    args.artifacts.mkdir(parents=True,exist_ok=True)
    spec=json.loads((ROOT/'config/engine/ios_source_patches.json').read_text(encoding='utf-8'))
    files={}
    for name in ['ft2.c','ft2.h','gl_draw.c']:
        text=(args.engine_source/name).read_text(encoding='utf-8')
        for patch in spec['patches']:
            if patch['path']==name:
                for r in patch['replacements']:
                    assert text.count(r['old'])==1,(name,r['old'][:100])
                    text=text.replace(r['old'],r['new'],1)
        files[name]=text
    source=files['ft2.c']
    font_struct=function(files['ft2.h'],'typedef struct ft2_font_s')+' ft2_font_t;'
    production='\n'.join(function(source,s) for s in [
        'float Font_VirtualToRealSize(float sz)',
        'float Font_SnapTo(float val, float snapwidth)',
        'static qboolean Font_LoadSize(ft2_font_t *font, float size, qboolean check_only)\n{'])
    demand='\n'.join(function(source,s) for s in [
        'static qboolean Font_PrepareDemandSizes(', 'static qboolean Font_EnsureDemandSize('])
    registration=function(source,'qboolean Font_LoadFont(const char *name, dp_font_t *dpfnt)')
    selection=function(source,'int Font_IndexForSize(ft2_font_t *font, float _fsize, float *outw, float *outh)')
    prefix=r'''
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdarg>
#include <algorithm>
using std::max;
typedef int qboolean;
typedef unsigned int Uchar;
typedef unsigned long FT_ULong;
typedef void *FT_Face;
struct FT_Vector { long x,y; };
enum { MAX_FONT_SIZES=16, MAX_FONT_FALLBACKS=3 };
struct ft2_settings_t { int unused; };
struct ft2_attachment_t {};
struct ft2_font_map_t {
    ft2_font_map_t *next;
    float size,intSize;
    int glyphSize;
    double sfx,sfy;
    float width_of[256];
    struct { float kerning[256][256][2]; } kerning;
};
struct Cvar { float value; int integer; };
static Cvar vid_height={1320,1320};
static Cvar vid_conwidth={478,478},vid_conheight={220,220};
static Cvar r_font_nonpoweroftwo={1,1},r_font_size_snapping={1,1};
static struct { int width,height; struct { int arb_texture_non_power_of_two; } support; } vid={2868,1320,{1}};
'''
    stubs=r'''
struct dp_font_t {
    char texpath[64],fallbacks[MAX_FONT_FALLBACKS][64];
    int req_face,fallback_faces[MAX_FONT_FALLBACKS];
    float req_sizes[MAX_FONT_SIZES],width_of[256];
    ft2_settings_t settings;
    ft2_font_t *ft2;
};
static uint64_t atlasLoads,atlasAttempts,bitmapBytes,maxBitmapBytes;
static float failSize=-1,unsupportedSize=-1;
static int errors;
static void Con_Printf(const char *,...) { ++errors; }
static void Mem_Free(void *p) { std::free(p); }
static ft2_font_t *Font_Alloc() { return (ft2_font_t *)std::calloc(1,sizeof(ft2_font_t)); }
static size_t strlcpy(char *out,const char *in,size_t cap) { size_t n=std::strlen(in); if(cap){std::memcpy(out,in,std::min(n,cap-1));out[std::min(n,cap-1)]=0;}return n; }
static char *va(char *out,size_t cap,const char *fmt,...) { va_list a;va_start(a,fmt);std::vsnprintf(out,cap,fmt,a);va_end(a);return out; }
static bool FS_FileExists(const char *) { return false; }
static bool Font_LoadFile(const char *name,int,ft2_settings_t *settings,ft2_font_t *font) {
    std::memset(font,0,sizeof(*font));font->settings=settings;
    strlcpy(font->name,name,sizeof(font->name));
    if(!std::strcmp(name,"missing"))return false;
    font->face=(void *)1;font->has_kerning=true;return true;
}
static void Font_UnloadFont(ft2_font_t *font) {
    if(font->next)Font_UnloadFont(font->next);
    for(auto &map:font->font_maps){std::free(map);map=nullptr;}
    font->face=nullptr;
}
static float Font_SearchSize(ft2_font_t *,FT_Face face,float size) { return face && size!=unsupportedSize?size:-1; }
static void Font_Postprocess(ft2_font_t *,void *,int,int,float,float,int *l,int *r,int *t,int *b){*l=*r=*t=*b=0;}
static int CeilPowerOf2(int n){int p=1;while(p<n)p*=2;return p;}
static FT_ULong qFT_Get_Char_Index(FT_Face,Uchar ch){return ch;}
static int qFT_Get_Kerning(FT_Face,FT_ULong,FT_ULong,int,FT_Vector *v){v->x=64;v->y=0;return 0;}
enum { FT_KERNING_DEFAULT=0 };
static bool Font_LoadMap(ft2_font_t *,ft2_font_map_t *start,Uchar,ft2_font_map_t **out){
    ++atlasAttempts;if(start->size==failSize)return false;
    auto *map=(ft2_font_map_t *)std::calloc(1,sizeof(ft2_font_map_t));assert(map);
    map->size=start->size;map->intSize=start->size;map->glyphSize=start->glyphSize;
    start->next=map;*out=map;++atlasLoads;
    uint64_t bytes=(uint64_t)map->glyphSize*map->glyphSize*16*16*4;
    bitmapBytes+=bytes;maxBitmapBytes=std::max(maxBitmapBytes,bytes);return true;
}
'''
    tests=r'''
static dp_font_t fixture(){
    dp_font_t f={};strlcpy(f.texpath,"journal",sizeof(f.texpath));
    float requests[]={6,8,12,14,16,20,24,32,40,64};
    for(int i=0;i<MAX_FONT_SIZES;++i)f.req_sizes[i]=i<10?requests[i]:-1;
    for(auto &width:f.width_of)width=.41f;
    return f;
}
static float selected(ft2_font_t *font,float virtualSize){int i=Font_IndexForSize(font,virtualSize,nullptr,nullptr);assert(i>=0);return font->font_maps[i]->size;}
static void release(dp_font_t &f){auto *p=f.ft2;Font_UnloadFont(p);while(p){auto *next=p->next;std::free(p);p=next;}f.ft2=nullptr;}
int main(){
    auto f=fixture();assert(Font_LoadFont(f.texpath,&f));
#ifdef WRATH_IOS_GLES3
    assert(atlasLoads==1 && bitmapBytes==5308416 && maxBitmapBytes==5308416);
    assert(f.ft2->ios_requested_count==10);
    std::memcpy(f.ft2->ios_image_widths,f.width_of,sizeof(f.width_of));
    assert(selected(f.ft2,13)==84); // Equal distance: original larger-size tie.
    assert(atlasLoads==2);
    int i=Font_IndexForSize(f.ft2,14,nullptr,nullptr);
    assert(std::fabs(f.ft2->font_maps[i]->width_of[65]-Font_SnapTo(.41f,1/84.f))<.00001f);
    assert(std::fabs(f.ft2->font_maps[i]->kerning.kerning[65][66][0]-1/84.f)<.00001f);
    uint64_t before=atlasLoads;assert(selected(f.ft2,64)==384 && atlasLoads==before+1);
    assert(maxBitmapBytes==603979776); // Large requested text remains native size.
    before=atlasLoads;assert(selected(f.ft2,64)==384 && atlasLoads==before);
#else
    assert(atlasLoads==10 && maxBitmapBytes==603979776); // Exact original eager path.
    assert(selected(f.ft2,13)==84 && selected(f.ft2,64)==384);
#endif
    float w=13.9f,h=13.9f;int i2=Font_IndexForSize(f.ft2,13.9f,&w,&h);
    assert(i2>=0 && std::fabs(w-14)<.00001f && std::fabs(h-14)<.00001f);
    release(f);

    // A missing primary uses the original bitmap/fallback mechanism.
    auto fallback=fixture();strlcpy(fallback.texpath,"missing",sizeof(fallback.texpath));
    strlcpy(fallback.fallbacks[0],"fallback",sizeof(fallback.fallbacks[0]));
    assert(Font_LoadFont(fallback.texpath,&fallback));assert(fallback.ft2->image_font && fallback.ft2->next);
    assert(selected(fallback.ft2,12)==72);release(fallback);

    // Default-size normalization and arbitrary console dimensions remain valid.
    auto defaults=fixture();defaults.req_sizes[0]=0;defaults.req_sizes[1]=-1;
    assert(Font_LoadFont(defaults.texpath,&defaults));assert(selected(defaults.ft2,0)==16);release(defaults);
    vid_conheight.value=440;vid_conwidth.value=956;
    auto custom=fixture();assert(Font_LoadFont(custom.texpath,&custom));assert(selected(custom.ft2,14)==42);release(custom);
    vid_conheight.value=220;vid_conwidth.value=478;

    auto rejected=fixture();for(auto &s:rejected.req_sizes)s=-1;
    assert(!Font_LoadFont(rejected.texpath,&rejected) && !rejected.ft2);
#ifdef WRATH_IOS_GLES3
    auto failure=fixture();assert(Font_LoadFont(failure.texpath,&failure));failSize=384;
    int errorBefore=errors;assert(Font_IndexForSize(failure.ft2,64,nullptr,nullptr)==-1 && errors>errorBefore);
    uint64_t attempts=atlasAttempts;assert(Font_IndexForSize(failure.ft2,64,nullptr,nullptr)==-1 && atlasAttempts==attempts);
    assert(failure.ft2->ios_demand_failed);release(failure);failSize=-1;
#endif
    std::puts("Production font registration/selection: startup atlas demand, native sizes, reuse, tie/snapping, kerning, image fallback, custom dimensions and failure recovery passed");
}
'''
    fixture=prefix+font_struct+'\n'+stubs+'\n'+production+'\n#ifdef WRATH_IOS_GLES3\n'+demand+'\n#endif\n'+registration+'\n'+selection+'\n'+tests
    src=args.artifacts/'production-font-fixture.cpp'
    src.write_text(fixture,encoding='utf-8')
    modes=[]
    is_msvc=Path(args.compiler).name.lower() in {'cl','cl.exe'}
    for name,defines in [('gles2',[]),('gles3',['WRATH_IOS_GLES3=1'])]:
        exe=args.artifacts/('font-'+name+('.exe' if os.name=='nt' else ''))
        if is_msvc:
            # Original C functions intentionally round sizes between float/int;
            # MSVC's C++ fixture warns about those unchanged conversions.
            command=[args.compiler,'/nologo','/std:c++17','/EHsc','/W4','/WX','/wd4244',*(f'/D{d}' for d in defines),str(src),f'/Fo{args.artifacts/name}.obj',f'/Fe{exe}']
        else:
            command=[args.compiler,'-std=c++17','-Wall','-Wextra','-Werror',*(f'-D{d}' for d in defines),str(src),'-o',str(exe)]
        subprocess.run(command,check=True)
        subprocess.run([str(exe.resolve())],check=True)
        modes.append(name)
    baseline=(args.engine_source/'ft2.c').read_text(encoding='utf-8')
    original_rasterizer=function(baseline,'static qboolean Font_LoadMap(ft2_font_t *font, ft2_font_map_t *mapstart, Uchar _ch, ft2_font_map_t **outmap)\n{')
    fixed_rasterizer=function(source,'static qboolean Font_LoadMap(ft2_font_t *font, ft2_font_map_t *mapstart, Uchar _ch, ft2_font_map_t **outmap)\n{')
    assert original_rasterizer==fixed_rasterizer
    receipt={'compiled_and_executed':modes,'production_functions':['Font_LoadFont','Font_LoadSize','Font_IndexForSize','Font_VirtualToRealSize','Font_PrepareDemandSizes','Font_EnsureDemandSize'],
        'initial_atlases':{'gles2':10,'gles3':1},'largest_native_atlas_bytes_preserved':603979776,
        'gles3_initial_bitmap_bytes':5308416,'glyph_rasterizer_unchanged_sha256':hashlib.sha256(fixed_rasterizer.encode()).hexdigest(),
        'scope':'Public engine functions exercised with deterministic FreeType-file and GPU-upload fixtures; no full engine or phone validation claim.'}
    (args.artifacts/'validation.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt,indent=2))

if __name__=='__main__':
    main()
