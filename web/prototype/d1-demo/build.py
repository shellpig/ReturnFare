import io, json, os
S = os.path.dirname(os.path.abspath(__file__))
R = os.path.join(S, '..', '..', '..', 'data', '')
L = lambda p: json.load(io.open(R + p, encoding='utf-8'))
op = L('opening_choices.json')
bs = L('beats/ch1_d01_d03.json')
bs = bs if isinstance(bs, list) else bs['beats']
ids = ['d1_morning_phone', 'd1_morning_departure', 'd1_pm_mountain_road', 'd1_arrival']
beats = {b['id']: {k: b[k] for k in ('title', 'text', 'slots', 'on_enter') if k in b} for b in bs if b['id'] in ids}
assert set(beats) == set(ids)
card = [c for c in L('cards.json')['cards'] if c['id'] == 'protagonist'][0]
loc = [l for l in L('locations.json')['day'] if l['id'] == 'busstop'][0]
data = {
    'opening': {'screen': op['screen'], 'choices': [{k: c.get(k) for k in ('id', 'label', 'preview', 'confirm_text', 'requires', 'reject_reason')} for c in op['opening_choices']]},
    'beats': beats, 'card': {'name': card['name'], 'text': card['text']}, 'loc': {'name': loc['name'], 'desc': loc['desc']}}
t = io.open(os.path.join(S, 'tpl.html'), encoding='utf-8').read().replace('__DATA__', json.dumps(data, ensure_ascii=False))
io.open(os.path.join(S, 'returnfare-d1-demo.html'), 'w', encoding='utf-8').write(t)
print(len(t))
