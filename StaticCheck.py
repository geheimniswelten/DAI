from pathlib import Path
import re, sys, xml.etree.ElementTree as ET
root=Path(__file__).resolve().parent
src=root/'Source'
errors=[]; warnings=[]
for required in ('README.md', 'Build.ps1', 'Test-MCP.ps1', 'CodexMCPIDE.dpk', 'CodexMCPIDE.dproj'):
    if not (root/required).is_file(): errors.append(f'missing {required}')
files=sorted(src.glob('*.pas'))
# encoding/unit/file
for p in files:
    try: t=p.read_text(encoding='utf-8')
    except Exception as e: errors.append(f'{p.name}: UTF-8: {e}'); continue
    m=re.search(r'(?im)^\s*unit\s+([A-Za-z0-9_.]+)\s*;',t)
    if not m: errors.append(f'{p.name}: no unit declaration')
    elif m.group(1).lower()!=p.stem.lower(): errors.append(f'{p.name}: unit {m.group(1)} mismatch')
    if 'EInvalidOperation' in t: errors.append(f'{p.name}: EInvalidOperation remains')
    if 'ExpandEnvironmentVariables' in t: errors.append(f'{p.name}: unknown ExpandEnvironmentVariables remains')
    if re.search(r'(?i)\b(?:TODO|FIXME)\b', t): errors.append(f'{p.name}: TODO/FIXME remains')
    if not re.search(r'(?is)\bend\s*\.\s*$',t): errors.append(f'{p.name}: no final end.')
# project XML
try: ET.parse(root/'CodexMCPIDE.dproj')
except Exception as e: errors.append(f'dproj XML: {e}')
# refs
all_names={p.name.lower() for p in files}
dpk=(root/'CodexMCPIDE.dpk').read_text(encoding='utf-8')
dproj=(root/'CodexMCPIDE.dproj').read_text(encoding='utf-8')
if '<ProjectVersion>20.4</ProjectVersion>' not in dproj: errors.append('DPROJ is not Delphi 13 ProjectVersion 20.4')
if '<FrameworkType>None</FrameworkType>' not in dproj: errors.append('DPROJ FrameworkType must be None for the package')
if 'Internal/Open Source' in (src/'CodexMCP.Register.pas').read_text(encoding='utf-8'): errors.append('unsubstantiated splash license text remains')
if 'System.Types' not in (src/'CodexMCP.Register.pas').read_text(encoding='utf-8'): errors.append('Register unit misses System.Types for Rect')
if 'System.SysUtils' not in (src/'CodexMCP.Wizard.pas').read_text(encoding='utf-8'): errors.append('Wizard unit misses System.SysUtils for sLineBreak')
if "CCodexMCPProtocolVersion = '2025-11-25'" not in (src/'CodexMCP.Constants.pas').read_text(encoding='utf-8'): errors.append('unexpected MCP protocol version')
for p in files:
    rel='Source\\'+p.name
    if rel.lower() not in dpk.lower(): errors.append(f'DPK missing {rel}')
    if rel.lower() not in dproj.lower(): errors.append(f'DPROJ missing {rel}')
# protocol vs dispatcher
prot=(src/'CodexMCP.Protocol.pas').read_text(encoding='utf-8')
disp=(src/'CodexMCP.OTA.Dispatcher.pas').read_text(encoding='utf-8')
tools=re.findall(r"NewTool\(\s*'([^']+)'", prot)
branches=re.findall(r"SameText\(AName,\s*'([^']+)'\)", disp)
# branches has activate and open separately; unique preserve
ut=[]
for x in tools:
    if x not in ut: ut.append(x)
ub=[]
for x in branches:
    if x not in ub: ub.append(x)
if len(tools)!=len(set(tools)): errors.append('duplicate protocol tools')
if set(ut)!=set(ub): errors.append(f'tool mismatch missing dispatcher={sorted(set(ut)-set(ub))}, undocumented={sorted(set(ub)-set(ut))}')
if len(ut)!=28: errors.append(f'expected 28 tools, found {len(ut)}')
# qualified methods duplicate
for p in files:
    t=p.read_text(encoding='utf-8')
    q=re.findall(r'(?im)^\s*(?:class\s+)?(?:function|procedure|constructor|destructor)\s+([A-Za-z_][\w.]*)(?:\s*<[^;]+>)?\s*(?:\([^;]*?\))?\s*(?::\s*[^;]+)?\s*;',t)
    seen={}
    for name in q:
        if '.' not in name: continue
        k=name.lower(); seen[k]=seen.get(k,0)+1
    for k,n in seen.items():
        if n>1: errors.append(f'{p.name}: qualified method {k} appears {n} times')
# interface declared class methods vs implemented names (simple)
for p in files:
    t=p.read_text(encoding='utf-8')
    intf=t.split('\nimplementation',1)[0]
    # class names and declarations in their class blocks, approximate
    for cm in re.finditer(r'(?is)\b([A-Za-z_]\w*)\s*=\s*class\b.*?\bend\s*;', intf):
        cname=cm.group(1); block=cm.group(0)
        decls=[]
        for dm in re.finditer(r'(?im)^\s*(?:class\s+)?(?:function|procedure|constructor|destructor)\s+([A-Za-z_]\w*)\b',block):
            decls.append(dm.group(1))
        for d in decls:
            # constructors and class destructor names included
            if not re.search(r'(?im)^\s*(?:class\s+)?(?:function|procedure|constructor|destructor)\s+'+re.escape(cname)+r'\.'+re.escape(d)+r'\b',t):
                errors.append(f'{p.name}: {cname}.{d} declared not implemented')
# crude lexical string/comment balance and begin/end count
# remove strings/comments/directives; count begin/case/record/class/try vs end is too complex; just parens/brackets outside strings/comments
def strip_pas(s):
    out=[]; i=0; state='code'
    while i<len(s):
        c=s[i]; n=s[i+1] if i+1<len(s) else ''
        if state=='code':
            if c=="'": state='str'; out.append(' ')
            elif c=='{' : state='brace'; out.append(' ')
            elif c=='(' and n=='*': state='star'; out.extend('  '); i+=1
            elif c=='/' and n=='/': state='line'; out.extend('  '); i+=1
            else: out.append(c)
        elif state=='str':
            out.append(' ')
            if c=="'":
                if n=="'": out.append(' '); i+=1
                else: state='code'
        elif state=='brace':
            out.append('\n' if c=='\n' else ' ')
            if c=='}': state='code'
        elif state=='star':
            out.append('\n' if c=='\n' else ' ')
            if c=='*' and n==')': out.append(' '); i+=1; state='code'
        elif state=='line':
            out.append('\n' if c=='\n' else ' ')
            if c=='\n': state='code'
        i+=1
    return ''.join(out), state
for p in files:
    t=p.read_text(encoding='utf-8'); st,state=strip_pas(t)
    if state in ('str','brace','star'): errors.append(f'{p.name}: unterminated lexical state {state}')
    stack=[]; pairs={')':'(',']':'['}
    line=1
    for c in st:
        if c=='\n': line+=1
        elif c in '([': stack.append((c,line))
        elif c in ')]':
            if not stack or stack[-1][0]!=pairs[c]: errors.append(f'{p.name}:{line}: unbalanced {c}'); break
            stack.pop()
    if stack: errors.append(f'{p.name}: unclosed delimiters {stack[-5:]}')
print('Tools:',len(ut),', '.join(ut))
if warnings:
    print('WARNINGS:'); print('\n'.join('- '+w for w in warnings))
if errors:
    print('ERRORS:'); print('\n'.join('- '+e for e in errors)); sys.exit(1)
print(f'OK: {len(files)} Pascal units, DPK/DPROJ references, XML, tool parity, method declarations and lexical delimiters.')
