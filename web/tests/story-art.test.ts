import { describe, it, expect, beforeAll } from 'vitest';
import { existsSync } from 'node:fs';
import { loadGameDataNode } from '../src/data/load-node';
import type { GameData } from '../src/data/types';
import { OPENING_ART, STORY_ART, storyArtFor } from '../src/ui/story-art';

describe('敘事插圖對照', () => {
  let data: GameData;
  beforeAll(async () => {
    data = await loadGameDataNode();
  });

  it('每個對照的 beat 存在、有正文，且以正文反查得到自己的圖檔', () => {
    for (const [beatId, src] of Object.entries(STORY_ART)) {
      const text = data.beatsById.get(beatId)?.text;
      expect(text, beatId).toBeTruthy();
      expect(storyArtFor(data, text)).toBe(src);
    }
  });

  it('圖檔都在 public/ 下', () => {
    for (const src of [OPENING_ART, ...Object.values(STORY_ART)]) {
      expect(existsSync(`public${src}`), src).toBe(true);
    }
  });

  it('未對照的段落與空段落不顯示圖', () => {
    expect(storyArtFor(data, data.beatsById.get('d1_morning_phone')?.text)).toBeNull();
    expect(storyArtFor(data, '')).toBeNull();
    expect(storyArtFor(data, undefined)).toBeNull();
  });
});
