#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Orbit pour Linux (famille Debian) : version legere.

Python 3.9+ et Tkinter seulement (paquet python3-tk). Une seule petite fenetre reste
ouverte ; les autres (tableaux, notes...) sont creees a l'ouverture et detruites a la
fermeture pour rendre la memoire. Aucune animation continue : Orbit ne se redessine
que quand quelque chose change (chrono chaque seconde, yeux quand la souris bouge).

Lancement : python3 orbit.py      Donnees : ~/.local/share/orbit
"""
from __future__ import annotations

import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime

import tkinter as tk
from tkinter import filedialog, messagebox

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import orbit_core as C  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
INK, BG, CARD, ACCENT, SOFT, MUTED = '#1E1B3A', '#F4F2FF', '#FFFFFF', '#6C5CE7', '#EEEBFF', '#6B6787'
COLORS = {'calm': '#4C8DFF', 'mid': '#FFC93C', 'high': '#FF8A1C', 'final': '#FF4D4D', 'break': '#3DDC84', 'paused': '#8A8FA3'}
MOODS = {'Idle': '#5FD3FF', 'Focus': '#4C8DFF', 'Break': '#3DDC84', 'Await': '#FF9F1C'}
FONT = ('DejaVu Sans', 10)
FONT_B = ('DejaVu Sans', 10, 'bold')

# petites phrases sympas (pas de blagues ni de culture G)
LINES = {
    'hello': ['Salut ! On avance ensemble aujourd\'hui ?', 'Hello ! Prêt(e) quand tu l\'es.', 'Coucou ! Une chose à la fois, et ça ira.'],
    'focusStart': ['C\'est parti pour {0} min. Je veille sur toi.', 'Focus lancé : {0} min rien que pour ça.', 'Go ! {0} min, une seule chose.'],
    'motivation': ['Tu tiens le bon bout.', 'Une étape après l\'autre, c\'est parfait.', 'Respire, tu avances bien.',
                   'Ce que tu fais là compte.', 'Pas besoin d\'être parfait(e), juste d\'avancer.', 'Tu gères.'],
    'half': ['Déjà la moitié ! Encore {0} min.', 'Mi-parcours : {0} min et c\'est fini.'],
    'last': ['Dernière ligne droite, 5 min !', 'Plus que 5 minutes, tu y es presque.'],
    'focusEnd': ['Bravo, {0} min de focus ! Une pause ?', 'Focus terminé ({0} min). Tu l\'as bien mérité.'],
    'break': ['Lève-toi, étire-toi un peu.', 'Un verre d\'eau ? Ton cerveau dira merci.', 'Regarde au loin quelques secondes, tes yeux respirent.',
              'Quelques respirations lentes, ça fait du bien.', 'Bouge un peu les épaules, ça détend.', 'Profite, tu as bien bossé.'],
    'breakEnd': ['Pause finie ! On repart ?', 'Prêt(e) pour la suite ?'],
    'win': ['Bravo !', 'Une de plus !', 'Bien joué !', 'Yes !'],
}


def pick(key):
    return random.choice(LINES[key])


# ---------------------------------------------------------------------------
#  Sons : petits WAV fabriques par Orbit, joues par le lecteur du systeme (sans attendre)
# ---------------------------------------------------------------------------
class Sound:
    def __init__(self, app):
        self.app = app
        self.players = {k: shutil.which(k) for k in ('pw-play', 'paplay', 'aplay')}
        self.cache = {}
        self.dir = tempfile.mkdtemp(prefix='orbit-sons-', dir=os.environ.get('XDG_RUNTIME_DIR') or None)
        self.bag = C.SoundBag()
        self.played = []          # pour les tests

    def _wav(self, key, tones):
        vol = self.app.s.settings['volume']
        path = self.cache.get((key, vol))
        if not path:
            path = os.path.join(self.dir, '%s-%d.wav' % (key, vol))
            with open(path, 'wb') as f:
                f.write(C.make_wav(tones, vol))
            self.cache[(key, vol)] = path
        return path

    def play_file(self, path):
        self.played.append(os.path.basename(path))
        ext = os.path.splitext(path)[1].lower()
        order = ('pw-play', 'paplay', 'aplay') if ext == '.wav' else ('pw-play', 'paplay')
        for name in order:
            exe = self.players.get(name)
            if exe:
                try:
                    subprocess.Popen([exe, path], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL, close_fds=True)
                except OSError:
                    continue
                return True
        return False

    def ok(self):
        st = self.app.s.settings
        return st['sounds'] and st['volume'] > 0

    def chirp(self, question=False):
        st = self.app.s.settings
        if not self.ok() or st['bubbleSound'] == 'aucun':
            return
        if st['bubbleSound'] == 'mes-sons':
            mine = C.list_sounds(self.app.store.sounds)
            if mine:
                self.play_file(self.bag.pick(mine))
                return
        n = random.randint(0, 3)
        if question:
            self.play_file(self._wav('ask%d' % n, [(660 + 80 * n, 0.07, 0), (880, 0.16, 1175)]))
        else:
            self.play_file(self._wav('talk%d' % n, [(784 + 60 * n, 0.07, 0), (659, 0.08, 700)]))

    def chime(self):
        if self.ok():
            self.play_file(self._wav('chime', [(659, 0.25, 0), (784, 0.25, 0), (1046, 0.5, 0)]))

    def tick(self, high=False):
        if self.ok():
            self.play_file(self._wav('tick-hi' if high else 'tick', [(1568 if high else 1046, 0.045, 0)]))

    def success(self):
        if self.ok():
            self.play_file(self._wav('win', [(880, 0.1, 0), (1318, 0.3, 0)]))


def run_quiet(args, timeout=1.0):
    """Petit outil optionnel du systeme (xdotool, xprintidle) : jamais de shell, jamais bloquant longtemps."""
    if not shutil.which(args[0]):
        return ''
    try:
        return subprocess.run(args, stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout, text=True).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ''


# ---------------------------------------------------------------------------
#  L'application
# ---------------------------------------------------------------------------
class Orbit:
    W, H, BAR = 252, 116, 24

    def __init__(self, root: tk.Tk):
        self.root = root
        self.store = C.Store()
        self.s = self.store.load()
        self.rules = self._load_rules()
        self.sound = Sound(self)
        self.offset = 0.0                       # decalage d'horloge (tests automatiques)
        self.windows = {}                       # fenetres ouvertes (une seule de chaque)
        self.bubble_win = None
        self.bubble_after = None
        self.bubble_buttons = False
        self.sec_count = 0
        self.last_busy = time.time()
        self.next_tick = 0.0
        self.next_reminder = 0.0
        self.next_motivation = 0.0
        self.next_break_line = 0.0
        self.nudge_off = ''
        self.half_said = self.five_said = False
        self.level = ''
        self.pinned = False
        self.bar_on = False
        self.drag = None
        self.dirty = False
        self.nonbmp = self._test_nonbmp()
        mig = self.s.migrate_anchor()
        self.s.prune_reprises()
        self._build()
        self.save()
        self.place_home()
        self.root.after(1000, self.on_second)
        self.root.after(250, self.on_pointer)
        if mig:
            self.say("Le Brain Dump et la DopaList ont été retirés. Rien n'est perdu : %d idée(s) sont devenues des notes et %d action(s) des cartes."
                     % (mig['notes'], mig['cards']), seconds=12)
        elif self.store.notices:
            self.say('\n'.join(self.store.notices), seconds=12)
        elif self.s.timer['state'] == 'Idle':
            self.root.after(800, self.morning_or_hello)

    # --- utilitaires -----------------------------------------------------------
    def now(self):
        return time.time() + self.offset

    def _load_rules(self):
        for p in (os.path.join(HERE, 'unstick', 'rules.json'), os.path.join(HERE, '..', 'unstick', 'rules.json')):
            try:
                with open(p, encoding='utf-8') as f:
                    return json.load(f)
            except (OSError, ValueError):
                continue
        return {}

    def _test_nonbmp(self):
        try:
            lbl = tk.Label(self.root, text='\U0001F4DD')
            lbl.destroy()
            return True
        except tk.TclError:
            return False

    def t(self, text):
        """Texte sur pour Tk (anciennes versions : sans emoji hors du plan de base)."""
        text = str(text)
        return text if self.nonbmp else ''.join(c for c in text if ord(c) <= 0xFFFF)

    def save(self):
        try:
            self.store.save(self.s)
        except OSError as e:
            print('Orbit : enregistrement impossible :', e, file=sys.stderr)

    # --- construction de la petite fenetre ----------------------------------------
    def _build(self):
        r = self.root
        r.title('Orbit')
        r.overrideredirect(True)
        r.attributes('-topmost', True)
        r.configure(bg=INK)
        self.frame = tk.Frame(r, bg=BG, highlightthickness=2, highlightbackground=INK)
        self.frame.pack(fill='both', expand=True)
        self.dock = tk.Frame(self.frame, bg=BG)
        self.dock.place(x=6, y=6)
        self.dock_buttons = {}
        for i, (key, label, tip, cmd, bg) in enumerate((
                ('note', '✎', 'Note rapide', self.quick_note, ACCENT),
                ('ctx', '✋', "Je m'interromps", self.interrupt, CARD),
                ('sos', 'SOS', 'S.O.S : je bloque', self.sos, '#FFE3E3'),
                ('boards', '▦', 'Mes tableaux', self.open_boards, '#FFF4D6'),
                ('notes', '☰', 'Mes notes', self.open_notes, '#E6F7EE'),
                ('reprises', '↩', 'Mes reprises', self.open_reprises, '#E8F1FF'))):
            cell = tk.Frame(self.dock, width=50, height=32, bg=BG)     # taille fixe en pixels, quelle que soit la police
            cell.grid_propagate(False)
            cell.pack_propagate(False)
            cell.grid(row=i % 3, column=i // 3, padx=2, pady=2)
            b = tk.Button(cell, text=label, command=cmd, bg=bg, fg='white' if bg == ACCENT else INK, activebackground=SOFT,
                          relief='flat', bd=0, highlightthickness=1, highlightbackground=INK,
                          font=('DejaVu Sans', 8 if key == 'sos' else 12, 'bold'), cursor='hand2')
            b.pack(fill='both', expand=True)
            Tooltip(b, tip)
            self.dock_buttons[key] = b
        self.canvas = tk.Canvas(self.frame, width=128, height=104, bg=BG, highlightthickness=0, cursor='hand2')
        self.canvas.place(x=self.W - 132, y=4)
        self._draw_bot()
        self.bar = tk.Canvas(self.frame, width=self.W - 12, height=16, bg=BG, highlightthickness=0)
        self.bar_track = self.bar.create_rectangle(1, 1, self.W - 13, 15, outline=INK, width=1.5, fill=SOFT)
        self.bar_fill = self.bar.create_rectangle(2, 2, 2, 14, outline='', fill=COLORS['calm'])
        self.bar_text = self.bar.create_text((self.W - 12) // 2, 8, text='', font=('DejaVu Sans Mono', 8, 'bold'), fill=INK)
        for w in (self.canvas,):
            w.bind('<ButtonPress-1>', self.on_press)
            w.bind('<B1-Motion>', self.on_drag)
            w.bind('<ButtonRelease-1>', self.on_release)
            w.bind('<Button-3>', self.show_menu)
        self.frame.bind('<Button-3>', self.show_menu)
        self.update_dock()

    def _draw_bot(self):
        c = self.canvas
        c.create_oval(4, 52, 124, 86, outline='#C9C2FF', width=4)
        for x in (4, 92):
            c.create_rectangle(x, 34, x + 32, 56, fill='#4C8DFF', outline=INK, width=2)
        c.create_line(36, 45, 44, 45, fill=INK, width=3)
        c.create_line(84, 45, 92, 45, fill=INK, width=3)
        c.create_line(64, 20, 64, 8, fill=INK, width=3)
        self.beacon = c.create_oval(58, 2, 70, 14, fill=MOODS['Idle'], outline=INK, width=2)
        c.create_oval(36, 18, 92, 74, fill='#8C7CFF', outline=INK, width=3)
        c.create_rectangle(46, 32, 82, 50, fill='#14112B', outline='')
        self.eyes = [c.create_oval(51, 37, 59, 45, fill=MOODS['Idle'], outline=''),
                     c.create_oval(69, 37, 77, 45, fill=MOODS['Idle'], outline='')]
        self.eye_home = [(55, 41), (73, 41)]
        c.create_rectangle(40, 78, 88, 96, fill='#14112B', outline=MOODS['Idle'], width=2, tags='screen')
        self.clock = c.create_text(64, 87, text='▶ FOCUS', fill='#E8EEF5', font=('DejaVu Sans Mono', 8, 'bold'))

    def update_dock(self):
        st = self.s.settings
        if st['dock']:
            self.dock.place(x=6, y=6)
        else:
            self.dock.place_forget()
        focus = self.s.timer['state'] == 'Focus' and not self.s.timer['paused']
        self.dock_buttons['ctx'].configure(state='normal' if focus else 'disabled')
        n = len(self.s.open_reprises())
        self.dock_buttons['reprises'].configure(text='↩%d' % n if n else '↩')

    def show_bar(self, on):
        if on == self.bar_on:
            return
        self.bar_on = on
        if on:
            self.bar.place(x=6, y=self.H - 2)
        else:
            self.bar.place_forget()
        self.place_home(keep=True)

    def place_home(self, keep=False):
        h = self.H + (self.BAR if self.bar_on else 0)
        if keep and self.pinned:
            x, y = self.root.winfo_x(), self.root.winfo_y()
        else:
            x = self.root.winfo_screenwidth() - self.W - 24
            y = self.root.winfo_screenheight() - h - 64
        self.root.geometry('%dx%d+%d+%d' % (self.W, h, x, y))
        self.root.update_idletasks()
        if self.bubble_win:
            self.place_bubble()

    # --- deplacer, cliquer, menu ------------------------------------------------
    def on_press(self, e):
        self.drag = (e.x_root, e.y_root, self.root.winfo_x(), self.root.winfo_y(), False)

    def on_drag(self, e):
        if not self.drag:
            return
        x0, y0, wx, wy, _ = self.drag
        dx, dy = e.x_root - x0, e.y_root - y0
        if abs(dx) + abs(dy) > 4:
            self.drag = (x0, y0, wx, wy, True)
            self.root.geometry('+%d+%d' % (wx + dx, wy + dy))
            if self.bubble_win:
                self.place_bubble()

    def on_release(self, e):
        moved = self.drag and self.drag[4]
        self.drag = None
        if moved:
            self.pinned = True
            self.say('Ok, je reste ici.', [('Retourner en bas à droite', self.go_home)], seconds=8)
        else:
            self.status()

    def go_home(self):
        self.pinned = False
        self.place_home()

    def show_menu(self, e):
        m = tk.Menu(self.root, tearoff=0, font=FONT)
        st = self.s.timer
        if st['state'] != 'Focus':
            m.add_command(label='▶  Lancer un focus (%g min)' % C.rhythm_minutes(self.s.settings)[0], command=self.start_focus)
        if st['state'] in ('Focus', 'AwaitBreak'):
            m.add_command(label='☕  Prendre ma pause (%g min)' % C.rhythm_minutes(self.s.settings)[1], command=self.start_break)
        if st['state'] in ('Focus', 'Break'):
            m.add_command(label='▶  Reprendre le chrono' if st['paused'] else '⏸  Mettre le chrono en pause', command=self.toggle_pause)
        if st['state'] != 'Idle':
            m.add_command(label='■  Couper le chrono', command=self.stop)
        if self.pinned:
            m.add_command(label='⌂  Revenir en bas à droite', command=self.go_home)
        m.add_separator()
        m.add_command(label='✎  Note rapide', command=self.quick_note)
        m.add_command(label="✋  Je m'interromps", command=self.interrupt)
        m.add_command(label='⚠  S.O.S : je bloque', command=self.sos)
        m.add_separator()
        m.add_command(label='▦  Mes tableaux', command=self.open_boards)
        m.add_command(label='☰  Mes notes', command=self.open_notes)
        n = len(self.s.open_reprises())
        m.add_command(label='↩  Mes reprises' + (' (%d en attente)' % n if n else ''), command=self.open_reprises)
        m.add_separator()
        more = tk.Menu(m, tearoff=0, font=FONT)
        more.add_command(label='◎  Cartes du focus…', command=self.choose_focus_cards)
        more.add_command(label='☀  Plan du jour', command=lambda: self.morning_plan(True))
        more.add_command(label='★  Mes victoires du jour', command=self.show_wins)
        more.add_command(label='⌕  Rechercher partout…', command=self.open_search)
        more.add_separator()
        rh = tk.Menu(more, tearoff=0, font=FONT)
        self._rhythm_var = tk.StringVar(value=self.s.settings['rhythm'])
        for r in ('50/10', '25/5', 'Perso'):
            rh.add_radiobutton(label=r if r != 'Perso' else 'Perso (%g/%g)' % (self.s.settings['customFocus'], self.s.settings['customBreak']),
                               value=r, variable=self._rhythm_var, command=lambda r=r: self.set_rhythm(r))
        more.add_cascade(label='⏱  Rythme', menu=rh)
        more.add_command(label='⇩  Exporter (zip pour le PC / téléphone)…', command=self.export)
        more.add_command(label='⇧  Importer un export…', command=self.import_)
        more.add_command(label='♫  Ouvrir le dossier de mes sons', command=self.open_sounds_dir)
        m.add_cascade(label='☰  Plus', menu=more)
        m.add_command(label='⚙  Réglages…', command=self.open_settings)
        m.add_command(label='✕  Quitter Orbit', command=self.quit)
        try:
            m.tk_popup(e.x_root, e.y_root)
        finally:
            m.grab_release()

    def set_rhythm(self, r):
        self.s.settings['rhythm'] = r
        self.save()
        self.render()

    # --- bulle -----------------------------------------------------------------------
    def say(self, text, buttons=None, seconds=7, sound=True):
        self.hide_bubble()
        w = tk.Toplevel(self.root)
        w.overrideredirect(True)
        w.attributes('-topmost', True)
        w.configure(bg=INK)
        f = tk.Frame(w, bg=CARD, padx=12, pady=9)
        f.pack(padx=2, pady=2)
        tk.Label(f, text=self.t(text), bg=CARD, fg=INK, font=FONT, justify='left', wraplength=300).pack(anchor='w')
        if buttons:
            bf = tk.Frame(f, bg=CARD)
            bf.pack(anchor='w', pady=(8, 0))
            for i, (label, cmd) in enumerate(buttons):
                b = tk.Button(bf, text=self.t(label), bg=ACCENT if i == 0 else SOFT, fg='white' if i == 0 else INK, relief='flat',
                              font=FONT_B if i == 0 else FONT, cursor='hand2', padx=8, pady=2,
                              command=lambda c=cmd: (self.hide_bubble(), c()))
                b.grid(row=i // 2, column=i % 2, sticky='w', padx=(0, 6), pady=2)
        self.bubble_win = w
        self.bubble_buttons = bool(buttons)
        self.place_bubble()
        if seconds:
            self.bubble_after = self.root.after(int(seconds * 1000), self.hide_bubble)
        if sound:
            self.sound.chirp(bool(buttons) or str(text).rstrip().endswith('?'))

    def place_bubble(self):
        w = self.bubble_win
        w.update_idletasks()
        x = self.root.winfo_x() + self.W - w.winfo_reqwidth()
        y = self.root.winfo_y() - w.winfo_reqheight() - 6
        w.geometry('+%d+%d' % (max(0, x), max(0, y)))

    def hide_bubble(self):
        if self.bubble_after:
            self.root.after_cancel(self.bubble_after)
            self.bubble_after = None
        if self.bubble_win:
            self.bubble_win.destroy()
            self.bubble_win = None
        self.bubble_buttons = False

    def has_question(self):
        return bool(self.bubble_win and self.bubble_buttons)

    # --- chrono ------------------------------------------------------------------------
    def start_focus(self):
        self.s.start_focus(self.now())
        self.half_said = self.five_said = False
        self.next_motivation = self.now() + 9 * 60
        f = C.rhythm_minutes(self.s.settings)[0]
        msg = pick('focusStart').format('%g' % f)
        cards = self.s.focus_cards(True)
        if cards:
            msg += '\nObjectif : « %s »' % C.short_text(cards[0]['text'], 50)
            if len(cards) > 1:
                msg += ' (+%d)' % (len(cards) - 1)
        self.say(msg, seconds=6)
        self.after_change()

    def start_break(self):
        self.s.start_break(self.now())
        self.next_break_line = self.now() + 60
        self.say('Pause de %g min. %s' % (C.rhythm_minutes(self.s.settings)[1], pick('break')), seconds=8)
        self.after_change()

    def toggle_pause(self):
        if self.s.timer['paused']:
            self.s.resume(self.now())
        else:
            self.s.pause(self.now())
            self.say('Chrono en pause. Clic droit > Reprendre quand tu veux.', seconds=5)
        self.after_change()

    def stop(self):
        self.s.stop()
        self.say('Chrono coupé. Je reste là.', seconds=4)
        self.after_change()

    def after_change(self):
        self.save()
        self.render()
        self.update_dock()

    def on_timer_event(self, ev):
        self.sound.chime()
        if ev == 'focusEnded':
            self.last_busy = self.now()
            msg = pick('focusEnd').format('%g' % self.s.timer['sessionMin'])
            buttons = [('Je prends ma pause', self.start_break)]
            cards = self.s.focus_cards(True)
            if cards:
                msg += '\n« %s » : c\'est fait ?' % C.short_text(cards[0]['text'], 40)
                buttons.append(("C'est fait !", lambda c=cards[0]: self.card_done_then_break(c['id'])))
            buttons.append(('On arrête là', self.stop))
            self.say(msg, buttons, seconds=0)
        else:
            self.say(pick('breakEnd'), [('On repart !', self.start_focus), ('On arrête là', self.stop)], seconds=0)
        self.next_reminder = self.now() + self.s.settings['reminderEveryMin'] * 60
        self.after_change()

    def card_done_then_break(self, cid):
        self.s.set_card_done(cid)
        self.sound.success()
        self.start_break()

    def status(self):
        st = self.s.timer
        if self.has_question():
            return
        rep = self.s.open_reprises()
        if rep and st['state'] == 'Idle':
            self.offer_reprise(rep[0])
        elif st['state'] == 'Focus':
            self.say('Encore %d min de focus. %s' % (int(self.s.time_left(self.now()) // 60) + 1, pick('motivation')), seconds=5)
        elif st['state'] == 'Break':
            self.say('Encore %d min de pause, profite.' % (int(self.s.time_left(self.now()) // 60) + 1), seconds=5)
        elif st['state'] == 'AwaitBreak':
            self.on_timer_event('focusEnded')
        elif st['state'] == 'AwaitFocus':
            self.on_timer_event('breakEnded')
        else:
            self.say(pick('hello'), [('Lancer un focus', self.start_focus), ('Note rapide', self.quick_note), ('Je bloque', self.sos)], seconds=10)

    def on_second(self):
        try:
            self._second()
        except Exception as e:   # une erreur imprevue ne doit jamais arreter Orbit
            print('Orbit :', repr(e), file=sys.stderr)
        self.root.after(1000, self.on_second)

    def _second(self):
        now = self.now()
        ev = self.s.tick(now)
        if ev:
            self.on_timer_event(ev)
            return
        st = self.s.timer
        if st['state'] != 'Idle':
            self.last_busy = now
        left = self.s.time_left(now)
        # zone finale : tic qui s'accelere
        if self.s.settings['tickSound'] and st['state'] == 'Focus' and not st['paused']:
            iv = C.tick_interval(left, self.s.settings['tickZoneMin'] * 60)
            if not iv:
                self.next_tick = 0
            elif now >= self.next_tick:
                self.sound.tick(left <= 10)
                self.next_tick = now + iv - 0.1
        if st['state'] == 'Focus' and not st['paused']:
            total = st['sessionMin']
            if not self.half_said and total >= 20 and left <= total * 30:
                self.half_said = True
                self.say(random.choice(LINES['half']).format(int(left // 60) + 1))
            elif not self.five_said and total >= 15 and left <= 300:
                self.five_said = True
                self.say(pick('last'))
            elif self.s.settings['motivation'] and now >= self.next_motivation and not self.bubble_win:
                self.next_motivation = now + 9 * 60 + random.randint(-120, 120)
                self.say(pick('motivation'), seconds=5, sound=False)
        if st['state'] == 'Break' and not st['paused'] and self.s.settings['motivation'] and now >= self.next_break_line \
                and left > 20 and not self.bubble_win:
            self.next_break_line = now + 120
            self.say(pick('break'), seconds=8, sound=False)
        if st['state'] in ('AwaitBreak', 'AwaitFocus') and now >= self.next_reminder and not self.has_question():
            self.next_reminder = now + self.s.settings['reminderEveryMin'] * 60
            self.on_timer_event('focusEnded' if st['state'] == 'AwaitBreak' else 'breakEnded')
        self.sec_count += 1
        if self.sec_count % 15 == 0:
            self.check_idle_pause()
            self.check_reprise_reminder()
            self.check_idle_nudge()
            self.check_card_reminders()
        self.render()

    def render(self):
        st = self.s.timer
        now = self.now()
        left = self.s.time_left(now)
        if st['state'] in ('Focus', 'Break'):
            txt = ('⏸' if st['paused'] else '☕' if st['state'] == 'Break' else '') + C.fmt_clock(left)
            mood = 'Focus' if st['state'] == 'Focus' else 'Break'
        elif st['state'] == 'AwaitBreak':
            txt, mood = '☕ ?', 'Await'
        elif st['state'] == 'AwaitFocus':
            txt, mood = '▶ ?', 'Await'
        else:
            txt, mood = '▶ FOCUS', 'Idle'
        c = self.canvas
        c.itemconfigure(self.clock, text=txt)
        c.itemconfigure(self.beacon, fill=MOODS[mood])
        for e in self.eyes:
            c.itemconfigure(e, fill=MOODS[mood])
        c.itemconfigure('screen', outline=MOODS[mood])
        # barre de compte a rebours
        show = self.s.settings['urgencyBar'] and st['state'] in ('Focus', 'Break')
        self.show_bar(show)
        if show:
            total = max(1, st['sessionMin']) * 60
            frac = min(1.0, max(0.0, left / total))
            lvl = 'paused' if st['paused'] else 'break' if st['state'] == 'Break' else C.urgency_level(frac, left)
            shown = min(1.0, left / 60) if lvl == 'final' else frac   # derniere minute : la barre « zoome » sur 60 s
            w = self.W - 14
            self.bar.coords(self.bar_fill, 2, 2, 2 + max(3, w * shown), 14)
            self.bar.itemconfigure(self.bar_fill, fill=COLORS[lvl])
            self.bar.itemconfigure(self.bar_text, text=('⏸ ' if st['paused'] else '') + C.fmt_clock(left))
            if lvl == 'final' and self.level != 'final':
                self.root.after(120, self.pulse)
            self.level = lvl
        else:
            self.level = ''

    def pulse(self):
        """Derniere minute : la barre clignote doucement, de plus en plus vite (seulement a ce moment-la)."""
        if self.level != 'final':
            self.bar.itemconfigure(self.bar_track, fill=SOFT)
            return
        left = max(1.0, self.s.time_left(self.now()))
        on = int(time.time() * (2 + 30 / left)) % 2 == 0
        self.bar.itemconfigure(self.bar_track, fill='#FFD6D6' if on else SOFT)
        self.root.after(150, self.pulse)

    def on_pointer(self):
        """Les yeux suivent la souris (4 fois par seconde, seulement si elle a bouge)."""
        try:
            px, py = self.root.winfo_pointerxy()
            if (px, py) != getattr(self, '_last_ptr', None):
                self._last_ptr = (px, py)
                ox, oy = self.canvas.winfo_rootx(), self.canvas.winfo_rooty()
                for eye, (hx, hy) in zip(self.eyes, self.eye_home):
                    dx, dy = px - (ox + hx), py - (oy + hy)
                    d = max(1.0, (dx * dx + dy * dy) ** 0.5)
                    ex, ey = hx + 2.5 * dx / d, hy + 2.0 * dy / d
                    self.canvas.coords(eye, ex - 4, ey - 4, ex + 4, ey + 4)
        except tk.TclError:
            pass
        self.root.after(250, self.on_pointer)

    def idle_seconds(self):
        out = run_quiet(['xprintidle'], 0.5)
        return int(out) / 1000 if out.isdigit() else 0

    def check_idle_pause(self):
        st = self.s.timer
        if not self.s.settings['idlePause'] or st['state'] != 'Focus' or st['paused']:
            return
        idle = self.idle_seconds()
        if idle >= self.s.settings['idlePauseMin'] * 60:
            self.s.pause(self.now() - idle)      # le temps d'absence ne compte pas
            self.away_since = self.now() - idle
            self.after_change()

    def check_reprise_reminder(self):
        c = self.s.due_reprise(datetime.fromtimestamp(self.now()))
        if c and not self.has_question() and self.s.timer['state'] != 'Focus':
            c['reminders'] += 1
            c['remindAt'] = C.iso_local(datetime.fromtimestamp(self.now() + self.s.settings['ctxRemindMin'] * 60))
            self.save()
            self.offer_reprise(c)

    def check_card_reminders(self):
        iso = C.iso_local(datetime.fromtimestamp(self.now()))
        for t in self.s.open_cards():
            if t['remindAt'] and not t['reminded'] and t['remindAt'] <= iso:
                t['reminded'] = True
                self.save()
                self.say('Rappel : « %s »' % C.short_text(t['text'], 60), [('Focus dessus', lambda i=t['id']: self.focus_on(i)), ('Ok', lambda: None)], seconds=0)
                return

    # --- relance « Tu attends quoi ? » ---------------------------------------------------
    def check_idle_nudge(self):
        now = self.now()
        if not C.idle_nudge_due(self.s.settings, self.s.timer['state'], self.last_busy, now, self.nudge_off):
            return
        if self.has_question() or self.idle_seconds() > 120:
            return
        self.last_busy = now
        plan = self.s.plan_cards(3)
        if not plan:
            return
        text = random.choice(["Tiens ! Ça fait un moment qu'on n'a pas lancé de focus.", 'Psst… tes tâches t\'attendent.',
                              'Hé, on se lance ? Il y a du monde qui attend.']) + \
            "\nTu as des tâches en cours, qu'est-ce que tu attends ? Je te propose :"
        for i, p in enumerate(plan):
            text += '\n%d. « %s »%s' % (i + 1, C.short_text(p['card']['text'], 45), ' (%s)' % p['why'] if p['why'] else '')
        text += "\nOn lance un focus sur l'une d'elles ?"
        buttons = [('%d. %s' % (i + 1, C.short_text(p['card']['text'], 22)), lambda c=p['card']['id']: self.focus_on(c)) for i, p in enumerate(plan)]
        buttons += [('Plus tard', self._nudge_later), ("Pas aujourd'hui", self._nudge_off)]
        self.say(text, buttons, seconds=300)

    def _nudge_later(self):
        self.last_busy = self.now()

    def _nudge_off(self):
        self.nudge_off = C.day_string(datetime.fromtimestamp(self.now()))
        self.say("Ok, je ne te relance plus aujourd'hui.", seconds=4)

    def focus_on(self, cid):
        if not self.s.card(cid):
            self.say("Cette carte n'existe plus.", seconds=4)
            return
        self.s.kanban['focus'] = [cid]
        self.start_focus()

    # --- plan du matin -----------------------------------------------------------------
    def morning_or_hello(self):
        today = C.day_string()
        if self.s.settings['morningPlan'] and self.s.stats['planDay'] != today and datetime.now().hour >= 5:
            self.morning_plan(False)
        else:
            rep = self.s.open_reprises()
            if rep:
                self.offer_reprise(rep[0])
            else:
                self.say(pick('hello'), seconds=6, sound=False)

    def morning_plan(self, manual=True):
        self.s.stats['planDay'] = C.day_string()
        self.save()
        plan = self.s.plan_cards(3)
        hello = 'Bonjour !' if datetime.now().hour < 12 else 'Re-bonjour !'
        if not plan:
            self.say('%s Tes tableaux sont vides : note tes tâches et je t\'aiderai à les attaquer dans le bon ordre.' % hello,
                     [('Mes tableaux', self.open_boards), ('Focus quand même', self.start_focus)], seconds=60)
            return
        text = hello + ' Mon plan pour ta journée :'
        for i, p in enumerate(plan):
            text += '\n%d. P%d « %s »%s' % (i + 1, p['card']['prio'], C.short_text(p['card']['text'], 45), '\n     ' + p['why'] if p['why'] else '')
        rep = self.s.open_reprises()
        if rep:
            text = 'Tu t\'étais arrêté(e) %s sur « %s ».\n\n' % (C.format_ago(rep[0]['created']), C.reprise_title(rep[0], 50)) + text
        self.say(text + "\n\nOn s'y met ?", [('Go, focus sur ces cartes', lambda: self._accept_plan(plan)),
                                               ('Choisir autre chose', self.choose_focus_cards), ('Plus tard', lambda: None)],
                 seconds=0 if manual else 180)

    def _accept_plan(self, plan):
        self.s.kanban['focus'] = [p['card']['id'] for p in plan]
        self.start_focus()

    # --- note rapide -----------------------------------------------------------------------
    def quick_note(self):
        def build(w, body):
            txt = tk.Text(body, width=40, height=7, font=FONT, wrap='word', bg='#FFF8C5', relief='flat', padx=8, pady=6)
            txt.pack(fill='both', expand=True)
            txt.focus_set()

            def done(_=None):
                v = txt.get('1.0', 'end').strip()
                if v and self.s.add_note(v):
                    self.save()
                    self.say('Noté ! Tu la retrouves dans ☰ Mes notes.', seconds=3)
                w.destroy()
                return 'break'
            txt.bind('<Return>', done)
            txt.bind('<Shift-Return>', lambda e: None)
            txt.bind('<Escape>', done)
            row = tk.Frame(body, bg=BG)
            row.pack(fill='x', pady=(6, 0))
            btn(row, 'OK', done, primary=True).pack(side='right')
            tk.Label(row, text='Entrée = garder · Maj+Entrée = nouvelle ligne', bg=BG, fg=MUTED, font=('DejaVu Sans', 8)).pack(side='left')
            w.protocol('WM_DELETE_WINDOW', done)
        self.open_window('note', 'Note rapide', build)

    # --- je m'interromps ------------------------------------------------------------------------
    def interrupt(self):
        title = run_quiet(['xdotool', 'getactivewindow', 'getwindowname'])
        app = ''
        pid = run_quiet(['xdotool', 'getactivewindow', 'getwindowpid'])
        if pid.isdigit():
            try:
                with open('/proc/%s/comm' % pid, encoding='utf-8') as f:
                    app = f.read().strip()
            except OSError:
                app = ''
        if re.search(r'(?i)navigation priv|private brows|incognito|inprivate', title):
            title = ''                               # fenetres privees : jamais lues
        paused_here = self.s.timer['state'] == 'Focus' and not self.s.timer['paused']
        if paused_here:
            self.s.pause(self.now())
            self.after_change()
        suggestion = next((ck['text'] for t in self.s.focus_cards(True) for ck in t['checks'] if not ck['done']), '')

        def build(w, body):
            tk.Label(body, text=self.t('Fenêtre gardée : %s' % (C.short_text(title, 60) if title else '(aucune)')), bg=BG, fg=MUTED,
                     font=('DejaVu Sans', 9)).pack(anchor='w')
            tk.Label(body, text="J'étais en train de…", bg=BG, fg=INK, font=FONT_B).pack(anchor='w', pady=(8, 0))
            doing = tk.Entry(body, width=46, font=FONT)
            doing.pack(fill='x')
            tk.Label(body, text='Prochaine étape exacte', bg=BG, fg=INK, font=FONT_B).pack(anchor='w', pady=(8, 0))
            nxt = tk.Entry(body, width=46, font=FONT)
            nxt.pack(fill='x')
            nxt.insert(0, suggestion)
            doing.focus_set()

            def save(_=None):
                c = self.s.add_reprise(doing.get().strip(), nxt.get().strip(), title=title, app=app, now=datetime.fromtimestamp(self.now()))
                self.save()
                w.destroy()
                self.say("C'est noté, je garde où tu en es.%s\nQuand tu reviens, clique sur moi.%s"
                         % ('\n→ ' + C.short_text(c['next'], 80) if c['next'] else '', '\nFocus en pause.' if paused_here else ''), seconds=8)
                self.update_dock()
            for e in (doing, nxt):
                e.bind('<Return>', save)
            row = tk.Frame(body, bg=BG)
            row.pack(fill='x', pady=(10, 0))
            btn(row, 'Enregistrer', save, primary=True).pack(side='right')
            w.protocol('WM_DELETE_WINDOW', save)      # fermer = garder quand meme (c'est le principe d'une interruption)
        self.open_window('interrupt', "Je m'interromps", build)

    def offer_reprise(self, c):
        lines = ['Tu t\'étais arrêté(e) %s sur « %s ».' % (C.format_ago(c['created']), C.reprise_title(c, 60))]
        if c['doing']:
            lines.append("J'étais en train de : " + C.short_text(c['doing'], 80))
        if c['next'] and c['doing']:
            lines.append('Prochaine étape : ' + C.short_text(c['next'], 80))
        self.say('\n'.join(lines), [('Reprendre', lambda: self.resume_reprise(c['id'])), ('Plus tard', lambda: None),
                                    ('En carte', lambda: self.reprise_to_card(c['id'])), ('Déjà fait', lambda: self.reprise_done(c['id']))], seconds=0)

    def resume_reprise(self, rid):
        c = next((x for x in self.s.reprises if x['id'] == rid), None)
        if not c:
            return
        self.s.complete_reprise(rid)
        if c['wasFocus'] and self.s.timer['state'] == 'Focus' and self.s.timer['paused']:
            self.s.resume(self.now())
        self.after_change()
        self.say('On reprend !' + ('\n→ ' + C.short_text(c['next'], 80) if c['next'] else ''), seconds=8)

    def reprise_done(self, rid):
        self.s.complete_reprise(rid)
        self.after_change()

    def reprise_to_card(self, rid):
        c = next((x for x in self.s.reprises if x['id'] == rid), None)
        if not c:
            return
        card = self.s.add_card(C.reprise_title(c, 140))
        if card:
            card['desc'] = C.clean_text('\n'.join(x for x in ("J'étais en train de : " + c['doing'] if c['doing'] else '',
                                                              'Fenêtre : ' + c['windows'][0]['title'] if c['windows'] else '') if x), C.LIMITS['long'])
        self.s.complete_reprise(rid)
        self.after_change()
        self.say('Ajoutée à ton tableau.', seconds=3)

    # --- S.O.S ---------------------------------------------------------------------------------
    def sos(self):
        if self.s.anchor['unstick']:
            self.open_runner()
            return
        ideas = [t['text'] for t in self.s.focus_cards(True)] + [p['card']['text'] for p in self.s.plan_cards(4)]
        ideas = list(dict.fromkeys(ideas))[:4]

        def build(w, body):
            tk.Label(body, text="Qu'est-ce que tu n'arrives pas à commencer ?", bg=BG, fg=INK, font=('DejaVu Sans', 12, 'bold')).pack(anchor='w')
            tk.Label(body, text='Je le découpe en micro-étapes ridiculement petites. Tu ne verras que la première.',
                     bg=BG, fg=MUTED, font=('DejaVu Sans', 9), wraplength=380, justify='left').pack(anchor='w', pady=(2, 8))
            e = tk.Entry(body, width=44, font=FONT)
            e.pack(fill='x')
            e.focus_set()

            def go(_=None, text=None):
                v = (text or e.get()).strip()
                if v and self.s.start_unstick(v, self.rules):
                    self.save()
                    w.destroy()
                    self.open_runner()
            e.bind('<Return>', go)
            btn(body, 'Découper', go, primary=True).pack(anchor='e', pady=(8, 0))
            if ideas:
                tk.Label(body, text='Ou bien :', bg=BG, fg=MUTED, font=('DejaVu Sans', 9)).pack(anchor='w', pady=(6, 0))
                for i in ideas:
                    btn(body, self.t(C.short_text(i, 40)), lambda i=i: go(text=i)).pack(anchor='w', pady=1)
        self.open_window('sos', 'S.O.S déblocage', build)

    def open_runner(self):
        def build(w, body):
            self._runner_body = body
            self._runner_win = w
            self.render_runner()
        self.open_window('runner', 'Une seule chose à la fois', build, rebuild=True)

    def render_runner(self):
        body = self._runner_body
        for ch in body.winfo_children():
            ch.destroy()
        u = self.s.anchor['unstick']
        if not u:
            tk.Label(body, text='Tu es lancé(e) ! Victoire notée.', bg=BG, fg=INK, font=('DejaVu Sans', 13, 'bold')).pack(pady=10)
            btn(body, 'Mes victoires', lambda: (self._runner_win.destroy(), self.show_wins())).pack()
            return
        step = u['steps'][u['index']]
        tk.Label(body, text=self.t('Étape %d sur %d · %s' % (u['index'] + 1, len(u['steps']), C.short_text(u['title'], 40))),
                 bg=BG, fg=MUTED, font=('DejaVu Sans', 9)).pack(anchor='w')
        tk.Label(body, text=self.t(step['content']), bg=BG, fg=INK, font=('DejaVu Sans', 13, 'bold'), wraplength=380,
                 justify='left').pack(anchor='w', pady=(6, 12))
        row = tk.Frame(body, bg=BG)
        row.pack(fill='x')

        def done():
            r = self.s.unstick_step_done()
            if r == 'finished':
                self.sound.success()
            self.save()
            self.render_runner()

        def smaller():
            self.s.unstick_smaller()
            self.save()
            self.render_runner()
        btn(row, "C'est fait !", done, primary=True).pack(side='left')
        btn(row, 'Plus petit', smaller).pack(side='left', padx=6)
        btn(row, 'Plus tard', self._runner_win.destroy).pack(side='right')

    # --- fenetres ---------------------------------------------------------------------------
    def open_window(self, key, title, build, rebuild=False):
        w = self.windows.get(key)
        if w is not None and w.winfo_exists():
            if not rebuild:
                w.deiconify()
                w.lift()
                return w
            w.destroy()
        w = tk.Toplevel(self.root)
        w.title('Orbit · ' + title)
        w.configure(bg=BG)
        w.attributes('-topmost', True)
        body = tk.Frame(w, bg=BG, padx=14, pady=12)
        body.pack(fill='both', expand=True)
        self.windows[key] = w
        w.bind('<Destroy>', lambda e, k=key: self.windows.pop(k, None) if e.widget is w else None)
        build(w, body)
        w.update_idletasks()
        x = max(0, self.root.winfo_x() + self.W - w.winfo_reqwidth())
        y = max(0, self.root.winfo_y() - w.winfo_reqheight() - 40)
        w.geometry('+%d+%d' % (x, y))
        return w

    def open_boards(self):
        def build(w, body):
            self._boards_body = body
            self._boards_win = w
            self.render_boards()
        self.open_window('boards', 'Mes tableaux', build)

    def render_boards(self):
        body = self._boards_body
        for ch in body.winfo_children():
            ch.destroy()
        b = self.s.current_board()
        top = tk.Frame(body, bg=BG)
        top.pack(fill='x')
        names = [x['name'] for x in self.s.kanban['boards']]
        var = tk.StringVar(value=b['name'])

        def switch(name):
            nb = next(x for x in self.s.kanban['boards'] if x['name'] == name)
            self.s.kanban['current'] = nb['id']
            self.save()
            self.render_boards()
        om = tk.OptionMenu(top, var, *names, command=switch)
        om.configure(font=FONT_B, bg=CARD, relief='flat', highlightthickness=0)
        om.pack(side='left')
        btn(top, '+ Tableau', self.new_board).pack(side='left', padx=6)
        add = tk.Entry(top, width=30, font=FONT)
        add.pack(side='left', padx=(12, 4))
        add.insert(0, '')

        def add_card(_=None):
            if self.s.add_card(add.get()):
                self.save()
                self.render_boards()
        add.bind('<Return>', add_card)
        btn(top, 'Ajouter', add_card, primary=True).pack(side='left')
        tk.Label(body, text='Astuce : « !2 » = priorité 2, « @14h » = rappel. Double-clic = modifier.', bg=BG, fg=MUTED,
                 font=('DejaVu Sans', 8)).pack(anchor='w', pady=(4, 6))
        cols = tk.Frame(body, bg=BG)
        cols.pack(fill='both', expand=True)
        self._lists = {}
        for i, col in enumerate(b['columns']):
            f = tk.Frame(cols, bg=SOFT, padx=6, pady=6)
            f.grid(row=0, column=i, sticky='nsew', padx=3)
            cols.grid_columnconfigure(i, weight=1)
            cards = self.s.column_cards(col['id'])
            tk.Label(f, text=self.t('%s%s (%d)' % ('✓ ' if col['done'] else '', col['name'], len(cards))), bg=SOFT, fg=INK,
                     font=FONT_B).pack(anchor='w')
            lb = tk.Listbox(f, width=26, height=12, font=FONT, activestyle='none', selectbackground=ACCENT, relief='flat',
                            highlightthickness=0, exportselection=False)
            lb.pack(fill='both', expand=True)
            for t in cards:
                lb.insert('end', self.t('%sP%d %s%s' % ('◎ ' if t['id'] in self.s.kanban['focus'] else '', t['prio'], t['text'],
                                                       '  · ' + C.format_due(t['due']) if t['due'] else '')))
            lb.ids = [t['id'] for t in cards]
            lb.bind('<Double-Button-1>', lambda e, lb=lb: self.edit_selected(lb))
            self._lists[col['id']] = lb
        acts = tk.Frame(body, bg=BG)
        acts.pack(fill='x', pady=(8, 0))
        for label, fn in (('◀', lambda: self._act(lambda c: self.s.shift_card(c, -1))), ('▶', lambda: self._act(lambda c: self.s.shift_card(c, 1))),
                          ('✓ Fait', lambda: self._act(lambda c: self.s.set_card_done(c))),
                          ('◎ Focus', lambda: self._act(self._toggle_focus)),
                          ('Modifier', lambda: self._act(self._edit_card, save=False)),
                          ('Supprimer', lambda: self._act(self._delete_card))):
            btn(acts, label, fn).pack(side='left', padx=2)

    def _selected(self):
        for lb in self._lists.values():
            sel = lb.curselection()
            if sel:
                return lb.ids[sel[0]]
        return None

    def _act(self, fn, save=True):
        cid = self._selected()
        if not cid:
            return
        fn(cid)
        if save:
            self.save()
            self.render_boards()

    def _toggle_focus(self, cid):
        f = self.s.kanban['focus']
        if cid in f:
            f.remove(cid)
        elif not self.s.card(cid)['done']:
            f.append(cid)

    def _delete_card(self, cid):
        t = self.s.card(cid)
        if t and messagebox.askyesno('Orbit', 'Supprimer « %s » ?' % C.short_text(t['text'], 50), parent=self._boards_win):
            self.s.remove_card(cid)

    def edit_selected(self, lb):
        sel = lb.curselection()
        if sel:
            self._edit_card(lb.ids[sel[0]])

    def _edit_card(self, cid):
        t = self.s.card(cid)
        if not t:
            return

        def build(w, body):
            tk.Label(body, text='Titre', bg=BG, font=FONT_B).grid(row=0, column=0, sticky='w')
            title = tk.Entry(body, width=44, font=FONT)
            title.insert(0, t['text'])
            title.grid(row=0, column=1, sticky='we')
            tk.Label(body, text='Priorité (1-10)', bg=BG, font=FONT_B).grid(row=1, column=0, sticky='w')
            prio = tk.Spinbox(body, from_=1, to=10, width=4, font=FONT)
            prio.delete(0, 'end')
            prio.insert(0, t['prio'])
            prio.grid(row=1, column=1, sticky='w')
            tk.Label(body, text='Échéance (AAAA-MM-JJ)', bg=BG, font=FONT_B).grid(row=2, column=0, sticky='w')
            due = tk.Entry(body, width=12, font=FONT)
            due.insert(0, t['due'])
            due.grid(row=2, column=1, sticky='w')
            tk.Label(body, text='Description', bg=BG, font=FONT_B).grid(row=3, column=0, sticky='nw')
            desc = tk.Text(body, width=44, height=6, font=FONT, wrap='word')
            desc.insert('1.0', t['desc'])
            desc.grid(row=3, column=1, sticky='we')

            def ok():
                t['text'] = C.clean_text(title.get()) or t['text']
                t['prio'] = C.limit_prio(prio.get())
                t['due'] = C.day_or_empty(due.get().strip())
                t['desc'] = C.clean_text(desc.get('1.0', 'end').strip(), C.LIMITS['long'])
                self.save()
                w.destroy()
                if 'boards' in self.windows:
                    self.render_boards()
            btn(body, 'OK', ok, primary=True).grid(row=4, column=1, sticky='e', pady=(8, 0))
        self.open_window('card', 'Carte', build, rebuild=True)

    def new_board(self):
        def build(w, body):
            e = tk.Entry(body, width=30, font=FONT)
            e.pack()
            e.focus_set()

            def ok(_=None):
                name = C.clean_text(e.get(), 60).strip()
                if name and len(self.s.kanban['boards']) < C.LIMITS['boards']:
                    b = C.new_board(name)
                    self.s.kanban['boards'].append(b)
                    self.s.kanban['current'] = b['id']
                    self.save()
                    self.render_boards()
                w.destroy()
            e.bind('<Return>', ok)
            btn(body, 'Créer', ok, primary=True).pack(pady=(6, 0))
        self.open_window('newboard', 'Nouveau tableau', build, rebuild=True)

    def choose_focus_cards(self):
        plan = self.s.plan_cards(60)

        def build(w, body):
            if not plan:
                tk.Label(body, text='Aucune carte ouverte. Ajoute-en dans ▦ Mes tableaux.', bg=BG).pack()
                return
            vars_ = []
            for p in plan:
                v = tk.BooleanVar(value=p['card']['id'] in self.s.kanban['focus'])
                tk.Checkbutton(body, text=self.t('P%d %s%s' % (p['card']['prio'], C.short_text(p['card']['text'], 50), ' · ' + p['why'] if p['why'] else '')),
                               variable=v, bg=BG, anchor='w', font=FONT).pack(fill='x')
                vars_.append((p['card']['id'], v))

            def ok(start=False):
                self.s.kanban['focus'] = [cid for cid, v in vars_ if v.get()]
                self.save()
                w.destroy()
                if start:
                    self.start_focus()
            row = tk.Frame(body, bg=BG)
            row.pack(fill='x', pady=(8, 0))
            btn(row, 'Lancer le focus', lambda: ok(True), primary=True).pack(side='right')
            btn(row, 'Enregistrer', ok).pack(side='right', padx=6)
        self.open_window('focuscards', 'Cartes du focus', build, rebuild=True)

    def open_notes(self):
        def build(w, body):
            self._notes_body = body
            self.render_notes()
        self.open_window('notes', 'Mes notes', build)

    def render_notes(self):
        body = self._notes_body
        for ch in body.winfo_children():
            ch.destroy()
        top = tk.Frame(body, bg=BG)
        top.pack(fill='x')
        btn(top, '+ Nouvelle', self.quick_note, primary=True).pack(side='left')
        lb = tk.Listbox(body, width=60, height=14, font=FONT, activestyle='none', selectbackground=ACCENT, relief='flat')
        lb.pack(fill='both', expand=True, pady=6)
        notes = self.s.sorted_notes()
        for n in notes:
            lb.insert('end', self.t(('★ ' if n['pinned'] else '') + C.note_title(n, 70)))
        txt = tk.Text(body, width=60, height=8, font=FONT, wrap='word', bg='#FFF8C5', relief='flat')
        txt.pack(fill='both', expand=True)
        state = {'id': None}

        def show(_=None):
            sel = lb.curselection()
            if sel:
                commit()
                n = notes[sel[0]]
                state['id'] = n['id']
                txt.delete('1.0', 'end')
                txt.insert('1.0', self.t(n['text']))

        def commit(_=None):
            if state['id']:
                self.s.update_note(state['id'], txt.get('1.0', 'end'))
                self.save()

        def pin():
            n = next((x for x in self.s.notes if x['id'] == state['id']), None)
            if n:
                n['pinned'] = not n['pinned']
                self.save()
                self.render_notes()

        def to_card():
            if state['id']:
                commit()
                n = next((x for x in self.s.notes if x['id'] == state['id']), None)
                if n:
                    lines = [x for x in n['text'].split('\n')]
                    card = self.s.add_card(next((x for x in lines if x.strip()), 'Note'))
                    if card:
                        card['desc'] = C.clean_text('\n'.join(lines[1:]).strip(), C.LIMITS['long'])
                        self.s.notes = [x for x in self.s.notes if x['id'] != n['id']]
                    self.save()
                    self.render_notes()
        lb.bind('<<ListboxSelect>>', show)
        txt.bind('<FocusOut>', commit)
        acts = tk.Frame(body, bg=BG)
        acts.pack(fill='x', pady=(6, 0))
        btn(acts, 'Enregistrer', lambda: (commit(), self.render_notes())).pack(side='left')
        btn(acts, '★ Épingler', pin).pack(side='left', padx=4)
        btn(acts, '▦ En carte', to_card).pack(side='left')

    def open_reprises(self):
        def build(w, body):
            reps = self.s.open_reprises()
            if not reps:
                tk.Label(body, text="Aucune reprise en attente. Quand on t'interrompt : bouton ✋.", bg=BG).pack()
            for c in reps:
                f = tk.Frame(body, bg=CARD, padx=8, pady=6, highlightthickness=1, highlightbackground=SOFT)
                f.pack(fill='x', pady=3)
                tk.Label(f, text=self.t('%s · %s' % (C.reprise_title(c, 60), C.format_ago(c['created']))), bg=CARD, font=FONT_B).pack(anchor='w')
                if c['doing']:
                    tk.Label(f, text=self.t("J'étais en train de : " + C.short_text(c['doing'], 80)), bg=CARD, fg=MUTED).pack(anchor='w')
                row = tk.Frame(f, bg=CARD)
                row.pack(anchor='w', pady=(4, 0))
                btn(row, 'Reprendre', lambda i=c['id']: (w.destroy(), self.resume_reprise(i)), primary=True).pack(side='left')
                btn(row, 'En carte', lambda i=c['id']: (w.destroy(), self.reprise_to_card(i))).pack(side='left', padx=4)
                btn(row, 'Déjà fait', lambda i=c['id']: (w.destroy(), self.reprise_done(i))).pack(side='left')
        self.open_window('reprises', 'Mes reprises', build, rebuild=True)

    def show_wins(self):
        wins = self.s.wins_of_day()
        streak = self.s.win_streak()
        icons = {'focus': '●', 'card': '▦', 'unstick': '⚡', 'reprise': '↩'}
        if not wins:
            text = 'La journée commence : chaque petite chose faite (focus, carte finie, déblocage…) sera notée ici.'
        else:
            text = "Aujourd'hui : %d victoire%s%s" % (len(wins), 's' if len(wins) > 1 else '', '  ·  %d jours d\'affilée' % streak if streak >= 2 else '')
            for w in wins[:12]:
                text += '\n%s %s' % (icons.get(w['kind'], '✓'), C.short_text(w['title'], 50))
            if len(wins) > 12:
                text += '\n… et %d autre(s)' % (len(wins) - 12)
        self.say('Focus aujourd\'hui : %d session(s), %g min.\n\n%s' % (self.s.stats['focus'], self.s.stats['minutes'], text), seconds=15)

    def open_search(self):
        def build(w, body):
            e = tk.Entry(body, width=50, font=FONT)
            e.pack(fill='x')
            e.focus_set()
            lb = tk.Listbox(body, width=70, height=14, font=FONT, relief='flat')
            lb.pack(fill='both', expand=True, pady=6)

            def run(_=None):
                lb.delete(0, 'end')
                r = self.s.search(e.get())
                for t in r['cards']:
                    lb.insert('end', self.t('▦ %s%s' % ('✓ ' if t['done'] else '', t['text'])))
                for n in r['notes']:
                    lb.insert('end', self.t('☰ ' + C.note_title(n, 70)))
                for c in r['reprises']:
                    lb.insert('end', self.t('↩ ' + C.reprise_title(c, 70)))
                if not lb.size():
                    lb.insert('end', 'Rien trouvé.' if e.get().strip() else 'Plusieurs mots : ils doivent tous y être.')
            e.bind('<KeyRelease>', run)
            run()
        self.open_window('search', 'Rechercher partout', build)

    # --- reglages ---------------------------------------------------------------------------
    def open_settings(self):
        st = self.s.settings

        def build(w, body):
            vals = {}

            def row(label, key, kind='bool', lo=None, hi=None):
                f = tk.Frame(body, bg=BG)
                f.pack(fill='x', pady=1)
                if kind == 'bool':
                    v = tk.BooleanVar(value=st[key])
                    tk.Checkbutton(f, text=label, variable=v, bg=BG, font=FONT, anchor='w').pack(side='left')
                else:
                    tk.Label(f, text=label, bg=BG, font=FONT).pack(side='left')
                    v = tk.StringVar(value=str(st[key]))
                    tk.Spinbox(f, from_=lo, to=hi, textvariable=v, width=5, font=FONT).pack(side='left', padx=4)
                vals[key] = (v, kind, lo, hi)

            def section(t):
                tk.Label(body, text=t, bg=BG, fg=ACCENT, font=FONT_B).pack(anchor='w', pady=(8, 2))
            section('Rythme')
            rv = tk.StringVar(value=st['rhythm'])
            f = tk.Frame(body, bg=BG)
            f.pack(fill='x')
            for r in ('50/10', '25/5', 'Perso'):
                tk.Radiobutton(f, text=r, value=r, variable=rv, bg=BG, font=FONT).pack(side='left')
            row('Focus perso (min)', 'customFocus', 'num', 1, 240)
            row('Pause perso (min)', 'customBreak', 'num', 1, 120)
            section('Compte à rebours')
            row('Barre qui se vide et change de couleur', 'urgencyBar')
            row("Tic doux qui s'accélère à la fin du focus", 'tickSound')
            row('… pendant les dernières (min)', 'tickZoneMin', 'num', 1, 15)
            section('Sons')
            row('Sons', 'sounds')
            row('Volume (0-100)', 'volume', 'num', 0, 100)
            bs = tk.StringVar(value=st['bubbleSound'])
            f = tk.Frame(body, bg=BG)
            f.pack(fill='x')
            tk.Label(f, text='Son des bulles :', bg=BG, font=FONT).pack(side='left')
            for val, lab in (('droide', 'Droïde doux'), ('mes-sons', 'Mes sons (dossier)'), ('aucun', 'Aucun')):
                tk.Radiobutton(f, text=lab, value=val, variable=bs, bg=BG, font=FONT).pack(side='left')
            btn(body, '♫ Ouvrir le dossier de mes sons', self.open_sounds_dir).pack(anchor='w', pady=2)
            section('Aide')
            row('Plan du matin (les 3 cartes les plus urgentes)', 'morningPlan')
            row('Proposer ma carte la plus urgente au début du focus', 'taskReminders')
            row('« Tu attends quoi ? » : sans focus depuis un moment, me proposer des cartes', 'idleNudge')
            row('… au bout de (min)', 'idleNudgeMin', 'num', 10, 240)
            row('Petites phrases d\'encouragement', 'motivation')
            row('Pause auto si je m\'absente (il faut xprintidle)', 'idlePause')
            row('Me relancer si je n\'ai pas repris une interruption', 'ctxRemind')
            row('Boutons ronds à côté d\'Orbit', 'dock')
            auto = tk.BooleanVar(value=os.path.exists(autostart_path()))
            tk.Checkbutton(body, text='Lancer Orbit à l\'ouverture de session', variable=auto, bg=BG, font=FONT).pack(anchor='w', pady=(8, 0))

            def ok():
                new = dict(st)
                new['rhythm'] = rv.get()
                new['bubbleSound'] = bs.get()
                for k, (v, kind, lo, hi) in vals.items():
                    new[k] = bool(v.get()) if kind == 'bool' else C.num(v.get(), lo, hi, st[k])
                self.s.settings = C.sanitize_settings(new)
                set_autostart(auto.get())
                self.after_change()
                w.destroy()
            btn(body, 'Enregistrer', ok, primary=True).pack(anchor='e', pady=(10, 0))
        self.open_window('settings', 'Réglages', build, rebuild=True)

    def open_sounds_dir(self):
        os.makedirs(self.store.sounds, exist_ok=True)
        if shutil.which('xdg-open'):
            subprocess.Popen(['xdg-open', self.store.sounds], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.say('Pose tes sons (.wav, .ogg, .flac, .mp3) dans :\n%s\nIls passeront chacun leur tour, au hasard.' % self.store.sounds, seconds=10)

    # --- export / import ----------------------------------------------------------------------
    def export(self):
        path = filedialog.asksaveasfilename(parent=self.root, defaultextension='.zip', initialfile='Orbit-export.zip',
                                            filetypes=[('Zip', '*.zip')])
        if path:
            with open(path, 'wb') as f:
                f.write(C.export_zip(self.s))
            self.say('Export prêt : %s\nIl s\'ouvre aussi sur le PC (Importer un export) et le téléphone.' % os.path.basename(path), seconds=8)

    def import_(self):
        path = filedialog.askopenfilename(parent=self.root, filetypes=[('Zip', '*.zip')])
        if not path:
            return
        try:
            with open(path, 'rb') as f:
                data = f.read(200 * 1024 * 1024)
            before = C.export_zip(self.s)
            backup = os.path.join(self.store.dir, 'avant-import-%s.zip' % datetime.now().strftime('%Y%m%d-%H%M%S'))
            with open(backup, 'wb') as f:
                f.write(before)
            C.import_zip(self.s, data)
            mig = self.s.migrate_anchor()
            self.after_change()
            self.say('Données importées. Une copie de tes anciennes données est gardée :\n%s%s'
                     % (os.path.basename(backup), '\n(ancien Brain Dump converti en notes et cartes)' if mig else ''), seconds=10)
        except (OSError, ValueError) as e:
            self.say('Import impossible : %s' % C.short_text(str(e), 80), seconds=8)

    def quit(self):
        self.save()
        shutil.rmtree(self.sound.dir, ignore_errors=True)
        self.root.destroy()


# ---------------------------------------------------------------------------
#  Petits outils d'interface
# ---------------------------------------------------------------------------
def btn(parent, text, cmd, primary=False):
    return tk.Button(parent, text=text, command=cmd, bg=ACCENT if primary else SOFT, fg='white' if primary else INK,
                     activebackground='#5A4BD1' if primary else '#DDD8FF', relief='flat', bd=0, padx=10, pady=3,
                     font=FONT_B if primary else FONT, cursor='hand2')


class Tooltip:
    def __init__(self, widget, text):
        self.widget, self.text, self.tip = widget, text, None
        widget.bind('<Enter>', self.show)
        widget.bind('<Leave>', self.hide)

    def show(self, _=None):
        if self.tip:
            return
        self.tip = tk.Toplevel(self.widget)
        self.tip.overrideredirect(True)
        self.tip.attributes('-topmost', True)
        tk.Label(self.tip, text=self.text, bg=INK, fg='white', font=('DejaVu Sans', 9), padx=6, pady=2).pack()
        self.tip.geometry('+%d+%d' % (self.widget.winfo_rootx(), self.widget.winfo_rooty() - 26))

    def hide(self, _=None):
        if self.tip:
            self.tip.destroy()
            self.tip = None


def autostart_path():
    base = os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config')
    return os.path.join(base, 'autostart', 'orbit.desktop')


def set_autostart(on):
    p = autostart_path()
    if not on:
        if os.path.exists(p):
            os.remove(p)
        return
    os.makedirs(os.path.dirname(p), exist_ok=True)
    exe = '%s %s' % (sys.executable, os.path.abspath(__file__))
    C.write_atomic(p, '[Desktop Entry]\nType=Application\nName=Orbit\nComment=Compagnon de concentration\nExec=%s\n'
                      'X-GNOME-Autostart-enabled=true\nNoDisplay=false\n' % exe.replace('%', '%%'))


def single_instance():
    """Une seule fois Orbit par session (verrou dans le dossier d'execution de l'utilisateur)."""
    import fcntl
    path = os.path.join(os.environ.get('XDG_RUNTIME_DIR') or tempfile.gettempdir(), 'orbit-%d.lock' % os.getuid())
    f = open(path, 'w')
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return None
    return f


def main():
    lock = single_instance()
    if lock is None and not os.environ.get('ORBIT_SELFTEST'):
        print('Orbit est déjà lancé.')
        return 0
    root = tk.Tk()
    app = Orbit(root)
    if os.environ.get('ORBIT_SELFTEST'):
        sys.path.insert(0, os.path.join(HERE, '..', 'tests', 'linux'))
        import selftest_ui   # tests automatiques (tests/linux) : scenario complet puis sortie
        root.after(500, lambda: selftest_ui.run(app))
    root.protocol('WM_DELETE_WINDOW', app.quit)
    root.mainloop()
    return 0


if __name__ == '__main__':
    sys.exit(main())
