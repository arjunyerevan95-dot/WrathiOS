from pathlib import Path
import subprocess,os
root=Path(__file__).resolve().parents[2]
subprocess.run([os.environ.get("PYTHON", "python3"),str(root/"scripts/materialize_engine_patches.py")],check=True)
text=(root/"Derived/wrath-darkplaces-ios/quakedef.h").read_text()
a=text.index("#if defined(__ANDROID__)");b=text.index("#elif defined(__linux__)",a)
block=text[a:b]+"#endif\n"
for backend in ["gles","zink"]:
    defines=["-DTARGET_OS_IPHONE=1"]+(["-DWRATH_IOS_ZINK=1"] if backend=="zink" else [])
    result=subprocess.run([os.environ.get("CC","cc"),"-E","-dM","-x","c",*defines,"-"],input=block,text=True,capture_output=True,check=True).stdout
    assert ('#define USE_GLES2 1' in result)==(backend=="gles"),result
    assert '#define DP_OS_NAME "iPhoneOS"' in result,result
print("Actual materialized iPhone platform block: Zink desktop GL / GLES rollback selection passed")
