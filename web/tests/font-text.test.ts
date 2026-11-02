import { describe, it, expect } from 'vitest';
import { mkdtemp, rm, writeFile, readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { collectFontCorpus, extractCssStrings } from '../scripts/collect-font-text';

async function pathExists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

describe('collectFontCorpus', () => {
  it('collects expected corpus from real project data, src, html, and ascii', () => {
    const result = collectFontCorpus();
    // Prompt audit confirms at least 2291 visible characters
    expect(result.charCount).toBeGreaterThanOrEqual(2291);
    expect(result.dataCharsCount).toBeGreaterThan(2000);
    expect(result.srcCharsCount).toBeGreaterThan(500);
    expect(result.asciiCharsCount).toBe(95);

    // Key domain characters
    expect(result.characters).toContain('溫');
    expect(result.characters).toContain('泉');
    expect(result.characters).toContain('小');
    expect(result.characters).toContain('鎮');
    expect(result.characters).toContain('霧');
    expect(result.characters).toContain('神');
    expect(result.characters).toContain('秘');

    // UI and template strings
    expect(result.characters).toContain('存');
    expect(result.characters).toContain('讀');
    expect(result.characters).toContain('檔');
    expect(result.characters).toContain('朝');
    expect(result.characters).toContain('夕');
    expect(result.characters).toContain('夜');

    // CSS content strings (e.g. .slot-occupant brackets U+3014 and U+3015)
    expect(result.characters).toContain('\u3014'); // '〔'
    expect(result.characters).toContain('\u3015'); // '〕'

    // Nonprinting controls must be excluded
    expect(result.characters).not.toContain('\n');
    expect(result.characters).not.toContain('\r');
    expect(result.characters).not.toContain('\t');
    expect(result.characters).not.toContain('\uFE0F');

    const excludedPoints = result.excludedControls.map(c => c.codePoint);
    expect(excludedPoints).toContain('U+000A');
    expect(excludedPoints).toContain('U+FE0F');

    // Characters must be deterministically sorted by Unicode code point
    const characters = Array.from(result.characters);
    for (let i = 1; i < characters.length; i++) {
      const prevCode = characters[i - 1].codePointAt(0) ?? 0;
      const currCode = characters[i].codePointAt(0) ?? 0;
      expect(currCode).toBeGreaterThan(prevCode);
    }
  });

  it('extracts template head/tail, escaped Unicode strings, JSX text, and JSON values from synthetic project', async () => {
    const tmp = await mkdtemp(join(tmpdir(), 'rf-font-synthetic-'));
    try {
      const dataDir = join(tmp, 'data');
      const webSrcDir = join(tmp, 'web', 'src');
      await import('node:fs').then(fs => {
        fs.mkdirSync(dataDir, { recursive: true });
        fs.mkdirSync(webSrcDir, { recursive: true });
      });

      // 1. JSON file with unique marker '曚'
      await writeFile(join(dataDir, 'test.json'), JSON.stringify({ marker: '曚𠮷' }));

      // 2. TSX file with literal '曖', template head '曜' / tail '曙', escaped unicode '\u66e6' ('曦'), JSX text '晞'
      const tsxContent = `
        import React from 'react';
        const literal = '曖';
        const interpolated = '中間';
        const templated = \`曜\${interpolated}曙\`;
        const escaped = "前置\\u66e6後置\\n\\uFE0F";
        export const MyComp = () => <div>晞</div>;
      `;
      await writeFile(join(webSrcDir, 'Sample.tsx'), tsxContent);

      const outCorpus = join(tmp, 'synthetic-corpus.txt');
      const result = collectFontCorpus({
        rootDir: tmp,
        outputPath: outCorpus,
      });

      // JSON string value
      expect(result.characters).toContain('曚');
      expect(Array.from(result.characters)).toContain('𠮷');
      expect(result.charCount).toBe(Array.from(result.characters).length);
      // String literal
      expect(result.characters).toContain('曖');
      // Template head ('曜') and template tail ('曙')
      expect(result.characters).toContain('曜');
      expect(result.characters).toContain('曙');
      // Escaped unicode ('\u66e6' -> '曦')
      expect(result.characters).toContain('曦');
      // JSX text ('晞')
      expect(result.characters).toContain('晞');

      // Controls in strings must be excluded
      expect(result.characters).not.toContain('\n');
      expect(result.characters).not.toContain('\uFE0F');

      // Verify file output contains these markers
      const fileContent = await readFile(outCorpus, 'utf8');
      expect(fileContent).toBe(result.characters);
    } finally {
      await rm(tmp, { recursive: true, force: true });
    }
  });

  it('extracts CSS quoted literals, hex escapes, whitespace terminators, escaped quotes/newlines, and ignores comments', async () => {
    expect(extractCssStrings(String.raw`.box { content: "\0\D800\110000"; }`))
      .toEqual(['\uFFFD'.repeat(3)]);
    const tmp = await mkdtemp(join(tmpdir(), 'rf-font-css-'));
    try {
      const dataDir = join(tmp, 'data');
      const webSrcDir = join(tmp, 'web', 'src');
      const subCssDir = join(webSrcDir, 'nested', 'theme');
      await import('node:fs').then(fs => {
        fs.mkdirSync(dataDir, { recursive: true });
        fs.mkdirSync(subCssDir, { recursive: true });
      });

      await writeFile(join(dataDir, 'test.json'), JSON.stringify({ marker: '基' }));
      await writeFile(join(webSrcDir, 'main.ts'), 'export const x = "本";');

      // CSS containing:
      // - Direct non-ASCII literal: '【' (U+3010)
      // - CSS hex escape with whitespace terminator: '\3011 ' (U+3011, '】')
      // - Escaped quote & backslash: "引\"號\\反"
      // - Multiline continuation: "連\
      // 續"
      // - Comment-like string: "/*非註解*/"
      // - CSS comment with unique marker: /* 註解隱藏字元 */
      const cssContent = `
        /* comment with hidden marker 隱 */
        .box::before {
          content: '【';
        }
        .box::after {
          content: '\\3011 ';
        }
        .quote {
          content: "引\\"號\\\\反";
        }
        .multi {
          content: "連\\
續";
        }
        .pseudo-comment {
          content: "/*非註解*/";
        }
      `;
      await writeFile(join(subCssDir, 'custom.css'), cssContent);

      const result = collectFontCorpus({ rootDir: tmp });

      // Direct literal
      expect(result.characters).toContain('【');
      // Hex escape \3011
      expect(result.characters).toContain('】');
      // Escaped quote and backslash
      expect(result.characters).toContain('引');
      expect(result.characters).toContain('號');
      expect(result.characters).toContain('反');
      expect(result.characters).toContain('"');
      expect(result.characters).toContain('\\');
      // Multiline continuation
      expect(result.characters).toContain('連');
      expect(result.characters).toContain('續');
      // String containing comment syntax
      expect(result.characters).toContain('非');
      expect(result.characters).toContain('註');
      // Comment marker '隱' MUST NOT be in corpus
      expect(result.characters).not.toContain('隱');
    } finally {
      await rm(tmp, { recursive: true, force: true });
    }
  });

  it('fails and does NOT create output files when JSON is malformed', async () => {
    const tmp = await mkdtemp(join(tmpdir(), 'rf-font-test-malformed-'));
    try {
      const dataDir = join(tmp, 'data');
      const webSrcDir = join(tmp, 'web', 'src');
      await import('node:fs').then(fs => {
        fs.mkdirSync(dataDir, { recursive: true });
        fs.mkdirSync(webSrcDir, { recursive: true });
      });

      await writeFile(join(dataDir, 'bad.json'), '{\n  "broken": unquoted_value\n}');
      await writeFile(join(webSrcDir, 'index.ts'), 'export const a = "hello";');

      const outCorpus = join(tmp, 'output-corpus.txt');
      const outMeta = join(tmp, 'output-meta.json');

      expect(() => {
        collectFontCorpus({
          rootDir: tmp,
          outputPath: outCorpus,
          metaPath: outMeta,
        });
      }).toThrow(/Failed to parse JSON file.*bad\.json/);

      // Verify that neither output file was created
      expect(await pathExists(outCorpus)).toBe(false);
      expect(await pathExists(outMeta)).toBe(false);
    } finally {
      await rm(tmp, { recursive: true, force: true });
    }
  });

  it('fails clearly when data directory is missing', async () => {
    const tmp = await mkdtemp(join(tmpdir(), 'rf-font-test-nodata-'));
    try {
      const webSrcDir = join(tmp, 'web', 'src');
      await import('node:fs').then(fs => {
        fs.mkdirSync(webSrcDir, { recursive: true });
      });
      await writeFile(join(webSrcDir, 'main.ts'), 'console.log("ok");');

      expect(() => {
        collectFontCorpus({ rootDir: tmp });
      }).toThrow(/Data directory not found/);
    } finally {
      await rm(tmp, { recursive: true, force: true });
    }
  });

  it('fails clearly when web src directory is missing', async () => {
    const tmp = await mkdtemp(join(tmpdir(), 'rf-font-test-nosrc-'));
    try {
      const dataDir = join(tmp, 'data');
      await import('node:fs').then(fs => {
        fs.mkdirSync(dataDir, { recursive: true });
      });
      await writeFile(join(dataDir, 'sample.json'), JSON.stringify({ key: 'val' }));

      expect(() => {
        collectFontCorpus({ rootDir: tmp });
      }).toThrow(/Web src directory not found/);
    } finally {
      await rm(tmp, { recursive: true, force: true });
    }
  });
});
