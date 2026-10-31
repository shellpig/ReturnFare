import { describe, it, expect } from 'vitest';
import { readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { loadGameData } from '../src/data/loader';
import { loadGameDataNode } from '../src/data/load-node';
import type { DataFile, ReadText } from '../src/data/types';

const REPO_ROOT = resolve(__dirname, '..', '..');
const DATA_DIR = join(REPO_ROOT, 'data');

async function readJsonFile(rel: string): Promise<unknown> {
  return JSON.parse(await readFile(join(DATA_DIR, rel), 'utf8'));
}

async function sourceBeatCatalog(): Promise<{
  count: number;
  firstId: string | null;
  lastId: string | null;
}> {
  const files = (await readdir(join(DATA_DIR, 'beats'))).filter((f) => f.endsWith('.json')).sort();
  let count = 0;
  let firstId: string | null = null;
  let lastId: string | null = null;
  for (const f of files) {
    const d = (await readJsonFile(join('beats', f))) as { beats?: unknown[] };
    const beats = d.beats ?? [];
    count += beats.length;
    if (beats.length > 0) {
      if (firstId === null) {
        firstId = String((beats[0] as { id?: unknown }).id ?? '');
      }
      lastId = String((beats[beats.length - 1] as { id?: unknown }).id ?? '');
    }
  }
  return { count, firstId, lastId };
}

function asDataFile(path: string): DataFile {
  return { path, sha256: '0000000000000000000000000000000000000000000000000000000000000000' };
}

describe('W2-A data loader (real data)', () => {
  it('loads formal data with positive counts equal to the source arrays', async () => {
    const data = await loadGameDataNode();

    const sourceCards = (await readJsonFile('cards.json')) as { cards: unknown[] };
    const sourceLocations = (await readJsonFile('locations.json')) as {
      day: unknown[];
      night: unknown[];
    };
    const sourceNpcs = (await readJsonFile('npcs.json')) as { npcs: unknown[] };
    const beatCatalog = await sourceBeatCatalog();
    const sourceEndingsRaw = await readJsonFile('endings.json');
    const sourceOpeningRaw = await readJsonFile('opening_choices.json');

    expect(data.cards.length).toBeGreaterThan(0);
    expect(data.cards.length).toBe(sourceCards.cards.length);
    expect(data.locations.length).toBeGreaterThan(0);
    expect(data.locations.length).toBe(
      sourceLocations.day.length + sourceLocations.night.length,
    );
    expect(data.npcs.length).toBeGreaterThan(0);
    expect(data.npcs.length).toBe(sourceNpcs.npcs.length);
    expect(data.beats.length).toBeGreaterThan(0);
    expect(data.beats.length).toBe(beatCatalog.count);
    const sourceEndings = Array.isArray(sourceEndingsRaw)
      ? sourceEndingsRaw
      : ((sourceEndingsRaw as { endings?: unknown[] }).endings ?? []);
    expect(data.endings.length).toBe(sourceEndings.length);
    const sourceOpening = Array.isArray(sourceOpeningRaw)
      ? sourceOpeningRaw
      : ((sourceOpeningRaw as { opening_choices?: unknown[] }).opening_choices ?? []);
    expect(data.openingChoices.length).toBe(sourceOpening.length);
    expect(data.cardTypes.length).toBeGreaterThan(0);
    expect(data.openingScreen).toBeDefined();
  });

  it('beat order equals filename-sorted concatenation; indexes agree with arrays', async () => {
    const data = await loadGameDataNode();
    const catalog = await sourceBeatCatalog();

    expect(data.beats[0].id).toBe(catalog.firstId);
    expect(data.beats[data.beats.length - 1].id).toBe(catalog.lastId);

    const collections: Array<{
      arr: readonly { id: string }[];
      map: ReadonlyMap<string, { id: string }>;
    }> = [
      { arr: data.cards, map: data.cardsById },
      { arr: data.locations, map: data.locationsById },
      { arr: data.npcs, map: data.npcsById },
      { arr: data.beats, map: data.beatsById },
      { arr: data.endings, map: data.endingsById },
      { arr: data.openingChoices, map: data.openingChoicesById },
    ];
    for (const coll of collections) {
      expect(coll.map.size).toBe(coll.arr.length);
      for (const item of coll.arr) {
        expect(coll.map.get(item.id)).toBe(item);
      }
    }
    expect(data.cardTypesById.size).toBe(data.cardTypes.length);
    for (const ct of data.cardTypes) {
      expect(data.cardTypesById.get(ct.id)).toBe(ct);
    }
  });

  it('second load creates fresh objects and does not accumulate', async () => {
    const first = await loadGameDataNode();
    const second = await loadGameDataNode();
    expect(first).not.toBe(second);
    expect(first.cards).not.toBe(second.cards);
    expect(first.beatsById).not.toBe(second.beatsById);
    expect(second.cards.length).toBe(first.cards.length);
    expect(second.beats.length).toBe(first.beats.length);
    expect(second.cardsById.size).toBe(first.cardsById.size);
    expect(second.beatsById.size).toBe(first.beatsById.size);
  });

  it('duplicate beat id across beat files rejects with the relative file name', async () => {
    const files: Record<string, string> = {
      'tuning.json': '{}',
      'relation_scale.json': '{}',
      'card_types.json': JSON.stringify({ card_types: [] }),
      'cards.json': JSON.stringify({ cards: [] }),
      'locations.json': JSON.stringify({ day: [], night: [] }),
      'npcs.json': JSON.stringify({ npcs: [] }),
      'opening_choices.json': JSON.stringify({ screen: {}, opening_choices: [] }),
      'endings.json': '[]',
      'beats/a.json': JSON.stringify({ beats: [{ id: 'dup_beat', location: 'sanquan' }] }),
      'beats/b.json': JSON.stringify({ beats: [{ id: 'dup_beat', location: 'jinghe' }] }),
    };
    const manifest = Object.keys(files).map(asDataFile);
    const readText: ReadText = async (relPath: string) => {
      if (!(relPath in files)) {
        throw new Error(`ENOENT: no such file '${relPath}'`);
      }
      return files[relPath];
    };

    let caught: Error | null = null;
    try {
      await loadGameData(readText, manifest);
    } catch (err) {
      caught = err instanceof Error ? err : new Error(String(err));
    }
    expect(caught).not.toBeNull();
    const msg = caught!.message;
    expect(msg).toContain('重複');
    expect(msg).toContain('.json');
  });

  it('beat.when 同時包含 day 與 day_from rejects with the relative file name', async () => {
    const files: Record<string, string> = {
      'tuning.json': '{}',
      'relation_scale.json': '{}',
      'card_types.json': JSON.stringify({ card_types: [] }),
      'cards.json': JSON.stringify({ cards: [] }),
      'locations.json': JSON.stringify({ day: [], night: [] }),
      'npcs.json': JSON.stringify({ npcs: [] }),
      'opening_choices.json': JSON.stringify({ screen: {}, opening_choices: [] }),
      'endings.json': '[]',
      'beats/a.json': JSON.stringify({
        beats: [{ id: 'bad_when', location: 'sanquan', when: { day: 3, day_from: 1 } }],
      }),
    };
    const manifest = Object.keys(files).map(asDataFile);
    const readText: ReadText = async (relPath: string) => {
      if (!(relPath in files)) {
        throw new Error(`ENOENT: no such file '${relPath}'`);
      }
      return files[relPath];
    };

    let caught: Error | null = null;
    try {
      await loadGameData(readText, manifest);
    } catch (err) {
      caught = err instanceof Error ? err : new Error(String(err));
    }
    expect(caught).not.toBeNull();
    const msg = caught!.message;
    expect(msg).toContain('day');
    expect(msg).toContain('day_from');
    expect(msg).toContain('.json');
  });

  it('missing required file rejects with the relative file name', async () => {
    const files: Record<string, string> = {
      'relation_scale.json': '{}',
      'card_types.json': JSON.stringify({ card_types: [] }),
      'cards.json': JSON.stringify({ cards: [] }),
      'locations.json': JSON.stringify({ day: [], night: [] }),
      'npcs.json': JSON.stringify({ npcs: [] }),
      'opening_choices.json': JSON.stringify({ screen: {}, opening_choices: [] }),
      'endings.json': '[]',
    };
    const manifest = Object.keys(files).map(asDataFile);
    const readText: ReadText = async () => {
      throw new Error('ENOENT: no such file');
    };

    let caught: Error | null = null;
    try {
      await loadGameData(readText, manifest);
    } catch (err) {
      caught = err instanceof Error ? err : new Error(String(err));
    }
    expect(caught).not.toBeNull();
    expect(caught!.message).toContain('tuning.json');
  });
});
