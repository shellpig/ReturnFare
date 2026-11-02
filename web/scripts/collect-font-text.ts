import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';

/**
 * ReturnFare UTF-8 Font Corpus Collector (W7-C)
 *
 * Deterministically extracts the complete required visible character set for font subsetting:
 * 1. Recursively all formal root `data/**\/*.json` string VALUES (not copied public data).
 * 2. Static string & template literals (including interpolated static chunks) and JSX text across `web/src/**\/*.{ts,tsx}`.
 * 3. Decoded quoted strings across `web/src/**\/*.css`, including generated content.
 * 4. Static visible text and attributes in `web/index.html` (e.g. title, loading UI).
 * 5. Full printable ASCII character set (0x20..0x7E).
 *
 * Filters only nonprinting control / formatting characters with explicit justification.
 * Emits a deterministic, codepoint-sorted UTF-8 character file and structured metadata.
 */

export interface ExcludedControl {
  codePoint: string;
  charRepr: string;
  justification: string;
  occurrences: number;
}

export interface CollectCorpusOptions {
  rootDir?: string;
  outputPath?: string;
  metaPath?: string;
}

export interface CollectCorpusResult {
  characters: string;
  charCount: number;
  dataCharsCount: number;
  srcCharsCount: number;
  cssCharsCount: number;
  asciiCharsCount: number;
  htmlCharsCount: number;
  excludedControls: ExcludedControl[];
  outputPath?: string;
  metaPath?: string;
}

/** Check if character is a nonprinting control or format character. */
function getControlJustification(code: number): string | null {
  if (code === 0x000a) {
    return 'Line Feed (\\n): Whitespace layout character handled by layout engine, not rendered as font glyph.';
  }
  if (code === 0x000d) {
    return 'Carriage Return (\\r): Whitespace layout character.';
  }
  if (code === 0x0009) {
    return 'Horizontal Tab (\\t): Whitespace layout character.';
  }
  if (code < 0x0020) {
    return 'C0 control code: Nonprinting control character.';
  }
  if (code >= 0x007f && code <= 0x009f) {
    return 'Delete / C1 control code: Nonprinting control character.';
  }
  if ((code >= 0xfe00 && code <= 0xfe0f) || (code >= 0xe0100 && code <= 0xe01ef)) {
    return 'Unicode Variation Selector: Non-spacing modifier for emoji/variant glyph selection without independent visual glyph.';
  }
  return null;
}

function findProjectRoot(startDir: string): string {
  let curr = path.resolve(startDir);
  for (let i = 0; i < 5; i++) {
    if (fs.existsSync(path.join(curr, 'data')) && fs.existsSync(path.join(curr, 'web'))) {
      return curr;
    }
    const parent = path.dirname(curr);
    if (parent === curr) break;
    curr = parent;
  }
  return path.resolve(startDir);
}

function getFilesRecursively(dir: string, predicate: (filePath: string) => boolean): string[] {
  if (!fs.existsSync(dir)) return [];
  const results: string[] = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...getFilesRecursively(fullPath, predicate));
    } else if (predicate(fullPath)) {
      results.push(fullPath);
    }
  }
  return results;
}

/**
 * Extract decoded string literals from CSS content.
 * Correctly skips CSS comments (/* ... *\/) without stripping comments inside strings.
 * Decodes CSS escapes:
 * 1. Escaped newline continuations (\ followed by \n or \r\n) -> omitted.
 * 2. Hexadecimal escapes (1 to 6 hex digits) with optional trailing whitespace delimiter.
 * 3. Escaped punctuation and quotes (\', \", \\, etc.).
 */
export function extractCssStrings(css: string): string[] {
  const strings: string[] = [];
  let i = 0;
  const len = css.length;

  while (i < len) {
    // 1. Skip CSS comments outside strings
    if (css[i] === '/' && css[i + 1] === '*') {
      i += 2;
      while (i < len && !(css[i] === '*' && css[i + 1] === '/')) {
        i++;
      }
      i += 2; // skip */
      continue;
    }

    // 2. Identify quoted string literal
    if (css[i] === '"' || css[i] === "'") {
      const quote = css[i];
      i++;
      let decoded = '';

      while (i < len) {
        const ch = css[i];

        if (ch === '\\') {
          i++;
          if (i >= len) break;
          const nextCh = css[i];

          // 2a. Escaped newline continuation
          if (nextCh === '\r' && css[i + 1] === '\n') {
            i += 2;
            continue;
          }
          if (nextCh === '\n' || nextCh === '\r' || nextCh === '\f') {
            i++;
            continue;
          }

          // 2b. Hexadecimal escape (1 to 6 hex digits)
          if (/[0-9a-fA-F]/.test(nextCh)) {
            let hexStr = '';
            while (i < len && hexStr.length < 6 && /[0-9a-fA-F]/.test(css[i])) {
              hexStr += css[i];
              i++;
            }
            const code = parseInt(hexStr, 16);
            if (!Number.isNaN(code)) {
              const scalar = code === 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)
                ? 0xfffd : code;
              decoded += String.fromCodePoint(scalar);
            }
            // Optional trailing whitespace delimiter in CSS hex escape
            if (i < len) {
              if (css[i] === ' ' || css[i] === '\t' || css[i] === '\n' || css[i] === '\r' || css[i] === '\f') {
                if (css[i] === '\r' && css[i + 1] === '\n') {
                  i += 2;
                } else {
                  i++;
                }
              }
            }
            continue;
          }

          // 2c. Escaped character
          decoded += nextCh;
          i++;
          continue;
        }

        if (ch === quote) {
          i++; // close quote
          break;
        }

        // Unescaped newline terminates string in CSS
        if (ch === '\n' || ch === '\r') {
          break;
        }

        decoded += ch;
        i++;
      }

      strings.push(decoded);
      continue;
    }

    i++;
  }

  return strings;
}

export function collectFontCorpus(options: CollectCorpusOptions = {}): CollectCorpusResult {
  const rootDir = options.rootDir ? path.resolve(options.rootDir) : findProjectRoot(process.cwd());
  const dataDir = path.join(rootDir, 'data');
  const webSrcDir = path.join(rootDir, 'web', 'src');
  const indexHtmlPath = path.join(rootDir, 'web', 'index.html');

  const rawCharSet = new Set<string>();
  const dataCharSet = new Set<string>();
  const srcCharSet = new Set<string>();
  const cssCharSet = new Set<string>();
  const htmlCharSet = new Set<string>();
  const asciiCharSet = new Set<string>();
  const controlOccurrences = new Map<number, number>();

  function recordChar(ch: string, sourceCategory: 'data' | 'src' | 'css' | 'html' | 'ascii'): void {
    rawCharSet.add(ch);
    if (sourceCategory === 'data') dataCharSet.add(ch);
    else if (sourceCategory === 'src') srcCharSet.add(ch);
    else if (sourceCategory === 'css') cssCharSet.add(ch);
    else if (sourceCategory === 'html') htmlCharSet.add(ch);
    else if (sourceCategory === 'ascii') asciiCharSet.add(ch);

    const code = ch.codePointAt(0);
    if (code !== undefined) {
      if (getControlJustification(code) !== null) {
        controlOccurrences.set(code, (controlOccurrences.get(code) ?? 0) + 1);
      }
    }
  }

  function recordString(str: string, sourceCategory: 'data' | 'src' | 'css' | 'html' | 'ascii'): void {
    for (const ch of Array.from(str)) {
      recordChar(ch, sourceCategory);
    }
  }

  // 1. Walk data/**/*.json string values
  if (!fs.existsSync(dataDir)) {
    throw new Error(`Data directory not found: ${dataDir}`);
  }
  const jsonFiles = getFilesRecursively(dataDir, f => f.endsWith('.json'));
  if (jsonFiles.length === 0) {
    throw new Error(`No JSON files found in data directory: ${dataDir}`);
  }

  for (const jsonFile of jsonFiles) {
    const content = fs.readFileSync(jsonFile, 'utf8');
    let parsed: unknown;
    try {
      parsed = JSON.parse(content);
    } catch (err) {
      throw new Error(`Failed to parse JSON file ${jsonFile}: ${err instanceof Error ? err.message : String(err)}`);
    }
    function walk(val: unknown): void {
      if (typeof val === 'string') {
        recordString(val, 'data');
      } else if (Array.isArray(val)) {
        for (const item of val) walk(item);
      } else if (val && typeof val === 'object') {
        for (const v of Object.values(val)) walk(v);
      }
    }
    walk(parsed);
  }

  // 2. TypeScript Compiler AST scan across web/src/**/*.{ts,tsx}
  if (!fs.existsSync(webSrcDir)) {
    throw new Error(`Web src directory not found: ${webSrcDir}`);
  }
  const tsFiles = getFilesRecursively(webSrcDir, f => f.endsWith('.ts') || f.endsWith('.tsx'));
  if (tsFiles.length === 0) {
    throw new Error(`No TypeScript files found in web src directory: ${webSrcDir}`);
  }
  for (const tsFile of tsFiles) {
    const code = fs.readFileSync(tsFile, 'utf8');
    const sourceFile = ts.createSourceFile(tsFile, code, ts.ScriptTarget.Latest, true);

    function visit(node: ts.Node): void {
      if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) {
        recordString(node.text, 'src');
      } else if (ts.isTemplateHead(node) || ts.isTemplateMiddle(node) || ts.isTemplateTail(node)) {
        recordString(node.text, 'src');
      } else if (ts.isJsxText(node)) {
        recordString(node.text, 'src');
      }
      ts.forEachChild(node, visit);
    }
    visit(sourceFile);
  }

  // 3. Scan CSS files across web/src/**/*.css
  const cssFiles = getFilesRecursively(webSrcDir, f => f.endsWith('.css'));
  for (const cssFile of cssFiles) {
    const code = fs.readFileSync(cssFile, 'utf8');
    const strings = extractCssStrings(code);
    for (const str of strings) {
      recordString(str, 'css');
    }
  }

  // 4. Scan web/index.html (title, loading markup, attributes)
  if (fs.existsSync(indexHtmlPath)) {
    const html = fs.readFileSync(indexHtmlPath, 'utf8');
    // Extract text between tags
    const textMatches = html.match(/>([^<]+)</g);
    if (textMatches) {
      for (const m of textMatches) {
        const text = m.slice(1, -1).trim();
        if (text) recordString(text, 'html');
      }
    }
    // Extract attribute values (like aria-label="載入進度")
    const attrMatches = html.match(/=["']([^"']+)["']/g);
    if (attrMatches) {
      for (const a of attrMatches) {
        const val = a.slice(2, -1).trim();
        if (val) recordString(val, 'html');
      }
    }
  }

  // 5. Full printable ASCII (0x20..0x7E)
  for (let c = 0x20; c <= 0x7e; c++) {
    recordChar(String.fromCharCode(c), 'ascii');
  }

  // Filter out nonprinting controls
  const visibleChars: string[] = [];
  const excludedControls: ExcludedControl[] = [];

  for (const ch of rawCharSet) {
    const code = ch.codePointAt(0);
    if (code === undefined) continue;
    const justification = getControlJustification(code);
    if (justification) {
      excludedControls.push({
        codePoint: `U+${code.toString(16).toUpperCase().padStart(4, '0')}`,
        charRepr: JSON.stringify(ch),
        justification,
        occurrences: controlOccurrences.get(code) ?? 1,
      });
    } else {
      visibleChars.push(ch);
    }
  }

  // Sort deterministically by Unicode code point
  visibleChars.sort((a, b) => (a.codePointAt(0) ?? 0) - (b.codePointAt(0) ?? 0));
  excludedControls.sort((a, b) => a.codePoint.localeCompare(b.codePoint));

  const sortedCorpus = visibleChars.join('');

  // Write outputs if requested
  const resolvedOutputPath = options.outputPath ? path.resolve(options.outputPath) : undefined;
  const resolvedMetaPath = options.metaPath ? path.resolve(options.metaPath) : undefined;

  if (resolvedOutputPath) {
    fs.mkdirSync(path.dirname(resolvedOutputPath), { recursive: true });
    fs.writeFileSync(resolvedOutputPath, sortedCorpus, 'utf8');
  }

  if (resolvedMetaPath) {
    fs.mkdirSync(path.dirname(resolvedMetaPath), { recursive: true });
    const meta = {
      totalRequiredCharacters: visibleChars.length,
      dataCharactersCount: dataCharSet.size,
      srcCharactersCount: srcCharSet.size,
      cssCharactersCount: cssCharSet.size,
      asciiCharactersCount: asciiCharSet.size,
      htmlCharactersCount: htmlCharSet.size,
      excludedControls,
      generatedAt: new Date().toISOString(),
    };
    fs.writeFileSync(resolvedMetaPath, JSON.stringify(meta, null, 2), 'utf8');
  }

  return {
    characters: sortedCorpus,
    charCount: visibleChars.length,
    dataCharsCount: dataCharSet.size,
    srcCharsCount: srcCharSet.size,
    cssCharsCount: cssCharSet.size,
    asciiCharsCount: asciiCharSet.size,
    htmlCharsCount: htmlCharSet.size,
    excludedControls,
    outputPath: resolvedOutputPath,
    metaPath: resolvedMetaPath,
  };
}

// CLI entry point
const isDirectRun = process.argv[1] && /collect-font-text\.(ts|js|mjs)$/.test(process.argv[1]);
if (isDirectRun) {
  try {
    const args = process.argv.slice(2);
    let outPath: string | undefined;
    let metaPath: string | undefined;

    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--output' || args[i] === '-o') {
        outPath = args[++i];
      } else if (args[i] === '--meta' || args[i] === '-m') {
        metaPath = args[++i];
      }
    }

    const root = findProjectRoot(process.cwd());
    const defaultOutput = outPath ?? path.join(root, '_qa', 'fonts', 'corpus.txt');
    const defaultMeta = metaPath ?? path.join(root, '_qa', 'fonts', 'corpus-meta.json');

    const result = collectFontCorpus({
      rootDir: root,
      outputPath: defaultOutput,
      metaPath: defaultMeta,
    });

    console.log(`[collect-font-text] Collected ${result.charCount} required visible characters.`);
    console.log(`  Source breakdown: data=${result.dataCharsCount}, src=${result.srcCharsCount}, css=${result.cssCharsCount}, ascii=${result.asciiCharsCount}, html=${result.htmlCharsCount}`);
    console.log(`  Excluded ${result.excludedControls.length} nonprinting controls.`);
    for (const c of result.excludedControls) {
      console.log(`    ${c.codePoint} (${c.charRepr}): ${c.justification}`);
    }
    console.log(`  Corpus written to: ${defaultOutput}`);
    console.log(`  Metadata written to: ${defaultMeta}`);
  } catch (err) {
    console.error(`[collect-font-text] Error: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  }
}
