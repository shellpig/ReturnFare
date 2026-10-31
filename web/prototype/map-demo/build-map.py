import io, json, os, sys
try: sys.stdout.reconfigure(encoding='utf-8')
except Exception: pass
S = os.path.dirname(os.path.abspath(__file__))
R = os.path.join(S, '..', '..', '..', 'data', '')
L = lambda p: json.load(io.open(R + p, encoding='utf-8'))
DAY, PHASE, CH = 9, 'afternoon', 1
bs = L('beats/ch1_d04_d15.json'); bs = bs if isinstance(bs, list) else bs['beats']
day = [b for b in bs if b.get('when') == {'day': DAY, 'phase': PHASE}]
assert len(day) == 5 and sum(len(b['slots']) for b in day) == 6
beats = [{k: b[k] for k in ('id', 'location', 'title', 'text', 'slots') if k in b} for b in day]
LJ = json.load(io.open(os.path.join(S, '..', 'map-calibration', 'locations-proposed.json'), encoding='utf-8'))
assert len(LJ['day']) == 20 and len(LJ['night']) == 28
# spec section 4: day map lists chapter <= current and phases contains current phase
locs = [{'id': l['id'], 'name': l['name'], 'desc': l['desc'], 'x': l['map']['x'], 'y': l['map']['y'],
         'avail': l['chapter'] <= CH and PHASE in l['phases']} for l in LJ['day']]
assert {b['location'] for b in beats} <= {l['id'] for l in locs if l['avail']}
# spec section 9: night rows appear once earliest_night <= today; teaser_only never listed as available. night_reveal / madness_cost are NOT exported.
night = [{'id': l['id'], 'name': l['name'], 'x': l['map']['x'], 'y': l['map']['y'], 'cp': l.get('day_counterpart'),
          'avail': l['chapter'] <= CH and not l.get('teaser_only') and l['earliest_night'] <= DAY} for l in LJ['night']]
cards = {c['id']: {k: c[k] for k in ('type', 'name', 'text')} for c in L('cards.json')['cards']}
types = {t['id']: t['name'] for t in L('card_types.json')['card_types']}
npcs = {n['id']: n['name'] for n in L('npcs.json')['npcs']}
alias = {'npc_student': 'grad_student'}
occ = {}
for b in beats:
    for s in b['slots']:
        o = s.get('occupant')
        if o: occ[o] = npcs[alias.get(o, o[4:])]
data = {'day': DAY, 'phase': '下午', 'beats': beats, 'locs': locs, 'night': night, 'cards': cards, 'types': types, 'occ': occ, 'hand_size': L('tuning.json')['hand_size']}
t = io.open(os.path.join(S, 'tpl-map.html'), encoding='utf-8').read().replace('__DATA__', json.dumps(data, ensure_ascii=False))
io.open(os.path.join(S, 'returnfare-map-demo.html'), 'w', encoding='utf-8').write(t)
print(len(t), sum(l['avail'] for l in locs), 'day avail;', sum(l['avail'] for l in night), 'night avail;', [l['name'] for l in night if l['avail']])
