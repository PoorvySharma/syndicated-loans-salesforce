#!/usr/bin/env python3
"""Developer helper: split a '//// FILE: name' bundle into Apex class/trigger files + meta XML."""
import re, sys
from pathlib import Path
SRC = Path(__file__).resolve().parent.parent / 'force-app/main/default'
parts = re.split(r'^//// FILE: (\S+)\n', Path(sys.argv[1]).read_text(), flags=re.M)
for i in range(1, len(parts), 2):
    name, body = parts[i], parts[i+1].rstrip() + '\n'
    d, tpl = (SRC/'classes', 'ApexClass') if name.endswith('.cls') else (SRC/'triggers', 'ApexTrigger')
    d.mkdir(parents=True, exist_ok=True)
    (d/name).write_text(body)
    (d/(name+'-meta.xml')).write_text(f'<?xml version="1.0" encoding="UTF-8"?>\n<{tpl} xmlns="http://soap.sforce.com/2006/04/metadata">\n    <apiVersion>62.0</apiVersion>\n    <status>Active</status>\n</{tpl}>\n')
    print('wrote', name)
