import unicodedata

NONE, HAT, BREVE, HORN, STROKE = 0, 1, 2, 3, 4
VOWELS = set("aeiouy")
MODCHAR = {"ă": ("a", BREVE), "â": ("a", HAT), "ê": ("e", HAT), "ô": ("o", HAT),
           "ơ": ("o", HORN), "ư": ("u", HORN)}


def parse_nucleus(s):
    return [MODCHAR.get(ch, (ch, NONE)) for ch in s]


NUCLEI = [parse_nucleus(s) for s in (
    "a ă â e ê i o ô ơ u ư y ai ao au ay âu ây eo êu ia iê iu oa oă oe oi ôi ơi oo "
    "ua uâ uê ui uô uơ ưa ưi ươ ưu uy yê iêu yêu oai oao oay oeo uây uôi uya uyê uyu ươi ươu").split()]
FINAL_NUCLEI = [parse_nucleus(s) for s in
                "a ă â e ê i o ô ơ u ư iê oa oă oe oo uâ uê uô ươ uy uyê yê".split()]
INITIALS = set("b c ch d g gh h k kh l m n ng ngh nh p ph q r s t th tr v x".split()) | {""}
FINALS = set("c ch m n ng nh p t".split())
STOP_FINALS = {"c", "ch", "p", "t"}
COMBINING_TONE = ["", "́", "̀", "̉", "̃", "̣"]
COMBINING_MOD = {HAT: "̂", BREVE: "̆", HORN: "̛"}
TELEX_TONES = {"s": 1, "f": 2, "r": 3, "x": 4, "j": 5}


class Letter:
    def __init__(self, base, mod=NONE, upper=False):
        self.base, self.mod, self.upper = base, mod, upper


def compatible(g, n, full):
    if len(g) > len(n) or (full and len(g) != len(n)):
        return False
    return all(b == nb and (m == nm or m == NONE) for (b, m), (nb, nm) in zip(g, n))


class Syllable:
    def __init__(self, letters):
        n = len(letters)
        i = 0
        while i < n and letters[i].base not in VOWELS:
            i += 1
        j = i
        while j < n and letters[j].base in VOWELS:
            j += 1
        self.initial = "".join(l.base for l in letters[:i])
        self.group = list(range(i, j))
        self.final = "".join(l.base for l in letters[j:])
        self.final_has_vowel = any(l.base in VOWELS for l in letters[j:])
        if self.initial == "q" and self.group and letters[i].base == "u":
            self.group = self.group[1:]
            self.initial = "qu"
        elif self.initial == "g" and len(self.group) > 1 and letters[i].base == "i":
            self.group = self.group[1:]
            self.initial = "gi"


def is_valid(letters, tone):
    if not letters:
        return True
    for k, l in enumerate(letters):
        if l.mod == STROKE and not (k == 0 and l.base == "d"):
            return False
        if l.base not in VOWELS and l.mod not in (NONE, STROKE):
            return False
    s = Syllable(letters)
    if s.final_has_vowel:
        return False
    if s.initial not in INITIALS and s.initial not in ("qu", "gi"):
        return False
    if s.initial == "q" and len(letters) > 1:
        return False
    g = [(letters[k].base, letters[k].mod) for k in s.group]
    if s.final:
        if s.final not in FINALS or not g:
            return False
        if not any(compatible(g, n, True) for n in FINAL_NUCLEI):
            return False
        if s.final in STOP_FINALS and tone in (2, 3, 4):
            return False
    elif g and not any(compatible(g, n, False) for n in NUCLEI):
        return False
    if tone and not g:
        return False
    return True


def tone_position(letters, modern):
    s = Syllable(letters)
    g = s.group
    if not g:
        return -1
    modded = [k for k in g if letters[k].mod != NONE]
    if modded:
        return modded[-1]
    if len(g) == 1:
        return g[0]
    if len(g) >= 3:
        return g[1]
    if s.final:
        return g[1]
    pair = letters[g[0]].base + letters[g[1]].base
    if modern and pair in ("oa", "oe", "uy"):
        return g[1]
    return g[0]


def render(letters, tone, modern):
    pos = tone_position(letters, modern) if tone else -1
    s = Syllable(letters)
    g = s.group
    plain_u = -1
    if not s.final and len(g) >= 2 and g[-1] == len(letters) - 1:
        a, b = letters[g[-2]], letters[g[-1]]
        if a.base == "u" and a.mod == HORN and b.base == "o" and b.mod == HORN:
            plain_u = g[-2]
    out = []
    for k, l in enumerate(letters):
        if l.mod == STROKE:
            ch = "đ"
        else:
            ch = l.base + ("" if k == plain_u else COMBINING_MOD.get(l.mod, ""))
            if k == pos:
                ch += COMBINING_TONE[tone]
            ch = unicodedata.normalize("NFC", ch)
        out.append(ch.upper() if l.upper else ch)
    return "".join(out)


class Engine:
    def __init__(self, method="telex", modern=False, spell_check=True):
        self.method, self.modern, self.spell_check = method, modern, spell_check
        self.reset()

    def reset(self):
        self.keys, self.letters, self.tone, self.dropped = [], [], 0, set()
        self.inert = None
        self.auto_horn = False

    def _ok(self):
        return (not self.spell_check) or is_valid(self.letters, self.tone)

    def _group(self):
        return Syllable(self.letters).group

    def _append(self, ch):
        lo = ch.lower()
        letter = Letter(lo, NONE, ch != lo)
        if lo == "o" and self.letters and self.letters[-1].base == "u" and self.letters[-1].mod == HORN:
            letter.mod = HORN
            self.auto_horn = True
        self.letters.append(letter)

    def _undo_literal(self, ch):
        self.dropped.add(len(self.keys) - 1)
        self.letters.append(Letter(ch.lower(), NONE, ch != ch.lower()))

    def _try(self, mutate):
        snap = [(l.base, l.mod, l.upper) for l in self.letters], self.tone
        mutate()
        if self._ok():
            return True
        self.letters = [Letter(*t) for t in snap[0]]
        self.tone = snap[1]
        return False

    def _tone(self, t, ch):
        if not self._group():
            return False
        if self.tone == t:
            self.tone = 0
            self._undo_literal(ch)
            return True
        return self._try(lambda: setattr(self, "tone", t))

    def _remove_tone(self):
        if self.tone == 0:
            return False
        self.tone = 0
        return True

    def _hat(self, ch, target=None):
        g = self._group()
        cands = [k for k in g if self.letters[k].base in ((target,) if target else ("a", "e", "o"))]
        if not cands:
            return False
        if any(self.letters[k].mod == HAT for k in cands):
            for k in cands:
                if self.letters[k].mod == HAT:
                    self.letters[k].mod = NONE
            self._undo_literal(ch)
            return True
        for k in reversed(cands):
            def m(k=k):
                self.letters[k].mod = HAT
            if self._try(m):
                return True
        return False

    def _horn(self, ch, allow_breve, allow_horn=True, allow_insert=False):
        g = self._group()
        L = self.letters
        if allow_horn and self.auto_horn:
            self.auto_horn = False
            return True  # "uwow": the w just confirms the auto ơ
        relevant = {m for m, on in ((HORN, allow_horn), (BREVE, allow_breve)) if on}
        if any(L[k].mod in relevant for k in g):
            for k in g:
                if L[k].mod in relevant:
                    L[k].mod = NONE
            self._undo_literal(ch)
            return True
        if not g:
            if allow_insert and not any(l.base in VOWELS for l in L):
                return self._try(lambda: L.append(Letter("u", HORN, ch.isupper())))
            return False
        bases = [L[k].base for k in g]
        targets = []
        if allow_horn:
            for a in range(len(g) - 1):
                if bases[a] == "u" and bases[a + 1] == "o":
                    targets.append([g[a], g[a + 1]])
            if "o" in bases:
                targets.append([g[len(bases) - 1 - bases[::-1].index("o")]])
            if "u" in bases:
                targets.append([g[bases.index("u")]])
        if allow_breve and "a" in bases:
            targets.append([g[bases.index("a")]])
        for t in targets:
            def m(t=t):
                for k in t:
                    L[k].mod = BREVE if L[k].base == "a" else HORN
            if self._try(m):
                return True
        return False

    def _stroke(self, ch):
        L = self.letters
        if not L or L[0].base != "d":
            return False
        if L[0].mod == STROKE:
            L[0].mod = NONE
            self._undo_literal(ch)
            return True

        def m():
            L[0].mod = STROKE
        return self._try(m)

    @property
    def output(self):
        if self.inert is not None:
            return self.inert
        if self.spell_check and not is_valid(self.letters, self.tone):
            return "".join(k for i, k in enumerate(self.keys) if i not in self.dropped)
        return render(self.letters, self.tone, self.modern)

    def process(self, ch):
        if self.inert is not None:
            self.inert += ch
            return self.output
        before = self.output
        self.keys.append(ch)
        if len(self.keys) > 24:
            self.inert = before + ch
            return self.inert
        lo = ch.lower()
        consumed = False
        auto = self.auto_horn
        self.auto_horn = False
        if self.spell_check and not is_valid(self.letters, self.tone):
            self._append(ch)  # already not Vietnamese: type literally
            return self.output
        self.auto_horn = auto
        if self.method == "telex":
            if lo in TELEX_TONES:
                consumed = self._tone(TELEX_TONES[lo], ch)
            elif lo == "z":
                consumed = self._remove_tone()
            elif lo in "aeo":
                consumed = self._hat(ch, lo)
            elif lo == "w":
                consumed = self._horn(ch, allow_breve=True, allow_insert=True)
            elif lo == "d":
                consumed = self._stroke(ch)
        else:
            if lo in "12345":
                consumed = self._tone(int(lo), ch)
            elif lo == "0":
                consumed = self._remove_tone()
            elif lo == "6":
                consumed = self._hat(ch)
            elif lo == "7":
                consumed = self._horn(ch, allow_breve=False)
            elif lo == "8":
                consumed = self._horn(ch, allow_breve=True, allow_horn=False)
            elif lo == "9":
                consumed = self._stroke(ch)
        self.auto_horn = False
        if not consumed:
            self._append(ch)
        return self.output

    def backspace(self):
        text = self.output
        if not text:
            return False
        target = text[:-1]
        self.reset()
        for k in synth_keys(target, self.method):
            self.process(k)
        if self.output != target:
            self.reset()
            self.inert = target
        return True


TONE_FROM_COMBINING = {c: i for i, c in enumerate(COMBINING_TONE) if c}


def synth_keys(text, method):
    keys, tone, horn, breve = [], 0, False, False
    for ch in text:
        upper = ch != ch.lower()
        d = unicodedata.normalize("NFD", ch.lower())
        if d == "đ":
            keys += [("D" if upper else "d"), "d" if method == "telex" else "9"]
            continue
        base = d[0]
        keys.append(base.upper() if upper else base)
        for c in d[1:]:
            if c in TONE_FROM_COMBINING:
                tone = TONE_FROM_COMBINING[c]
            elif c == "̂":
                keys.append(base if method == "telex" else "6")
            elif c == "̛":
                horn = True
            elif c == "̆":
                breve = True
    if method == "telex":
        if horn or breve:
            keys.append("w")
        if tone:
            keys.append("sfrxj"[tone - 1])
    else:
        if horn:
            keys.append("7")
        if breve:
            keys.append("8")
        if tone:
            keys.append(str(tone))
    return keys


def type_word(s, **kw):
    e = Engine(**kw)
    for ch in s:
        e.process(ch)
    return e.output
