# -*- coding: utf-8 -*-
"""Orbit pour Linux : toute la logique, sans interface (testable seule).

Memes formats de donnees que la version PC (kanban.json, notes.json, reprises.json,
lifeanchor.json) et que la version PC : un zip exporte d'un cote s'ouvre de
l'autre. Tout ce qui est lu (fichiers, zip importe) est reverifie ici : identifiants,
adresses web, longueurs, types. Python 3.9+ et la bibliotheque standard seulement.
"""
from __future__ import annotations

import io
import json
import math
import os
import random
import re
import struct
import time
import unicodedata
import uuid
import zipfile
from datetime import datetime, timedelta

SAFE_ID = re.compile(r'^[A-Za-z0-9_-]{1,64}$')
RHYTHMS = {'50/10': (50, 10), '25/5': (25, 5)}
LIMITS = {'boards': 50, 'columns': 20, 'cards': 3000, 'checks': 100, 'notes': 2000, 'reprises': 200,
          'text': 300, 'long': 20000, 'wins': 3000}
SOUND_EXT = ('.wav', '.ogg', '.oga', '.flac', '.mp3')


# ---------------------------------------------------------------------------
#  Petites fonctions
# ---------------------------------------------------------------------------
def new_id() -> str:
    return uuid.uuid4().hex


def is_safe_id(v) -> bool:
    return isinstance(v, str) and bool(SAFE_ID.match(v))


def safe_id(v) -> str:
    return v if is_safe_id(v) else new_id()


_JUNK = re.compile('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F​‎‏'
                   '‪-‮⁦-⁩﻿�\uD800-\uDFFF]')


def clean_text(v, max_len: int = LIMITS['text']) -> str:
    """Texte affichable : sans caracteres de controle, longueur bornee."""
    if v is None or isinstance(v, (dict, list)):
        return ''
    s = str(v).replace('\r\n', '\n').replace('\r', '\n')
    s = _JUNK.sub('', s)
    if len(s) > max_len:
        s = short_text(s, max_len)
    return s


def short_text(v, max_len: int = 60) -> str:
    s = re.sub(r'\s+', ' ', str(v if v is not None else '')).strip()
    if len(s) <= max_len:
        return s
    return s[:max(0, max_len - 1)].rstrip('‍︎️⃣') + '…'


def limit_prio(p) -> int:
    try:
        n = int(str(p).strip())
    except (TypeError, ValueError):
        return 5
    return min(10, max(1, n))


def num(v, lo, hi, default):
    try:
        n = float(v)
    except (TypeError, ValueError):
        return default
    if math.isnan(n) or math.isinf(n):
        return default
    return min(hi, max(lo, n))


def as_bool(v) -> bool:
    return v is True


_URL_OK = re.compile(r'^https?://[^\s"\'<>`^{}|\\]+$')


def safe_url(v) -> str:
    """Adresse web : seulement http(s), sans caractere qui pourrait servir a autre chose."""
    u = str(v if v is not None else '').strip().replace(' ', '%20')
    if not u or len(u) > 2048:
        return ''
    if not re.match(r'^[A-Za-z][A-Za-z0-9+.-]*:', u) and re.match(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d{1,5})?([/?#]|$)', u):
        u = 'https://' + u
    return u if _URL_OK.match(u) else ''


_FOLD = {'œ': 'oe', 'æ': 'ae', 'ß': 'ss'}


def search_key(v) -> str:
    s = str(v if v is not None else '').lower()
    s = ''.join(_FOLD.get(c, c) for c in s).replace('’', "'")
    s = ''.join(c for c in unicodedata.normalize('NFD', s) if not unicodedata.combining(c))
    return re.sub(r'\s+', ' ', s).strip()


def matches(haystack, words) -> bool:
    h = search_key(haystack)
    return all(w in h for w in words)


def iso_local(d: datetime | None = None) -> str:
    return (d or datetime.now()).strftime('%Y-%m-%dT%H:%M:%S')


def day_string(d: datetime | None = None) -> str:
    return (d or datetime.now()).strftime('%Y-%m-%d')


_ISO = re.compile(r'^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?)?')


def iso_or_empty(v) -> str:
    s = str(v if v is not None else '')
    return s[:19] if _ISO.match(s) else ''


def day_or_empty(v) -> str:
    s = iso_or_empty(v)
    return s[:10] if s else ''


def parse_local(iso) -> datetime | None:
    m = re.match(r'^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?', str(iso or ''))
    if not m:
        return None
    try:
        return datetime(int(m[1]), int(m[2]), int(m[3]), int(m[4] or 0), int(m[5] or 0), int(m[6] or 0))
    except ValueError:
        return None


def format_ago(iso, now: datetime | None = None) -> str:
    now = now or datetime.now()
    d = parse_local(iso)
    if not d:
        return ''
    minutes = (now - d).total_seconds() / 60
    if minutes < 1:
        return "à l'instant"
    if minutes < 60:
        return 'il y a %d min' % int(minutes)
    hm = d.strftime('%H:%M')
    if day_string(d) == day_string(now):
        return 'à ' + hm
    if day_string(d) == day_string(now - timedelta(days=1)):
        return 'hier à ' + hm
    return 'le %s à %s' % (d.strftime('%d/%m'), hm)


def format_due(day, now: datetime | None = None) -> str:
    now = now or datetime.now()
    d = parse_local(day)
    if not d:
        return ''
    diff = (d.date() - now.date()).days
    if diff < 0:
        return 'en retard (%s)' % d.strftime('%d/%m')
    if diff == 0:
        return "aujourd'hui"
    if diff == 1:
        return 'demain'
    return d.strftime('%d/%m')


def fmt_clock(seconds: float) -> str:
    s = max(0, int(math.ceil(seconds)))
    return '%02d:%02d' % (s // 60, s % 60)


# ---------------------------------------------------------------------------
#  Reglages
# ---------------------------------------------------------------------------
def default_settings() -> dict:
    return {
        'rhythm': '50/10', 'customFocus': 40, 'customBreak': 8,
        'motivation': True, 'sounds': True, 'volume': 60,
        'bubbleSound': 'droide',          # droide | mes-sons | aucun
        'taskReminders': True, 'morningPlan': True, 'reminderEveryMin': 4,
        'idleNudge': True, 'idleNudgeMin': 45,
        'tickSound': True, 'tickZoneMin': 5, 'urgencyBar': True,
        'dock': True, 'ctxRemind': True, 'ctxRemindMin': 30,
        'idlePause': True, 'idlePauseMin': 5,
    }


def sanitize_settings(s) -> dict:
    d = default_settings()
    if not isinstance(s, dict):
        return d
    out = dict(d)
    for k, v in d.items():
        if isinstance(v, bool) and isinstance(s.get(k), bool):
            out[k] = s[k]
    if s.get('rhythm') in ('50/10', '25/5', 'Perso'):
        out['rhythm'] = s['rhythm']
    if s.get('bubbleSound') in ('droide', 'mes-sons', 'aucun'):
        out['bubbleSound'] = s['bubbleSound']
    out['customFocus'] = num(s.get('customFocus'), 1, 240, d['customFocus'])
    out['customBreak'] = num(s.get('customBreak'), 1, 120, d['customBreak'])
    out['volume'] = int(num(s.get('volume'), 0, 100, d['volume']))
    out['reminderEveryMin'] = num(s.get('reminderEveryMin'), 1, 60, d['reminderEveryMin'])
    out['idleNudgeMin'] = num(s.get('idleNudgeMin'), 10, 240, d['idleNudgeMin'])
    out['tickZoneMin'] = int(round(num(s.get('tickZoneMin'), 1, 15, d['tickZoneMin'])))
    out['ctxRemindMin'] = num(s.get('ctxRemindMin'), 5, 480, d['ctxRemindMin'])
    out['idlePauseMin'] = num(s.get('idlePauseMin'), 1, 120, d['idlePauseMin'])
    return out


def rhythm_minutes(settings) -> tuple:
    if settings.get('rhythm') == 'Perso':
        return settings['customFocus'], settings['customBreak']
    return RHYTHMS.get(settings.get('rhythm'), RHYTHMS['50/10'])


# ---------------------------------------------------------------------------
#  Tableaux (meme format que kanban.json de la version PC)
# ---------------------------------------------------------------------------
def new_column(name, done=False) -> dict:
    return {'id': new_id(), 'name': name, 'done': done}


def new_board(name) -> dict:
    return {'id': new_id(), 'name': name,
            'columns': [new_column('À faire'), new_column('En cours'), new_column('Terminé', True)]}


REPEATS = ('', 'workdays', 'weekdays', 'daily', 'weekly', 'biweekly', 'monthly')


def _sanitize_checks(lst) -> list:
    out = []
    for c in lst if isinstance(lst, list) else []:
        if not isinstance(c, dict):
            continue
        text = clean_text(c.get('text'))
        if text:
            out.append({'text': text, 'done': as_bool(c.get('done'))})
        if len(out) >= LIMITS['checks']:
            break
    return out


def sanitize_card(t: dict, board: str, col: str, order) -> dict:
    return {
        'id': safe_id(t.get('id')), 'text': clean_text(t.get('text')) or 'Sans titre',
        'desc': clean_text(t.get('desc'), LIMITS['long']), 'prio': limit_prio(t.get('prio')),
        'due': day_or_empty(t.get('due')), 'remindAt': iso_or_empty(t.get('remindAt')), 'reminded': as_bool(t.get('reminded')),
        'done': as_bool(t.get('done')), 'created': iso_or_empty(t.get('created')) or iso_local(),
        'doneAt': iso_or_empty(t.get('doneAt')), 'board': board, 'col': col, 'order': num(order, -1e9, 1e9, 0),
        'pomos': int(num(t.get('pomos'), 0, 1e6, 0)), 'focusMin': int(num(t.get('focusMin'), 0, 1e8, 0)),
        'lastFocus': iso_or_empty(t.get('lastFocus')), 'checks': _sanitize_checks(t.get('checks')),
        'repeat': t.get('repeat') if t.get('repeat') in REPEATS else '', 'spawned': as_bool(t.get('spawned')),
    }


def sanitize_kanban(data) -> dict:
    out = {'current': '', 'boards': [], 'cards': [], 'focus': [], 'upcoming': [], 'templates': []}
    d = data if isinstance(data, dict) else {}
    seen = set()
    for b in d.get('boards') if isinstance(d.get('boards'), list) else []:
        if not isinstance(b, dict) or not is_safe_id(b.get('id')) or b['id'] in seen or len(out['boards']) >= LIMITS['boards']:
            continue
        cols = []
        for c in b.get('columns') if isinstance(b.get('columns'), list) else []:
            if isinstance(c, dict) and is_safe_id(c.get('id')) and c['id'] not in seen and len(cols) < LIMITS['columns']:
                seen.add(c['id'])
                cols.append({'id': c['id'], 'name': clean_text(c.get('name'), 60) or 'Colonne', 'done': as_bool(c.get('done'))})
        if not cols:
            continue
        seen.add(b['id'])
        out['boards'].append({'id': b['id'], 'name': clean_text(b.get('name'), 60) or 'Tableau', 'columns': cols})
    if not out['boards']:
        out['boards'].append(new_board('Mon tableau'))
    ids = [b['id'] for b in out['boards']]
    out['current'] = d.get('current') if d.get('current') in ids else ids[0]
    card_ids = set()
    for t in d.get('cards') if isinstance(d.get('cards'), list) else []:
        if not isinstance(t, dict) or len(out['cards']) >= LIMITS['cards']:
            continue
        b = next((x for x in out['boards'] if x['id'] == t.get('board')), None)
        if not b:
            continue
        col = next((c for c in b['columns'] if c['id'] == t.get('col')), None)
        if not col:
            col = next((c for c in b['columns'] if not c['done']), b['columns'][0])
        card = sanitize_card(t, b['id'], col['id'], t.get('order'))
        if card['id'] in card_ids:
            card['id'] = new_id()
        card_ids.add(card['id'])
        card['done'] = col['done']
        out['cards'].append(card)
    out['focus'] = [i for i in (d.get('focus') if isinstance(d.get('focus'), list) else []) if is_safe_id(i) and i in card_ids]
    # cartes recurrentes a venir et modeles : geres par la version PC, gardes tels quels (verifies)
    up = []
    for u in (d.get('upcoming') if isinstance(d.get('upcoming'), list) else [])[:500]:
        if isinstance(u, dict):
            c = sanitize_card(u, u.get('board') if is_safe_id(u.get('board')) else '', '', 0)
            c['showAt'] = day_or_empty(u.get('showAt'))
            if c['showAt']:
                up.append(c)
    out['upcoming'] = up
    out['templates'] = [{'name': clean_text(m.get('name'), 60), 'text': clean_text(m.get('text')),
                         'desc': clean_text(m.get('desc'), LIMITS['long']), 'prio': limit_prio(m.get('prio')),
                         'checks': _sanitize_checks(m.get('checks')),
                         'repeat': m.get('repeat') if m.get('repeat') in REPEATS else ''}
                        for m in (d.get('templates') if isinstance(d.get('templates'), list) else [])[:200]
                        if isinstance(m, dict) and m.get('name')]
    return out


def sanitize_notes(lst) -> list:
    out, ids = [], set()
    for n in lst if isinstance(lst, list) else []:
        if not isinstance(n, dict) or len(out) >= LIMITS['notes']:
            continue
        text = clean_text(n.get('text'), LIMITS['long'])
        if not text.strip():
            continue
        nid = safe_id(n.get('id'))
        if nid in ids:
            nid = new_id()
        ids.add(nid)
        updated = iso_or_empty(n.get('updated')) or iso_or_empty(n.get('created')) or iso_local()
        out.append({'id': nid, 'text': text, 'created': iso_or_empty(n.get('created')) or updated,
                    'updated': updated, 'pinned': as_bool(n.get('pinned'))})
    return out


def _sanitize_window(w: dict) -> dict:
    priv = as_bool(w.get('private'))
    return {
        'app': re.sub(r'[^A-Za-z0-9_.-]', '', str(w.get('app') or '')).lower()[:40],
        'title': 'Fenêtre de navigation privée' if priv else clean_text(w.get('title'), 200),
        'url': '' if priv else safe_url(w.get('url')),
        'path': '' if priv else re.sub(r'["<>|*?]', '', clean_text(w.get('path'), 400)),
        'hwnd': 0, 'pid': 0, 'private': priv,
    }


def sanitize_reprises(lst) -> list:
    out, ids = [], set()
    for c in lst if isinstance(lst, list) else []:
        if not isinstance(c, dict) or len(out) >= LIMITS['reprises']:
            continue
        cid = safe_id(c.get('id'))
        if cid in ids:
            cid = new_id()
        ids.add(cid)
        out.append({
            'id': cid, 'created': iso_or_empty(c.get('created')) or iso_local(),
            'status': 'done' if c.get('status') == 'done' else 'open', 'doneAt': iso_or_empty(c.get('doneAt')),
            'doing': clean_text(c.get('doing'), 2000), 'next': clean_text(c.get('next'), 2000),
            'windows': [_sanitize_window(w) for w in (c.get('windows') if isinstance(c.get('windows'), list) else [])
                        if isinstance(w, dict)][:10],
            'focusCards': [i for i in (c.get('focusCards') if isinstance(c.get('focusCards'), list) else []) if is_safe_id(i)][:50],
            'wasFocus': as_bool(c.get('wasFocus')), 'focusLeftMin': num(c.get('focusLeftMin'), 0, 1000, 0),
            'remindAt': iso_or_empty(c.get('remindAt')), 'reminders': int(num(c.get('reminders'), 0, 100, 0)),
        })
    return out


def sanitize_anchor(a) -> dict:
    """lifeanchor.json : on garde le journal des victoires et le deblocage en cours."""
    d = a if isinstance(a, dict) else {}
    out = {'dump': [], 'tasks': [], 'wins': [], 'unstick': None}
    ids = set()
    for w in (d.get('wins') if isinstance(d.get('wins'), list) else [])[-LIMITS['wins']:]:
        if not isinstance(w, dict):
            continue
        title = clean_text(w.get('title'), 200)
        if not title:
            continue
        wid = safe_id(w.get('id'))
        if wid in ids:
            wid = new_id()
        ids.add(wid)
        out['wins'].append({'id': wid, 'title': title,
                            'kind': re.sub(r'[^a-z]', '', str(w.get('kind') or ''))[:20] or 'task',
                            'at': iso_or_empty(w.get('at')) or iso_local()})
    # ancien Brain Dump / DopaList (versions precedentes) : relus pour etre convertis
    for x in (d.get('dump') if isinstance(d.get('dump'), list) else [])[:1000]:
        if isinstance(x, dict) and clean_text(x.get('text'), 2000).strip():
            out['dump'].append({'text': clean_text(x.get('text'), 2000)})
    for x in (d.get('tasks') if isinstance(d.get('tasks'), list) else [])[:2000]:
        if isinstance(x, dict) and x.get('status', 'todo') == 'todo':
            out['tasks'].append({'title': clean_text(x.get('title')) or 'Sans titre', 'isRoutine': as_bool(x.get('isRoutine')),
                                 'repeat': x.get('repeat') if x.get('repeat') in ('daily', 'weekdays', 'weekly') else ''})
    u = d.get('unstick')
    if isinstance(u, dict):
        steps = [{'content': clean_text(s.get('content')), 'sec': int(num(s.get('sec'), 30, 900, 150)), 'done': as_bool(s.get('done'))}
                 for s in (u.get('steps') if isinstance(u.get('steps'), list) else [])[:12] if isinstance(s, dict)]
        steps = [s for s in steps if s['content']]
        if steps:
            out['unstick'] = {'title': clean_text(u.get('title')), 'steps': steps,
                              'index': int(num(u.get('index'), 0, len(steps) - 1, 0))}
    return out


# ---------------------------------------------------------------------------
#  L'etat complet et ses operations
# ---------------------------------------------------------------------------
class State:
    def __init__(self):
        b = new_board('Mon tableau')
        self.settings = default_settings()
        self.timer = {'state': 'Idle', 'endsAt': 0.0, 'paused': False, 'remaining': 0.0, 'sessionMin': 0}
        self.stats = {'date': day_string(), 'focus': 0, 'minutes': 0, 'planDay': ''}
        self.kanban = {'current': b['id'], 'boards': [b], 'cards': [], 'focus': [], 'upcoming': [], 'templates': []}
        self.notes = []
        self.reprises = []
        self.anchor = {'dump': [], 'tasks': [], 'wins': [], 'unstick': None}

    # --- tableaux ---
    def board(self, bid):
        return next((b for b in self.kanban['boards'] if b['id'] == bid), None)

    def current_board(self):
        return self.board(self.kanban['current']) or self.kanban['boards'][0]

    def card(self, cid):
        return next((t for t in self.kanban['cards'] if t['id'] == cid), None)

    def find_column(self, col_id):
        for b in self.kanban['boards']:
            for c in b['columns']:
                if c['id'] == col_id:
                    return b, c
        return None, None

    @staticmethod
    def open_column(b):
        return next((c for c in b['columns'] if not c['done']), b['columns'][0])

    @staticmethod
    def done_column(b):
        return next((c for c in b['columns'] if c['done']), b['columns'][-1])

    def column_cards(self, col_id):
        return sorted((t for t in self.kanban['cards'] if t['col'] == col_id), key=lambda t: (t['order'], t['prio']))

    def add_card(self, raw_text, col_id='', prio=5, now: datetime | None = None):
        p = parse_shortcuts(raw_text, now)
        text = clean_text(p['text'])
        if not text or len(self.kanban['cards']) >= LIMITS['cards']:
            return None
        b, col = self.find_column(col_id) if col_id else (None, None)
        if not col:
            b = self.current_board()
            col = self.open_column(b)
        cards = self.column_cards(col['id'])
        card = sanitize_card({'id': new_id(), 'text': text, 'prio': p['prio'] if p['prio'] else prio,
                              'remindAt': p['remindAt'], 'created': iso_local()}, b['id'], col['id'],
                             cards[-1]['order'] + 1 if cards else 0)
        card['done'] = col['done']
        if card['done']:
            card['doneAt'] = iso_local()
        self.kanban['cards'].append(card)
        return card

    def move_card(self, cid, col_id):
        t = self.card(cid)
        b, col = self.find_column(col_id)
        if not t or not col:
            return
        others = [x for x in self.column_cards(col_id) if x['id'] != cid]
        t['board'], t['col'] = b['id'], col_id
        t['order'] = others[-1]['order'] + 1 if others else 0
        was_done = t['done']
        t['done'] = col['done']
        if t['done'] and not was_done:
            t['doneAt'] = iso_local()
            self.kanban['focus'] = [x for x in self.kanban['focus'] if x != cid]
            self.add_win(t['text'], 'card')
        if not t['done']:
            t['doneAt'] = ''

    def shift_card(self, cid, step):
        """Deplace une carte d'une colonne vers la gauche (-1) ou la droite (+1)."""
        t = self.card(cid)
        b = self.board(t['board']) if t else None
        if not b:
            return
        ids = [c['id'] for c in b['columns']]
        i = ids.index(t['col']) + step
        if 0 <= i < len(ids):
            self.move_card(cid, ids[i])

    def set_card_done(self, cid, done=True):
        t = self.card(cid)
        b = self.board(t['board']) if t else None
        if b:
            self.move_card(cid, (self.done_column(b) if done else self.open_column(b))['id'])

    def remove_card(self, cid):
        self.kanban['cards'] = [t for t in self.kanban['cards'] if t['id'] != cid]
        self.kanban['focus'] = [x for x in self.kanban['focus'] if x != cid]

    def open_cards(self):
        return [t for t in self.kanban['cards'] if not t['done']]

    def focus_cards(self, open_only=False):
        out = []
        for i in self.kanban['focus']:
            t = self.card(i)
            if t and (not open_only or not t['done']):
                out.append(t)
        return out

    def move_to_doing(self, t):
        b = self.board(t['board'])
        if not b or t['done'] or t['col'] != self.open_column(b)['id']:
            return
        doing = next((c for c in b['columns'] if not c['done'] and re.match(r'^\s*en\s*cours', c['name'], re.I)), None)
        if doing and doing['id'] != t['col']:
            self.move_card(t['id'], doing['id'])

    def plan_cards(self, n=3, now: datetime | None = None):
        """Les cartes les plus urgentes, tous tableaux confondus, avec la raison."""
        now = now or datetime.now()
        today, tomorrow = day_string(now), day_string(now + timedelta(days=1))
        scored = []
        for t in self.kanban['cards']:
            if t['done']:
                continue
            score, why = (11 - t['prio']) * 10, ''
            if t['due'] and t['due'] < today:
                score += 400
                why = 'en retard (%s)' % format_due(t['due'], now)
            elif t['due'] == today:
                score += 300
                why = "à rendre aujourd'hui"
            elif t['due'] == tomorrow:
                score += 200
                why = 'à rendre demain'
            if t['remindAt'] and t['remindAt'][:10] == today:
                score += 150
                why = why or 'rappel à %s' % t['remindAt'][11:16]
            if t['id'] in self.kanban['focus']:
                score += 60
                why = why or 'déjà liée au focus'
            b = self.board(t['board'])
            if b and t['col'] != self.open_column(b)['id']:
                score += 40
                why = why or 'déjà commencée'
            if t['pomos']:
                score += 10
            scored.append({'card': t, 'score': score, 'why': why})
        scored.sort(key=lambda x: (-x['score'], x['card']['prio']))
        return scored[:n]

    # --- chrono ---
    def time_left(self, now=None) -> float:
        t = self.timer
        if t['state'] not in ('Focus', 'Break'):
            return 0.0
        now = time.time() if now is None else now
        return max(0.0, t['remaining'] if t['paused'] else t['endsAt'] - now)

    def start_focus(self, now=None):
        now = time.time() if now is None else now
        f = rhythm_minutes(self.settings)[0]
        self.timer = {'state': 'Focus', 'endsAt': now + f * 60, 'paused': False, 'remaining': 0.0, 'sessionMin': f}
        self.kanban['focus'] = [i for i in self.kanban['focus'] if self.card(i) and not self.card(i)['done']]
        if not self.kanban['focus'] and self.settings['taskReminders']:
            first = self.plan_cards(1)
            if first:
                self.kanban['focus'].append(first[0]['card']['id'])
        for t in self.focus_cards(True):
            self.move_to_doing(t)

    def start_break(self, now=None):
        now = time.time() if now is None else now
        b = rhythm_minutes(self.settings)[1]
        self.timer = {'state': 'Break', 'endsAt': now + b * 60, 'paused': False, 'remaining': 0.0, 'sessionMin': b}

    def pause(self, now=None):
        t = self.timer
        now = time.time() if now is None else now
        if t['state'] in ('Focus', 'Break') and not t['paused']:
            t['remaining'] = max(0.0, t['endsAt'] - now)
            t['paused'] = True

    def resume(self, now=None):
        t = self.timer
        now = time.time() if now is None else now
        if t['state'] in ('Focus', 'Break') and t['paused']:
            t['endsAt'] = now + t['remaining']
            t['paused'] = False

    def stop(self):
        self.timer = {'state': 'Idle', 'endsAt': 0.0, 'paused': False, 'remaining': 0.0, 'sessionMin': 0}

    def tick(self, now=None) -> str:
        """Avance le chrono. Renvoie 'focusEnded', 'breakEnded' ou ''."""
        t = self.timer
        now = time.time() if now is None else now
        if t['state'] not in ('Focus', 'Break') or t['paused'] or now < t['endsAt']:
            return ''
        if t['state'] == 'Focus':
            d = day_string(datetime.fromtimestamp(now))
            if self.stats['date'] != d:
                self.stats.update(date=d, focus=0, minutes=0)
            self.stats['focus'] += 1
            self.stats['minutes'] += t['sessionMin']
            for c in self.focus_cards():
                c['pomos'] += 1
                c['focusMin'] += int(round(t['sessionMin']))
                c['lastFocus'] = iso_local(datetime.fromtimestamp(now))
            self.add_win('Focus de %d min' % round(t['sessionMin']), 'focus', datetime.fromtimestamp(now))
            self.timer = {'state': 'AwaitBreak', 'endsAt': 0.0, 'paused': False, 'remaining': 0.0, 'sessionMin': t['sessionMin']}
            return 'focusEnded'
        self.timer = {'state': 'AwaitFocus', 'endsAt': 0.0, 'paused': False, 'remaining': 0.0, 'sessionMin': 0}
        return 'breakEnded'

    # --- notes ---
    def sorted_notes(self):
        by_date = sorted(self.notes, key=lambda n: n['updated'], reverse=True)
        return sorted(by_date, key=lambda n: not n['pinned'])   # tri stable : epinglees d'abord

    def add_note(self, text):
        t = clean_text(text, LIMITS['long']).strip()
        if not t or len(self.notes) >= LIMITS['notes']:
            return None
        now = iso_local()
        n = {'id': new_id(), 'text': t, 'created': now, 'updated': now, 'pinned': False}
        self.notes.insert(0, n)
        return n

    def update_note(self, nid, text):
        n = next((x for x in self.notes if x['id'] == nid), None)
        if not n:
            return
        t = clean_text(text, LIMITS['long']).strip()
        if not t:
            self.notes = [x for x in self.notes if x['id'] != nid]
        elif n['text'] != t:
            n['text'], n['updated'] = t, iso_local()

    # --- reprises (« Je m'interromps ») ---
    def open_reprises(self):
        return sorted((c for c in self.reprises if c['status'] == 'open'), key=lambda c: c['created'], reverse=True)

    def add_reprise(self, doing='', nxt='', title='', app='', now: datetime | None = None):
        now = now or datetime.now()
        c = sanitize_reprises([{
            'id': new_id(), 'created': iso_local(now), 'status': 'open', 'doing': doing, 'next': nxt,
            'windows': [{'app': app or 'linux', 'title': title}] if title else [],
            'focusCards': [t['id'] for t in self.focus_cards(True)], 'wasFocus': self.timer['state'] == 'Focus',
            'focusLeftMin': round(self.time_left() / 60, 1) if self.timer['state'] == 'Focus' else 0,
        }])[0]
        if self.settings['ctxRemind']:
            c['remindAt'] = iso_local(now + timedelta(minutes=self.settings['ctxRemindMin']))
        self.reprises.insert(0, c)
        del self.reprises[LIMITS['reprises']:]
        return c

    def complete_reprise(self, rid):
        c = next((x for x in self.reprises if x['id'] == rid), None)
        if c and c['status'] == 'open':
            c['status'], c['doneAt'] = 'done', iso_local()
            self.add_win('Repris : %s' % reprise_title(c, 60), 'reprise')

    def due_reprise(self, now: datetime | None = None):
        if not self.settings['ctxRemind']:
            return None
        iso = iso_local(now)
        return next((c for c in self.open_reprises() if c['remindAt'] and c['remindAt'] <= iso and c['reminders'] < 3), None)

    def prune_reprises(self, now: datetime | None = None):
        limit = iso_local((now or datetime.now()) - timedelta(days=14))
        self.reprises = [c for c in self.reprises if not (c['status'] == 'done' and c['doneAt'] and c['doneAt'] < limit)]

    # --- victoires ---
    def add_win(self, title, kind='task', now: datetime | None = None):
        now = now or datetime.now()
        w = {'id': new_id(), 'title': clean_text(title, 200) or 'Une victoire', 'kind': kind, 'at': iso_local(now)}
        self.anchor['wins'].append(w)
        limit = iso_local(now - timedelta(days=60))
        self.anchor['wins'] = [x for x in self.anchor['wins'] if x['at'] >= limit][-LIMITS['wins']:]
        return w

    def wins_of_day(self, now: datetime | None = None):
        d = day_string(now)
        return sorted((w for w in self.anchor['wins'] if w['at'][:10] == d), key=lambda w: w['at'], reverse=True)

    def win_streak(self, now: datetime | None = None) -> int:
        days = {w['at'][:10] for w in self.anchor['wins']}
        d = now or datetime.now()
        if day_string(d) not in days:
            d -= timedelta(days=1)
        n = 0
        while day_string(d) in days:
            n += 1
            d -= timedelta(days=1)
        return n

    # --- S.O.S / Unstick Me ---
    def start_unstick(self, title, rules):
        steps = [{'content': c, 'sec': 150, 'done': False} for c in decompose(title, rules)]
        if not steps:
            return None
        self.anchor['unstick'] = {'title': clean_text(title), 'steps': steps, 'index': 0}
        return self.anchor['unstick']

    def unstick_step_done(self, now: datetime | None = None) -> str:
        u = self.anchor['unstick']
        if not u:
            return ''
        u['steps'][u['index']]['done'] = True
        if u['index'] < len(u['steps']) - 1:
            u['index'] += 1
            return 'next'
        self.add_win('Débloqué : %s' % u['title'], 'unstick', now)
        self.anchor['unstick'] = None
        return 'finished'

    def unstick_smaller(self):
        u = self.anchor['unstick']
        if not u or len(u['steps']) >= 12:
            return
        s = u['steps'][u['index']]
        u['steps'].insert(u['index'], {'content': "Prépare-toi juste pour : « %s » (pose ce qu'il faut devant toi)"
                                       % short_text(s['content'], 80), 'sec': 90, 'done': False})

    # --- recherche ---
    def search(self, q):
        words = [w for w in search_key(q).split(' ') if w]
        r = {'cards': [], 'notes': [], 'reprises': []}
        if not words:
            return r
        r['cards'] = sorted((t for t in self.kanban['cards']
                             if matches('%s %s %s' % (t['text'], t['desc'], ' '.join(c['text'] for c in t['checks'])), words)),
                            key=lambda t: (t['done'], t['prio']))
        r['notes'] = [n for n in self.notes if matches(n['text'], words)]
        r['reprises'] = [c for c in self.reprises
                         if matches('%s %s %s' % (c['doing'], c['next'], ' '.join(w['title'] + ' ' + w['url'] for w in c['windows'])), words)]
        return r

    # --- ancien Brain Dump / DopaList (lifeanchor.json d'une ancienne version) ---
    def migrate_anchor(self):
        notes = cards = 0
        for d in self.anchor['dump']:
            if self.add_note(d['text']):
                notes += 1
        for t in self.anchor['tasks']:
            c = self.add_card(t['title'])
            if c:
                if t['isRoutine']:
                    c['repeat'] = {'weekdays': 'workdays', 'weekly': 'weekly'}.get(t['repeat'], 'daily')
                    c['desc'] = 'Ancienne routine de la DopaList'
                cards += 1
        had = bool(self.anchor['dump'] or self.anchor['tasks'])
        self.anchor['dump'], self.anchor['tasks'] = [], []
        return {'notes': notes, 'cards': cards} if had else None


def parse_shortcuts(text, now: datetime | None = None) -> dict:
    """« !2 » = priorite 2, « @14h » / « @14h30 » = rappel (aujourd'hui, ou demain si l'heure est passee)."""
    now = now or datetime.now()
    t = str(text if text is not None else '').strip()
    prio, remind = None, ''
    m = re.search(r'(^|\s)!(10|[1-9])(?=\s|$)', t)
    if m:
        prio = int(m.group(2))
        t = re.sub(r'\s{2,}', ' ', t[:m.start()] + ' ' + t[m.end():]).strip()
    m = re.search(r'(^|\s)@([01]?\d|2[0-3])(?:h|:)([0-5]\d)?(?=\s|$)', t)
    if m:
        at = now.replace(hour=int(m.group(2)), minute=int(m.group(3) or 0), second=0, microsecond=0)
        if at <= now:
            at += timedelta(days=1)
        remind = iso_local(at)
        t = re.sub(r'\s{2,}', ' ', t[:m.start()] + ' ' + t[m.end():]).strip()
    return {'text': t, 'prio': prio, 'remindAt': remind}


def reprise_title(c, max_len=70) -> str:
    if c.get('next'):
        return short_text(c['next'], max_len)
    if c.get('doing'):
        return short_text(c['doing'], max_len)
    w = c['windows'][0] if c.get('windows') else None
    if w and w.get('title'):
        return short_text(w['title'], max_len)
    if w and w.get('url'):
        return short_text(re.sub(r'^https?://', '', w['url']), max_len)
    return 'Reprise sans détail'


def note_title(n, max_len=60) -> str:
    first = next((ln for ln in str(n['text']).split('\n') if ln.strip()), '')
    return short_text(first.strip(), max_len)


# ---------------------------------------------------------------------------
#  S.O.S : decoupage local en micro-etapes (meme fichier de regles que le PC)
# ---------------------------------------------------------------------------
def decompose(text, rules) -> list:
    task = clean_text(text, 300).strip()
    if not task:
        return []
    rules = rules if isinstance(rules, dict) else {}
    norm = ' ' + re.sub(r'\s+', ' ', re.sub(r"[^a-z0-9' -]", ' ', search_key(task))) + ' '
    obj = task
    for v in rules.get('verbs') or []:
        if search_key(task).startswith(v + ' '):
            obj = task[len(v):].strip()
            break
    obj = re.sub(r"^(le|la|les|l'|un|une|des|du|de|d'|mon|ma|mes|ton|ta|tes)\s*", '', obj, flags=re.I).strip() or task
    steps = rules.get('generic') or ['Commence « {x} » : la toute première action', 'Continue 2 minutes', 'Note où tu en es']
    for r in rules.get('rules') or []:
        if any((' ' + search_key(k)) in norm for k in r.get('keys', [])):
            steps = r['steps']
            break
    return [s.replace('{x}', task).replace('{o}', obj) for s in steps[:5]]


# ---------------------------------------------------------------------------
#  Zone finale du focus, relance « Tu attends quoi ? », sons (memes regles que le PC)
# ---------------------------------------------------------------------------
def tick_interval(left_sec, zone_sec) -> int:
    if left_sec <= 0 or left_sec > zone_sec:
        return 0
    if left_sec > 120:
        return 20
    if left_sec > 60:
        return 10
    if left_sec > 30:
        return 5
    if left_sec > 10:
        return 2
    return 1


def urgency_level(frac, left_sec) -> str:
    if left_sec <= 60:
        return 'final'
    if frac > 0.5:
        return 'calm'
    if frac > 0.25:
        return 'mid'
    return 'high'


def idle_nudge_due(settings, timer_state, last_busy, now=None, off_day='') -> bool:
    now = time.time() if now is None else now
    if not settings['idleNudge'] or timer_state != 'Idle':
        return False
    if off_day == day_string(datetime.fromtimestamp(now)):
        return False
    return now - last_busy >= settings['idleNudgeMin'] * 60


class SoundBag:
    """Chacun son tour, dans un ordre au hasard : la liste est melangee, jouee en entier, puis remelangee
    (sans rejouer tout de suite le dernier son entendu)."""

    def __init__(self, rng=None):
        self.rng = rng or random.Random()
        self.key, self.bag, self.last = None, [], None

    def pick(self, items):
        items = [i for i in items if i]
        if len(items) <= 1:
            self.last = items[0] if items else None
            return self.last
        key = '|'.join(items)
        if key != self.key or not self.bag:
            self.key = key
            mixed = list(items)
            self.rng.shuffle(mixed)
            if mixed[0] == self.last:
                mixed.append(mixed.pop(0))
            self.bag = mixed
        self.last = self.bag.pop(0)
        return self.last


def list_sounds(folder) -> list:
    try:
        return sorted(os.path.join(folder, f) for f in os.listdir(folder)
                      if f.lower().endswith(SOUND_EXT) and os.path.isfile(os.path.join(folder, f)))
    except OSError:
        return []


def make_wav(tones, volume=60, rate=22050) -> bytes:
    """Petit WAV en memoire. tones = [(frequence, duree_s, glissando_vers), ...]."""
    amp = 12000 * min(1.0, max(0.0, volume / 100.0))
    frames = bytearray()
    for freq, dur, glide in tones:
        n = int(rate * dur)
        phase = 0.0
        for i in range(n):
            f = freq + (glide - freq) * i / n if glide else freq
            phase += 2 * math.pi * f / rate
            env = min(1.0, i / 60.0) * math.exp(-4.0 * i / n)
            frames += struct.pack('<h', int(amp * env * math.sin(phase)))
        frames += b'\x00\x00' * int(rate * 0.02)
    head = b'RIFF' + struct.pack('<I', 36 + len(frames)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, rate, rate * 2, 2, 16)
    return head + b'data' + struct.pack('<I', len(frames)) + bytes(frames)


# ---------------------------------------------------------------------------
#  Fichiers : lecture verifiee, ecriture atomique, sauvegarde du jour
# ---------------------------------------------------------------------------
FILES = ('kanban.json', 'notes.json', 'reprises.json', 'lifeanchor.json')


def data_dir() -> str:
    base = os.environ.get('ORBIT_DATA') or os.path.join(
        os.environ.get('XDG_DATA_HOME') or os.path.join(os.path.expanduser('~'), '.local', 'share'), 'orbit')
    os.makedirs(base, exist_ok=True)
    return base


def write_atomic(path, text):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def read_json(path):
    with open(path, 'r', encoding='utf-8-sig') as f:
        return json.load(f)


class Store:
    """Charge et enregistre l'etat dans le dossier de donnees (un fichier par sujet, comme le PC)."""

    def __init__(self, folder=None):
        self.dir = folder or data_dir()
        self.backups = os.path.join(self.dir, 'sauvegardes')
        self.sounds = os.path.join(self.dir, 'sons')
        self.notices = []

    def _load(self, name, default):
        path = os.path.join(self.dir, name)
        if not os.path.exists(path):
            return default
        try:
            return read_json(path)
        except (OSError, ValueError) as e:
            bad = path + '.illisible-' + datetime.now().strftime('%Y%m%d-%H%M%S')
            try:
                os.replace(path, bad)
            except OSError:
                pass
            # on repart de la sauvegarde du jour la plus recente
            for f in sorted(os.listdir(self.backups) if os.path.isdir(self.backups) else [], reverse=True):
                if f.startswith(name[:-5] + '-'):
                    try:
                        data = read_json(os.path.join(self.backups, f))
                        self.notices.append('%s était abîmé : j\'ai repris la sauvegarde du %s.' % (name, f[len(name) - 4:-5]))
                        return data
                    except (OSError, ValueError):
                        continue
            self.notices.append('%s était abîmé (%s) : il est gardé à côté, je repars à zéro.' % (name, e.__class__.__name__))
            return default

    def load(self) -> State:
        s = State()
        s.settings = sanitize_settings(self._load('settings.json', {}))
        s.kanban = sanitize_kanban(self._load('kanban.json', None) or s.kanban)
        notes = self._load('notes.json', [])
        s.notes = sanitize_notes(notes if isinstance(notes, list) else [notes])
        rep = self._load('reprises.json', [])
        s.reprises = sanitize_reprises(rep if isinstance(rep, list) else [rep])
        s.anchor = sanitize_anchor(self._load('lifeanchor.json', {}))
        st = self._load('etat.json', {})
        st = st if isinstance(st, dict) else {}
        t = st.get('timer') if isinstance(st.get('timer'), dict) else {}
        if t.get('state') in ('Idle', 'Focus', 'Break', 'AwaitBreak', 'AwaitFocus'):
            s.timer = {'state': t['state'], 'endsAt': num(t.get('endsAt'), 0, 1e12, 0), 'paused': as_bool(t.get('paused')),
                       'remaining': num(t.get('remaining'), 0, 86400, 0), 'sessionMin': num(t.get('sessionMin'), 0, 1000, 0)}
        stats = st.get('stats') if isinstance(st.get('stats'), dict) else {}
        s.stats.update({'date': day_or_empty(stats.get('date')) or day_string(), 'focus': int(num(stats.get('focus'), 0, 1e6, 0)),
                        'minutes': num(stats.get('minutes'), 0, 1e7, 0), 'planDay': day_or_empty(stats.get('planDay'))})
        if s.stats['date'] != day_string():
            s.stats.update(date=day_string(), focus=0, minutes=0)
        return s

    def save(self, s: State):
        os.makedirs(self.dir, exist_ok=True)
        files = {
            'settings.json': s.settings, 'kanban.json': s.kanban, 'notes.json': s.notes, 'reprises.json': s.reprises,
            'lifeanchor.json': {'dump': [], 'tasks': [], 'wins': s.anchor['wins'], 'unstick': s.anchor['unstick']},
            'etat.json': {'timer': s.timer, 'stats': s.stats},
        }
        for name, data in files.items():
            write_atomic(os.path.join(self.dir, name), json.dumps(data, ensure_ascii=False, indent=1))
        self.daily_backup()

    def daily_backup(self, keep_days=7):
        """Une copie par jour des tableaux et des notes (7 jours gardes)."""
        os.makedirs(self.backups, exist_ok=True)
        today = day_string()
        for name in ('kanban.json', 'notes.json'):
            src = os.path.join(self.dir, name)
            dst = os.path.join(self.backups, '%s-%s.json' % (name[:-5], today))
            if os.path.exists(src) and not os.path.exists(dst):
                with open(src, 'rb') as a, open(dst + '.tmp', 'wb') as b:
                    b.write(a.read())
                os.replace(dst + '.tmp', dst)
        limit = day_string(datetime.now() - timedelta(days=keep_days))
        for f in os.listdir(self.backups):
            m = re.search(r'-(\d{4}-\d{2}-\d{2})\.json$', f)
            if m and m.group(1) < limit:
                try:
                    os.remove(os.path.join(self.backups, f))
                except OSError:
                    pass


# ---------------------------------------------------------------------------
#  Echange avec les version PC (meme zip : Orbit/donnees/*.json)
# ---------------------------------------------------------------------------
MAX_ZIP_ENTRY = 20 * 1024 * 1024


def export_zip(s: State) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('Orbit/donnees/orbit-export.json', json.dumps({'from': 'linux', 'at': iso_local()}))
        z.writestr('Orbit/donnees/kanban.json', json.dumps(s.kanban, ensure_ascii=False, indent=1))
        z.writestr('Orbit/donnees/notes.json', json.dumps(s.notes, ensure_ascii=False, indent=1))
        z.writestr('Orbit/donnees/reprises.json', json.dumps(s.reprises, ensure_ascii=False, indent=1))
        z.writestr('Orbit/donnees/lifeanchor.json', json.dumps({'dump': [], 'tasks': [], 'wins': s.anchor['wins']}, ensure_ascii=False, indent=1))
    return buf.getvalue()


def import_zip(s: State, data: bytes) -> dict:
    """Lit un zip d'Orbit (PC ou Linux). Ne lit que les 4 fichiers de donnees, de taille raisonnable."""
    found = {}
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for info in z.infolist():
            name = info.filename.replace('\\', '/').split('/')[-1]
            if name in FILES and name not in found:
                if info.file_size > MAX_ZIP_ENTRY:
                    raise ValueError('fichier trop gros dans le zip : ' + name)
                with z.open(info) as f:
                    raw = f.read(MAX_ZIP_ENTRY + 1)
                if len(raw) > MAX_ZIP_ENTRY:
                    raise ValueError('fichier trop gros dans le zip : ' + name)
                found[name] = json.loads(raw.decode('utf-8-sig'))
    if not found:
        raise ValueError("ce zip ne contient pas de données d'Orbit")
    if 'kanban.json' in found:
        s.kanban = sanitize_kanban(found['kanban.json'])
    if 'notes.json' in found:
        n = found['notes.json']
        s.notes = sanitize_notes(n if isinstance(n, list) else [n])
    if 'reprises.json' in found:
        r = found['reprises.json']
        s.reprises = sanitize_reprises(r if isinstance(r, list) else [r])
    if 'lifeanchor.json' in found:
        unstick = s.anchor.get('unstick')
        s.anchor = sanitize_anchor(found['lifeanchor.json'])
        s.anchor['unstick'] = s.anchor['unstick'] or unstick
    return {k: True for k in found}
