# -*- coding: utf-8 -*-
"""Tests de la logique d'Orbit pour Linux (sans interface). Lancement : python3 tests/linux/test_core.py"""
import io
import json
import os
import random
import sys
import tempfile
import unittest
import zipfile
from datetime import datetime, timedelta

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'linux'))
import orbit_core as C  # noqa: E402



def load(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return json.load(f)


RULES = load('unstick', 'rules.json')


class Texte(unittest.TestCase):
    def test_clean_text(self):
        self.assertEqual(C.clean_text('a​b‮c\x00d'), 'abcd')
        self.assertEqual(C.clean_text(None), '')
        self.assertEqual(C.clean_text({'x': 1}), '')
        self.assertLessEqual(len(C.clean_text('x' * 5000)), 300)

    def test_short_text(self):
        self.assertEqual(C.short_text('abcdefghij', 5), 'abcd…')
        self.assertEqual(C.short_text('  court  ', 50), 'court')

    def test_safe_url(self):
        self.assertEqual(C.safe_url('exemple.fr/a'), 'https://exemple.fr/a')
        self.assertEqual(C.safe_url('javascript:alert(1)'), '')
        self.assertEqual(C.safe_url('https://ok.fr/"onclick'), '')
        self.assertEqual(C.safe_url('file:///etc/passwd'), '')

    def test_search_key(self):
        self.assertEqual(C.search_key('ÉCOLE Été Ça Œuvre'), 'ecole ete ca oeuvre')

    def test_shortcuts(self):
        now = datetime(2026, 10, 5, 15, 0)
        p = C.parse_shortcuts('Appeler Paul !2 @14h', now)
        self.assertEqual((p['text'], p['prio'], p['remindAt']), ('Appeler Paul', 2, '2026-10-06T14:00:00'))
        self.assertEqual(C.parse_shortcuts('Réunion @16h30', now)['remindAt'], '2026-10-05T16:30:00')

    def test_dates(self):
        now = datetime(2026, 10, 5, 12, 0)
        self.assertEqual(C.format_due('2026-10-05', now), "aujourd'hui")
        self.assertEqual(C.format_due('2026-10-06', now), 'demain')
        self.assertTrue(C.format_due('2026-10-01', now).startswith('en retard'))
        self.assertEqual(C.format_ago('2026-10-05T11:50:00', now), 'il y a 10 min')
        self.assertEqual(C.fmt_clock(61.2), '01:02')


class Tableaux(unittest.TestCase):
    def setUp(self):
        self.s = C.State()

    def test_ajout_deplacement_victoire(self):
        c = self.s.add_card('Payer la facture !2')
        self.assertEqual((c['text'], c['prio'], c['done']), ('Payer la facture', 2, False))
        self.s.shift_card(c['id'], 1)
        self.assertEqual(self.s.find_column(c['col'])[1]['name'], 'En cours')
        self.s.set_card_done(c['id'])
        self.assertTrue(c['done'] and c['doneAt'])
        self.assertEqual(self.s.anchor['wins'][-1]['kind'], 'card')
        self.assertIsNone(self.s.add_card('   '))

    def test_plan(self):
        today = datetime.now()
        a = self.s.add_card('Peu urgent !9')
        b = self.s.add_card('En retard !7')
        b['due'] = C.day_string(today - timedelta(days=2))
        c = self.s.add_card('Tres prioritaire !1')
        plan = self.s.plan_cards(3)
        self.assertEqual([p['card']['text'] for p in plan], ['En retard', 'Tres prioritaire', 'Peu urgent'])
        self.assertIn('retard', plan[0]['why'])
        del a, c

    def test_kanban_piege(self):
        evil = {'boards': [{'id': '<x>', 'columns': [{'id': 'c1'}]}, {'id': 'ok', 'name': 'Bon', 'columns': [{'id': 'c9', 'name': 'A'}]}],
                'cards': [{'id': '<script>', 'text': '<b>gras</b>', 'board': 'ok', 'col': 'c9', 'prio': 999, 'due': 'pas une date',
                           'checks': 'pas une liste'}, 'pas un objet', None], 'focus': ['<x>'], 'current': '../../etc'}
        k = C.sanitize_kanban(evil)
        self.assertEqual([b['id'] for b in k['boards']], ['ok'])
        t = k['cards'][0]
        self.assertTrue(C.is_safe_id(t['id']) and t['prio'] == 10 and t['due'] == '' and t['checks'] == [])
        self.assertEqual(t['text'], '<b>gras</b>')
        self.assertEqual(k['focus'], [])
        self.assertEqual(k['current'], 'ok')
        self.assertEqual(len(C.sanitize_kanban('nimporte quoi')['boards']), 1)

    def test_fichier_du_pc(self):
        pc = {'current': 'b1', 'boards': [{'id': 'b1', 'name': 'Projet PC', 'columns': [
            {'id': 'c1', 'name': 'À faire', 'done': False}, {'id': 'c2', 'name': 'Terminé', 'done': True}]}],
            'cards': [{'id': 'k1', 'text': 'Carte PC', 'prio': 3, 'board': 'b1', 'col': 'c1', 'repeat': 'workdays'}]}
        k = C.sanitize_kanban(pc)
        self.assertEqual((k['boards'][0]['name'], k['cards'][0]['text'], k['cards'][0]['repeat']), ('Projet PC', 'Carte PC', 'workdays'))


class Chrono(unittest.TestCase):
    def test_cycle(self):
        s = C.State()
        c = s.add_card('Rapport')
        t0 = 1_000_000.0
        s.start_focus(t0)
        self.assertEqual(s.timer['state'], 'Focus')
        self.assertEqual(s.kanban['focus'], [c['id']])
        self.assertEqual(s.find_column(c['col'])[1]['name'], 'En cours')
        s.pause(t0 + 600)
        self.assertEqual(s.tick(t0 + 99999), '')
        s.resume(t0 + 1200)
        self.assertAlmostEqual(s.time_left(t0 + 1200), 2400, delta=1)
        self.assertEqual(s.tick(t0 + 1200 + 2401), 'focusEnded')
        self.assertEqual((s.timer['state'], c['pomos'], s.stats['focus']), ('AwaitBreak', 1, 1))
        self.assertTrue(any(w['kind'] == 'focus' for w in s.anchor['wins']))
        s.start_break(t0 + 4000)
        self.assertEqual(s.tick(t0 + 4000 + 601), 'breakEnded')
        self.assertEqual(s.timer['state'], 'AwaitFocus')

    def test_rythmes(self):
        self.assertEqual(C.rhythm_minutes({'rhythm': '25/5'}), (25, 5))
        self.assertEqual(C.rhythm_minutes({'rhythm': 'Perso', 'customFocus': 40, 'customBreak': 8}), (40, 8))

    def test_reglages_pieges(self):
        st = C.sanitize_settings({'rhythm': 'x', 'customFocus': -5, 'tickZoneMin': 99, 'sounds': 'oui', 'volume': 1e9})
        self.assertEqual((st['rhythm'], st['customFocus'], st['tickZoneMin'], st['sounds'], st['volume']), ('50/10', 1, 15, True, 100))


class ZoneFinale(unittest.TestCase):
    def test_tic_accelere(self):
        self.assertEqual(C.tick_interval(301, 300), 0)
        self.assertEqual([C.tick_interval(x, 300) for x in (300, 100, 45, 20, 5)], [20, 10, 5, 2, 1])

    def test_simulation(self):
        """Seconde par seconde, comme l'interface : aucun tic avant 5 min, puis de plus en plus vite."""
        ticks, nxt = [], 0
        for elapsed in range(3000):
            left = 3000 - elapsed
            iv = C.tick_interval(left, 300)
            if iv and elapsed >= nxt:
                ticks.append(left)
                nxt = elapsed + iv
        gaps = [a - b for a, b in zip(ticks, ticks[1:])]
        self.assertEqual(ticks[0], 300)
        self.assertTrue(all(g2 <= g1 for g1, g2 in zip(gaps, gaps[1:])), gaps)
        self.assertEqual(gaps[-1], 1)

    def test_couleurs(self):
        self.assertEqual([C.urgency_level(f, l) for f, l in ((0.8, 2400), (0.4, 1200), (0.2, 600), (0.02, 59))],
                         ['calm', 'mid', 'high', 'final'])


class Relance(unittest.TestCase):
    def test_relance(self):
        st = C.default_settings()
        t0 = datetime(2026, 10, 5, 10, 0).timestamp()
        self.assertFalse(C.idle_nudge_due(st, 'Idle', t0, t0 + 44 * 60))
        self.assertTrue(C.idle_nudge_due(st, 'Idle', t0, t0 + 45 * 60))
        self.assertFalse(C.idle_nudge_due(st, 'Focus', t0, t0 + 99 * 60))
        self.assertFalse(C.idle_nudge_due(st, 'Idle', t0, t0 + 60 * 60, '2026-10-05'))
        self.assertFalse(C.idle_nudge_due(dict(st, idleNudge=False), 'Idle', t0, t0 + 999 * 60))


class Sons(unittest.TestCase):
    def test_chacun_son_tour(self):
        bag = C.SoundBag(random.Random(4))
        items = ['a.wav', 'b.ogg', 'c.wav', 'd.flac']
        played = [bag.pick(items) for _ in range(40)]
        for r in range(10):
            self.assertEqual(sorted(played[r * 4:(r + 1) * 4]), sorted(items))
        self.assertFalse(any(a == b for a, b in zip(played, played[1:])))
        self.assertGreater(len({tuple(played[r * 4:(r + 1) * 4]) for r in range(10)}), 1)
        self.assertEqual(bag.pick(['seul.wav']), 'seul.wav')

    def test_dossier(self):
        with tempfile.TemporaryDirectory() as d:
            for n in ('a.wav', 'b.ogg', 'lisez-moi.txt'):
                open(os.path.join(d, n), 'w').close()
            self.assertEqual([os.path.basename(x) for x in C.list_sounds(d)], ['a.wav', 'b.ogg'])
            self.assertEqual(C.list_sounds(os.path.join(d, 'absent')), [])

    def test_wav(self):
        w = C.make_wav([(1046, 0.045, 0)], 50)
        self.assertEqual((w[:4], w[8:12]), (b'RIFF', b'WAVE'))
        self.assertEqual(int.from_bytes(w[4:8], 'little'), len(w) - 8)


class Sos(unittest.TestCase):
    def test_meme_decoupage_que_pc_et_telephone(self):
        expected = load('tests', 'fixtures', 'unstick-expected.json')
        diff = {t: C.decompose(t, RULES) for t, steps in expected.items() if C.decompose(t, RULES) != steps}
        self.assertEqual(diff, {})

    def test_deroule(self):
        s = C.State()
        s.start_unstick('Ranger le bureau', RULES)
        n0 = len(s.anchor['unstick']['steps'])
        s.unstick_smaller()
        self.assertEqual(len(s.anchor['unstick']['steps']), n0 + 1)
        r = ''
        for _ in range(20):
            r = s.unstick_step_done()
            if r == 'finished':
                break
        self.assertEqual(r, 'finished')
        self.assertIsNone(s.anchor['unstick'])
        self.assertTrue(s.anchor['wins'][-1]['title'].startswith('Débloqué'))
        self.assertIsNone(s.start_unstick('   ', RULES))


class NotesReprisesVictoires(unittest.TestCase):
    def test_notes(self):
        s = C.State()
        a = s.add_note('Première')
        b = s.add_note('Deuxième')
        a['pinned'] = True
        self.assertEqual([n['text'] for n in s.sorted_notes()], ['Première', 'Deuxième'])
        s.update_note(b['id'], '   ')
        self.assertEqual(len(s.notes), 1)
        self.assertEqual(C.note_title({'text': '\n\n  Titre  \nsuite'}), 'Titre')

    def test_reprises(self):
        s = C.State()
        s.add_card('Budget')
        s.start_focus()
        c = s.add_reprise('le tableau', 'ligne 2', title='budget.ods - LibreOffice', app='soffice')
        self.assertTrue(c['wasFocus'] and c['remindAt'] and c['focusCards'])
        self.assertEqual(C.reprise_title(c), 'ligne 2')
        self.assertIsNone(s.due_reprise())
        self.assertEqual(s.due_reprise(datetime.now() + timedelta(minutes=31))['id'], c['id'])
        s.complete_reprise(c['id'])
        self.assertEqual((s.open_reprises(), s.anchor['wins'][-1]['kind']), ([], 'reprise'))
        bad = C.sanitize_reprises([{'id': 'x', 'windows': [{'url': 'javascript:alert(1)', 'app': 'a";b'}]}])
        self.assertEqual((bad[0]['windows'][0]['url'], bad[0]['windows'][0]['app']), ('', 'ab'))

    def test_victoires(self):
        s = C.State()
        mon = datetime(2026, 10, 5, 9)
        s.add_win('Focus', 'focus', mon - timedelta(days=1))
        s.add_win('Carte', 'card', mon)
        self.assertEqual((len(s.wins_of_day(mon)), s.win_streak(mon)), (1, 2))

    def test_recherche(self):
        s = C.State()
        s.add_card('Payer la facture EDF')
        s.add_note('Idée cadeau Léa')
        r = s.search('lea cadeau')
        self.assertEqual((len(r['cards']), len(r['notes'])), (0, 1))
        self.assertEqual(len(s.search('FACTURE edf')['cards']), 1)

    def test_ancien_brain_dump(self):
        old = load('tests', 'fixtures', 'lifeanchor-telephone.json')
        s = C.State()
        s.anchor = C.sanitize_anchor(old)
        m = s.migrate_anchor()
        self.assertEqual((m['notes'], m['cards']), (1, 2))
        self.assertEqual(next(c for c in s.kanban['cards'] if c['text'].startswith('Boire'))['repeat'], 'daily')
        self.assertIsNone(s.migrate_anchor())


class Fichiers(unittest.TestCase):
    def test_enregistrer_relire(self):
        with tempfile.TemporaryDirectory() as d:
            st = C.Store(d)
            s = C.State()
            s.add_card('Carte ✓ 🚀')
            s.add_note('Note')
            s.start_focus()
            st.save(s)
            s2 = st.load()
            self.assertEqual((s2.kanban['cards'][0]['text'], len(s2.notes), s2.timer['state']), ('Carte ✓ 🚀', 1, 'Focus'))
            self.assertTrue(os.listdir(os.path.join(d, 'sauvegardes')))

    def test_fichier_abime(self):
        with tempfile.TemporaryDirectory() as d:
            st = C.Store(d)
            s = C.State()
            s.add_card('Sauvee')
            st.save(s)
            with open(os.path.join(d, 'kanban.json'), 'w') as f:
                f.write('{abime')
            s2 = C.Store(d).load()
            self.assertEqual(s2.kanban['cards'][0]['text'], 'Sauvee')   # reprise de la sauvegarde du jour
            self.assertTrue(any(f.startswith('kanban.json.illisible-') for f in os.listdir(d)))

    def test_fichiers_abimes_de_10_facons(self):
        for junk in ('', 'null', '[]', '"x"', '{"boards": 5}', '{"cards": [null, 1, "x"]}', '[{"text": null}]', '1e999', '{', '\x00\x01'):
            with tempfile.TemporaryDirectory() as d:
                for n in ('kanban.json', 'notes.json', 'reprises.json', 'lifeanchor.json', 'settings.json', 'etat.json'):
                    with open(os.path.join(d, n), 'w') as f:
                        f.write(junk)
                s = C.Store(d).load()
                self.assertTrue(s.kanban['boards'])

    def test_zip_avec_pc_et_telephone(self):
        s = C.State()
        s.add_card('Carte Linux')
        s.add_note('Note')
        s.add_win('Victoire', 'focus')
        data = C.export_zip(s)
        s2 = C.State()
        got = C.import_zip(s2, data)
        self.assertEqual(set(got), set(C.FILES))
        self.assertEqual((s2.kanban['cards'][0]['text'], s2.notes[0]['text'], s2.anchor['wins'][0]['title']),
                         ('Carte Linux', 'Note', 'Victoire'))
        # un zip du PC : dossier « Orbit\donnees », BOM, plus d'autres fichiers ignores
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('Orbit/orbit.ps1', '# programme')
            z.writestr('Orbit/donnees/notes.json', '﻿' + json.dumps([{'id': 'n1', 'text': 'Note du PC'}]))
        s3 = C.State()
        C.import_zip(s3, buf.getvalue())
        self.assertEqual(s3.notes[0]['text'], 'Note du PC')
        with self.assertRaises(ValueError):
            C.import_zip(C.State(), self._zip({'autre.txt': 'x'}))

    @staticmethod
    def _zip(files):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, 'w') as z:
            for k, v in files.items():
                z.writestr(k, v)
        return buf.getvalue()


if __name__ == '__main__':
    unittest.main(verbosity=1)
