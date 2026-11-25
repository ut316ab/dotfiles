#!/usr/bin/env python3
"""Copy Darryl's Hyprland (JaKooLit) keybinds onto KDE Plasma's global shortcuts.

Run:  kde-hyprkeys.py          -> dry run, prints what would change
      kde-hyprkeys.py --apply  -> applies live via kglobalaccel (D-Bus), saves an
                                  undo log to ~/.config/kde-hyprkeys-undo.json
Needs Krohnkite (tiling) and the hyprfollow KWin script loaded.
Backups of the config files before the first run: ~/.config/*.before-hyprkeys
"""
import json, os, sys
import dbus

APPLY = "--apply" in sys.argv

# ---- Qt key encoding -------------------------------------------------------
MODS = {"Meta": 0x10000000, "Ctrl": 0x04000000, "Alt": 0x08000000, "Shift": 0x02000000}
KEYS = {"Left": 0x01000012, "Up": 0x01000013, "Right": 0x01000014, "Down": 0x01000015,
        "Return": 0x01000004, "Tab": 0x01000001, "Space": 0x20, "Print": 0x01000009,
        ".": 0x2E, ",": 0x2C, "[": 0x5B, "]": 0x5D, "{": 0x7B, "}": 0x7D}
for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
    KEYS[c] = ord(c)
# US layout: Shift+digit produces these symbols; register both spellings
SHIFTED = {"1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")"}
for d, s in SHIFTED.items():
    KEYS[s] = ord(s)

def k(spec):
    *mods, key = spec.split("+") if not spec.endswith("++") else spec[:-2].split("+") + ["+"]
    v = KEYS[key]
    for m in mods:
        v |= MODS[m]
    return v

def name(v):
    out = [m for m, bit in MODS.items() if v & bit]
    base = v & 0x01FFFFFF
    inv = {val: key for key, val in KEYS.items()}
    out.append(inv.get(base, hex(base)))
    return "+".join(out)

# ---- the mapping -------------------------------------------------------------
# (component, action, [keys], mode)  mode: "set" = exactly these keys, "add" = keep existing too
KW, KR = "kwin", "kwin"
M = []
def S(comp, act, keys, mode="set"):
    M.append((comp, act, [k(x) for x in keys], mode))

# Windows & tiling (Krohnkite actions live in the kwin component)
for d in ("Left", "Right", "Up", "Down"):
    S(KR, f"KrohnkiteFocus{d}", [f"Meta+{d}"])                     # SUPER+arrow focus
    S(KR, f"KrohnkiteShift{d}", [f"Meta+Ctrl+{d}", f"Meta+Alt+{d}"])  # move / swap
S(KR, "KrohnkiteShrinkWidth", ["Meta+Shift+Left"])                  # SUPER+SHIFT+arrow resize
S(KR, "KrohnkitegrowWidth", ["Meta+Shift+Right"])
S(KR, "KrohnkiteShrinkHeight", ["Meta+Shift+Up"])
S(KR, "KrohnkiteGrowHeight", ["Meta+Shift+Down"])
S(KR, "KrohnkiteToggleFloat", ["Meta+Space"])
S(KR, "KrohnkiteFloatAll", ["Meta+Alt+Space"])
S(KR, "KrohnkiteSetMaster", ["Meta+Ctrl+Return"])
S(KR, "KrohnkiteIncrease", ["Meta+I"])                              # add master
S(KR, "KrohnkiteDecrease", ["Meta+Ctrl+D"])                         # remove master
S(KR, "KrohnkiteSpiralLayout", ["Meta+Alt+1"])                      # dwindle
S(KR, "KrohnkiteTileLayout", ["Meta+Alt+2"])                        # master
S(KR, "KrohnkiteColumnsLayout", ["Meta+Alt+3"])                     # scrolling
S(KR, "KrohnkiteMonocleLayout", ["Meta+Alt+4"])                     # monocle
S(KR, "KrohnkiteNextLayout", ["Meta+Alt+L"])                        # toggle layouts
S(KR, "KrohnkiteFocusNext", ["Meta+J"])                             # cycle next
S(KR, "KrohnkiteFocusPrev", ["Meta+K"])                             # cycle previous
KROHNKITE_MAPPED = {a for c, a, _, _ in M}
S(KW, "Window Maximize", ["Meta+F"], "add")                         # fullscreen 1 (maximize)
S(KW, "Window Fullscreen", ["Meta+Shift+F"])

# Workspaces
for n in range(1, 11):
    d = str(n % 10)
    S(KW, f"Switch to Desktop {n}", [f"Meta+{d}"], "add")
    S(KW, f"HyprFollowToDesktop{n}", [f"Meta+Shift+{d}", f"Meta+{SHIFTED[d]}"])
    S(KW, f"Window to Desktop {n}", [f"Meta+Ctrl+{d}"])              # move silently
S(KW, "Switch to Next Desktop", ["Meta+Tab", "Meta+."])
S(KW, "Switch to Previous Desktop", ["Meta+Shift+Tab", "Meta+,"])
S(KW, "HyprFollowToNext", ["Meta+Shift+]", "Meta+}"])
S(KW, "HyprFollowToPrev", ["Meta+Shift+[", "Meta+{"])
S(KW, "Window to Next Desktop", ["Meta+Ctrl+]"])
S(KW, "Window to Previous Desktop", ["Meta+Ctrl+["])

# App launchers
S("kitty.desktop", "_launch", ["Meta+Return"])
S("zen.desktop", "_launch", ["Meta+B"])
S("hypr-keyhints.desktop", "_launch", ["Meta+H"])
S(KW, "Overview", ["Meta+A"], "add")
S("ksmserver", "Lock Session", ["Ctrl+Alt+L"], "add")
S("ksmserver", "Log Out", ["Ctrl+Alt+P"], "add")
S("plasmashell", "show-on-mouse-pos", ["Meta+Alt+V"], "add")
S("org.kde.kcalc.desktop", "_launch", ["Meta+Alt+C"], "add")
S("org.kde.plasma.emojier.desktop", "_launch", ["Meta+Alt+E"], "add")

# Screenshots (Spectacle)
S("org.kde.spectacle.desktop", "FullScreenScreenShot", ["Meta+Print"], "add")
S("org.kde.spectacle.desktop", "RectangularRegionScreenShot", ["Meta+Shift+Print", "Meta+Shift+S"])
S("org.kde.spectacle.desktop", "ActiveWindowScreenShot", ["Alt+Print"])

# ---- D-Bus helpers -----------------------------------------------------------
bus = dbus.SessionBus()
ka = dbus.Interface(bus.get_object("org.kde.kglobalaccel", "/kglobalaccel"), "org.kde.KGlobalAccel")

def aid(comp, act, cf="", af=""):
    return dbus.Array([comp, act, cf, af], signature="s")

def current(comp, act):
    return [int(x) for x in ka.shortcut(aid(comp, act))]

def owners(key):
    res = []
    for i in ka.getGlobalShortcutsByKey(dbus.Int32(key)):
        res.append((str(i[2]), str(i[0])))     # (component, action)
    return res

FRIENDLY = {"kitty.desktop": "kitty", "zen.desktop": "Zen Browser",
            "hypr-keyhints.desktop": "Keyboard shortcuts"}

def setkeys(comp, act, keys):
    keys = dbus.Array([dbus.Int32(x) for x in keys], signature="i")
    if comp.endswith(".desktop"):
        # launcher components must be marked present or the key is ignored
        a = aid(comp, act, FRIENDLY.get(comp, comp), "Launch " + FRIENDLY.get(comp, comp))
        ka.doRegister(a)
        ka.setShortcut(a, keys, dbus.UInt32(6))  # SetPresent | NoAutoloading
    else:
        ka.setForeignShortcut(aid(comp, act), keys)

# ---- plan --------------------------------------------------------------------
targets = {(c, a) for c, a, _, _ in M}
final = {}
for comp, act, keys, mode in M:
    cur = current(comp, act) if mode == "add" else []
    final[(comp, act)] = list(dict.fromkeys(cur + keys))
# an "add" target must not keep an old key that another target now claims
claimed = {}
for comp, act, keys, mode in M:
    for x in keys:
        claimed[x] = (comp, act)
for (comp, act), keys in final.items():
    final[(comp, act)] = [x for x in keys if claimed.get(x, (comp, act)) == (comp, act)]

# Krohnkite actions with no Hyprland equivalent: clear so they can't grab keys
all_kwin = [str(x) for x in dbus.Interface(bus.get_object("org.kde.kglobalaccel", "/component/kwin"),
                                           "org.kde.kglobalaccel.Component").shortcutNames()]
for act in all_kwin:
    if act.startswith("Krohnkite") and act not in KROHNKITE_MAPPED:
        if current("kwin", act):
            final[("kwin", act)] = []

# Steal keys from other actions
removals = {}
for (comp, act), keys in list(final.items()):
    for key in keys:
        for oc, oa in owners(key):
            if (oc, oa) == (comp, act) or (oc, oa) in final:
                continue
            removals.setdefault((oc, oa), set()).add(key)

undo = {}
print("== Keys taken away from other actions:")
for (oc, oa), ks in sorted(removals.items()):
    cur = current(oc, oa)
    undo[f"{oc}|{oa}"] = cur
    newk = [x for x in cur if x not in ks]
    print(f"  {oc:32} {oa:45} {', '.join(map(name, cur)) or '-'}  ->  {', '.join(map(name, newk)) or 'none'}")
    final.setdefault((oc, oa), newk)

print("== New keys:")
for (comp, act), keys in final.items():
    if (comp, act) in removals:
        continue
    try:
        cur = current(comp, act)
    except dbus.DBusException:
        cur = []
    undo.setdefault(f"{comp}|{act}", cur)
    if sorted(cur) != sorted(keys):
        print(f"  {comp:32} {act:45} {', '.join(map(name, cur)) or '-'}  ->  {', '.join(map(name, keys)) or 'none'}")

if not APPLY:
    print("\nDry run only. Re-run with --apply.")
    sys.exit(0)

log = os.path.expanduser("~/.config/kde-hyprkeys-undo.json")
if not os.path.exists(log):  # keep the ORIGINAL state from the first run
    json.dump(undo, open(log, "w"), indent=1)
# removals first, then the new keys
for (oc, oa) in removals:
    setkeys(oc, oa, final[(oc, oa)])
for (comp, act), keys in final.items():
    if (comp, act) not in removals:
        setkeys(comp, act, keys)
# verify
bad = [(c, a) for (c, a), keys in final.items() if sorted(current(c, a)) != sorted(keys)]
print(f"\nApplied {len(final)} actions; mismatches: {bad or 'none'}")
