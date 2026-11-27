import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine import Engine, type_word
fails=0
for line in open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'cases.tsv'),encoding='utf-8'):
    if not line.strip(): continue
    m,mod,inp,exp=line.rstrip('\n').split('\t')
    got=type_word(inp,method=m,modern=mod=='1')
    if got!=exp: fails+=1; print('FAIL',m,mod,inp,'->',got,'expected',exp)
# word-end restore (restore.tsv: method, modern, keys, the one word the dictionary knows or -, expected)
for line in open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'restore.tsv'),encoding='utf-8'):
    if not line.strip(): continue
    m,mod,inp,known,exp=line.rstrip('\n').split('\t')
    e=Engine(method=m,modern=mod=='1')
    for ch in inp: e.process(ch)
    got=e.restore_if_not_word(lambda w: w==known) or e.output
    if got!=exp: fails+=1; print('RESTORE FAIL',m,mod,inp,'->',got,'expected',exp)
# Esc revert (revert.tsv: method, keys, expected revert result or -, keys typed after, expected output)
for line in open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'revert.tsv'),encoding='utf-8'):
    if not line.strip(): continue
    m,inp,exp,more,final=line.rstrip('\n').split('\t')
    e=Engine(method=m)
    for ch in inp: e.process(ch)
    got=e.revert() or '-'
    for ch in more: e.process(ch)
    if got!=exp or e.output!=final: fails+=1; print('REVERT FAIL',m,inp,'->',got,e.output,'expected',exp,final)
# backspace: type word, backspace, should equal output minus last char, then continue typing
def bs(m,word,n,more,exp):
    global fails
    e=Engine(method=m)
    for ch in word: e.process(ch)
    for _ in range(n): e.backspace()
    for ch in more: e.process(ch)
    if e.output!=exp: fails+=1; print('BS FAIL',word,n,more,'->',e.output,'expected',exp)
bs('telex','tieengs',1,'h','tiếnh')
bs('telex','tieengs',2,'t','tiết')
bs('telex','dduwowcj',1,'',  'đượ')
bs('telex','tesst',1,'t','test')
bs('telex','vieetj',3,'ieetj','việt')
bs('vni','tie6ng1',1,'','tiến')
import random
random.seed(1)
alpha='aeiouywdsfrxjzngthcmqAEW'
for _ in range(20000):
    m=random.choice(['telex','vni'])
    al=alpha+('0123456789' if m=='vni' else '')
    w=''.join(random.choice(al) for _ in range(random.randint(1,10)))
    e=Engine(method=m,modern=random.random()<.5)
    for ch in w: e.process(ch)
    before=e.output
    e.backspace()
    if e.output!=before[:-1]: fails+=1; print('FUZZ',m,w,repr(before),repr(e.output)); break
print('fails',fails)
