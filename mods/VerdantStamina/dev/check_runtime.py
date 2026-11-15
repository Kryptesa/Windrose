"""Check which renderer the running game's most recent mod load actually used."""
from pathlib import Path
import sys
import re

root=Path(__file__).resolve().parents[3]
revision=re.search(r'M\.revision="([^"]+)"',(root/'mods/VerdantStamina/Scripts/renderer.lua').read_text()).group(1)
config=(root/'mods/VerdantStamina/Scripts/config.lua').read_text()
sys.path.insert(0,str(root/'tools/python'))
from lupa.lua54 import LuaRuntime
settings=LuaRuntime().execute(config)
def setting(name):return float(settings[name])
scale=setting('ui_scale')
geometry=f'diameter={(2*setting("radius")+setting("base_thickness"))*scale:.1f} bonusWeights={setting("bonus_thickness")*scale:.1f}/{setting("outer_bonus_thickness")*scale:.1f} scale={scale:.2f}'

log=Path(r'C:\Program Files (x86)\Steam\steamapps\common\Windrose\R5\Binaries\Win64\ue4ss\UE4SS.log')
text=log.read_text(encoding='utf-8',errors='replace')
starts=[i for i,line in enumerate(text.splitlines()) if '[VerdantStamina]' in line and ' ready;' in line]
lines=text.splitlines()
if not starts:
    sys.exit('FAIL: no mod startup recorded')
latest=lines[starts[-1]:]
if f'renderer={revision};' not in latest[0]:
    sys.exit('FAIL: latest runtime still uses the previous loader/renderer: '+latest[0])
failures=[line for line in latest if '[VerdantStamina]' in line and ('Stopped;' in line or 'Could not load' in line)]
if failures:
    sys.exit('FAIL: '+failures[-1])
if settings['split_sources'] and not settings['visual_test_mode']:
    source_status=[line for line in latest if 'Sources verified ' in line or 'Source split unavailable;' in line]
    if not source_status:
        sys.exit('WAIT: enter the world to validate native source accounting')
    if 'Source split unavailable;' in source_status[-1]:
        sys.exit('FAIL: '+source_status[-1])
bindings=[line for line in latest if f'Bound renderer={revision}' in line]
if not bindings:
    sys.exit('WAIT: new renderer loaded; enter the world to validate attachment')
last=bindings[-1]
if geometry not in last:
    sys.exit('FAIL: unexpected ring geometry: '+last)
if f"surface={settings['surface_style']}" not in last:
    sys.exit('FAIL: unexpected or unconfirmed surface style: '+last)
print(f'PASS: {revision} attached; {geometry}')
print(last)
if settings['visual_test_mode']:
    demos=[line for line in latest if 'DISPLAY TEST active' in line]
    if not demos:sys.exit('FAIL: visual test enabled but no mapping recorded')
    print(demos[-1])
    print('VISUAL TEST ONLY: native source accounting is not certified by this result')
elif settings['split_sources']:print(source_status[-1])
