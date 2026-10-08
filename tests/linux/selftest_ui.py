# -*- coding: utf-8 -*-
"""Test de la vraie interface d'Orbit pour Linux (lance par orbit.py quand ORBIT_SELFTEST=1).

Lancement : ORBIT_DATA=$(mktemp -d) ORBIT_SELFTEST=1 xvfb-run -a python3 linux/orbit.py
Le temps est accelere (decalage d'horloge) : un focus de 50 minutes se teste en quelques secondes.
"""
import os
import sys
import tkinter as tk

import orbit_core as C

ok = 0
ko = 0
RSS_MAX_MB = float(os.environ.get('ORBIT_RSS_MAX_MB', '60'))


def check(name, cond, detail=''):
    global ok, ko
    if cond:
        ok += 1
        print('  OK    ' + name)
    else:
        ko += 1
        print('  ECHEC %s %s' % (name, detail))


def section(n):
    print('\n== ' + n)


def shot(app, name):
    """Capture d'ecran (seulement si ORBIT_SHOTS donne un dossier ; il faut ImageMagick « import »)."""
    folder = os.environ.get('ORBIT_SHOTS')
    if folder:
        import subprocess
        app.root.update()
        subprocess.run(['import', '-window', 'root', os.path.join(folder, name + '.png')], check=False)


def rss_mb():
    with open('/proc/self/status') as f:
        for line in f:
            if line.startswith('VmRSS:'):
                return int(line.split()[1]) / 1024
    return 0


def all_widgets(w):
    out = [w]
    for ch in w.winfo_children():
        out += all_widgets(ch)
    return out


def buttons_of(w):
    return [b for b in all_widgets(w) if isinstance(b, tk.Button)]


def press(win, label):
    for b in buttons_of(win):
        if label in b.cget('text'):
            b.invoke()
            return True
    return False


def bubble_text(app):
    if not app.bubble_win:
        return ''
    return ' '.join(lab.cget('text') for lab in all_widgets(app.bubble_win) if isinstance(lab, tk.Label))


def seconds(app, n):
    """Fait avancer le temps de n secondes, une seconde a la fois, comme la vraie boucle."""
    for _ in range(n):
        app.offset += 1
        app._second()
    app.root.update()


def run(app):
    try:
        scenario(app)
    except Exception as e:   # un plantage du scenario est un echec, jamais un blocage
        import traceback
        traceback.print_exc()
        check('scenario sans erreur', False, repr(e))
    print('\n%d verification(s) reussie(s), %d echec(s)' % (ok, ko))
    sys.stdout.flush()
    app.root.destroy()
    os._exit(1 if ko else 0)


def scenario(app):
    r = app.root
    r.update()
    section('Demarrage')
    rss0 = rss_mb()
    print('  (memoire au demarrage : %.1f Mo)' % rss0)
    check('la petite fenetre est affichee, toujours au-dessus', r.winfo_viewable() and r.attributes('-topmost'))
    check('en bas a droite de l\'ecran', r.winfo_x() > r.winfo_screenwidth() / 2 and r.winfo_y() > r.winfo_screenheight() / 2)
    check('6 boutons ronds (note, ✋, S.O.S, tableaux, notes, reprises)', len(app.dock_buttons) == 6)
    right = max(b.master.winfo_x() + b.master.winfo_width() for b in app.dock_buttons.values()) + app.dock.winfo_x()
    check('les boutons ne passent pas sous le robot', right <= app.canvas.winfo_x(), '%d > %d' % (right, app.canvas.winfo_x()))
    check("pas de blague ni de culture G dans les phrases", not any('blague' in k or 'culture' in k for k in __import__('orbit').LINES))
    check(f'memoire au demarrage < {RSS_MAX_MB:.0f} Mo', rss0 < RSS_MAX_MB, '%.1f Mo' % rss0)
    shot(app, '1-demarrage')

    section('Tableaux')
    for t in ('Rapport mensuel !2', 'Appeler le garage', 'Payer la facture EDF !1'):
        app.s.add_card(t)
    app.open_boards()
    r.update()
    shot(app, '0-tableaux')
    lists = app._lists
    check('3 colonnes, 3 cartes dans « À faire »', len(lists) == 3 and list(lists.values())[0].size() == 3)
    first = list(lists.values())[0]
    first.selection_set(0)
    press(app._boards_win, '▶')
    r.update()
    check('▶ : la carte passe dans « En cours »', list(app._lists.values())[1].size() == 1)
    app._boards_win.destroy()
    r.update()
    check('fenetre fermee = detruite (memoire rendue)', 'boards' not in app.windows)

    section('Focus, barre de couleur et tic qui s\'accelere')
    app.start_focus()
    r.update()
    shot(app, '2-focus')
    check('focus lance, carte la plus urgente liee', app.s.timer['state'] == 'Focus' and len(app.s.kanban['focus']) == 1)
    check('barre de compte a rebours visible, bleue, la fenetre s\'agrandit', app.bar.winfo_ismapped() and app.level == 'calm'
          and r.winfo_height() >= app.H + app.BAR - 2, 'hauteur %d' % r.winfo_height())
    check('le bouton ✋ est actif pendant le focus', app.dock_buttons['ctx'].cget('state') == 'normal')
    app.offset += app.s.time_left(app.now()) - 6 * 60
    seconds(app, 1)
    check('a 6 min de la fin : orange, pas de tic', app.level == 'high' and not [p for p in app.sound.played if p.startswith('tick')])
    seconds(app, 59)                       # jusqu'a 5:00 de la fin
    app.sound.played.clear()
    seconds(app, 60)                       # 1re minute de la zone finale
    first_min = len([p for p in app.sound.played if p.startswith('tick')])
    seconds(app, 3 * 60 + 30)              # jusqu'a 0:30 de la fin
    shot(app, '3-derniere-minute')
    check('derniere minute : rouge', app.level == 'final' and app.bar.itemcget(app.bar_fill, 'fill') == '#FF4D4D')
    seconds(app, 29)                       # jusqu'a 0:01
    total = len([p for p in app.sound.played if p.startswith('tick')])
    check('zone finale : le tic commence doucement (toutes les 20 s)', 2 <= first_min <= 4, '%d' % first_min)
    check('puis il s\'accelere jusqu\'a la fin', total >= 30, '%d tics' % total)
    check('les 10 dernieres secondes : tic plus aigu', 'tick-hi' in ''.join(app.sound.played))
    seconds(app, 2)
    shot(app, '4-fin-du-focus')
    check('fin du focus : question « pause ? » avec boutons', app.s.timer['state'] == 'AwaitBreak' and app.has_question()
          and any('Je prends ma pause' in b.cget('text') for b in buttons_of(app.bubble_win)))
    check('victoire « Focus » notee', any(w['kind'] == 'focus' for w in app.s.anchor['wins']))
    check('la barre disparait', not app.bar.winfo_ismapped())
    press(app.bubble_win, 'Je prends ma pause')
    r.update()
    check('pause lancee, barre verte', app.s.timer['state'] == 'Break' and app.level == 'break')
    app.sound.played.clear()
    said = []
    real_say = app.say
    app.say = lambda text, *a, **k: (said.append(text), real_say(text, *a, **k))
    for _ in range(9):                     # (les bulles se ferment en temps reel : on les ferme a la main)
        app.hide_bubble()
        seconds(app, 60)
    app.say = real_say
    import orbit
    check('pendant la pause : jamais de tic', not [p for p in app.sound.played if p.startswith('tick')])
    check('pendant la pause : petites phrases sympas', any(t in orbit.LINES['break'] for t in said), ' | '.join(said)[:200])
    app.stop()

    section('Note rapide')
    app.quick_note()
    r.update()
    w = app.windows['note']
    txt = [x for x in all_widgets(w) if isinstance(x, tk.Text)][0]
    txt.insert('1.0', 'Idée notée sous Linux ✓')
    press(w, 'OK')
    r.update()
    check('note gardee, fenetre fermee', app.s.notes and app.s.notes[0]['text'] == 'Idée notée sous Linux ✓' and 'note' not in app.windows)

    section("Je m'interromps")
    app.start_focus()
    app.interrupt()
    r.update()
    w = app.windows['interrupt']
    entries = [x for x in all_widgets(w) if isinstance(x, tk.Entry)]
    entries[0].insert(0, 'le rapport')
    entries[1].delete(0, 'end')
    entries[1].insert(0, 'ecrire la conclusion')
    press(w, 'Enregistrer')
    r.update()
    rep = app.s.open_reprises()
    check('reprise gardee, focus en pause', rep and rep[0]['next'] == 'ecrire la conclusion' and app.s.timer['paused'])
    app.offer_reprise(rep[0])
    r.update()
    check('« Tu t\'étais arrêté(e) » avec la prochaine etape', 'conclusion' in bubble_text(app))
    press(app.bubble_win, 'Reprendre')
    r.update()
    check('reprendre : le focus repart, reprise terminee', not app.s.timer['paused'] and not app.s.open_reprises())
    app.stop()

    section('S.O.S : une seule chose a la fois')
    app.sos()
    r.update()
    w = app.windows['sos']
    e = [x for x in all_widgets(w) if isinstance(x, tk.Entry)][0]
    e.insert(0, 'Répondre au mail de Julie')
    press(w, 'Découper')
    r.update()
    u = app.s.anchor['unstick']
    check('decoupage immediat (messagerie), une seule etape affichee', u and 'messagerie' in u['steps'][0]['content'] and 'runner' in app.windows)
    for _ in range(len(u['steps'])):
        press(app.windows['runner'], "C'est fait")
        r.update()
    check('toutes les etapes : victoire « Débloqué »', app.s.anchor['unstick'] is None and app.s.anchor['wins'][-1]['title'].startswith('Débloqué'))
    app.windows['runner'].destroy()

    section('Relance « Tu attends quoi ? »')
    app.hide_bubble()
    app.last_busy = app.now() - 46 * 60
    app.check_idle_nudge()
    r.update()
    check("apres 45 min sans focus : « qu'est-ce que tu attends ? » + cartes", "qu'est-ce que tu attends" in bubble_text(app)
          and len(buttons_of(app.bubble_win)) >= 4)
    press(app.bubble_win, '1.')
    r.update()
    check('un clic sur une carte : focus lance dessus', app.s.timer['state'] == 'Focus' and len(app.s.kanban['focus']) == 1)
    app.stop()

    section('Toutes les fenetres s\'ouvrent et se ferment')
    for name, fn in (('notes', app.open_notes), ('reprises', app.open_reprises), ('search', app.open_search),
                     ('settings', app.open_settings), ('focuscards', app.choose_focus_cards)):
        fn()
        r.update()
        okw = name in app.windows and app.windows[name].winfo_exists()
        app.windows[name].destroy()
        r.update()
        check('fenetre « %s »' % name, okw and name not in app.windows)
    app.show_wins()
    r.update()
    check('mes victoires du jour', 'victoire' in bubble_text(app))

    section('Donnees')
    app.save()
    s2 = app.store.load()
    check('tout est relu a l\'identique', len(s2.kanban['cards']) == len(app.s.kanban['cards']) and len(s2.notes) == len(app.s.notes))
    s3 = C.State()
    C.import_zip(s3, C.export_zip(app.s))
    check('export / import (meme zip que le PC et le telephone)', len(s3.kanban['cards']) == 3 and s3.notes)

    section('Memoire')
    for _ in range(3):
        app.open_boards()
        app.open_notes()
        app.open_settings()
        r.update()
        for k in list(app.windows):
            app.windows[k].destroy()
        r.update()
    rss1 = rss_mb()
    print('  (memoire apres avoir tout ouvert et ferme 3 fois : %.1f Mo)' % rss1)
    check(f'reste sous {RSS_MAX_MB:.0f} Mo apres usage', rss1 < RSS_MAX_MB, '%.1f Mo' % rss1)
    check('pas de fuite (moins de 8 Mo de plus qu\'au demarrage)', rss1 - rss0 < 8, '+%.1f Mo' % (rss1 - rss0))
