// W1-C: engine-agnostic golden-trace comparator for ReturnFare.
// Implements trace format v1 (docs/web/W1實作契約.md §三 軌跡格式 v1).
// Pure TypeScript: no imports, no dependencies.

export const MISSING: unique symbol = Symbol('trace.missing');

export type TracePhase = 'morning' | 'afternoon' | 'evening' | 'night';

export interface TraceManifestEntry {
  path: string;
  sha256: string;
}

export interface TraceCheckpoint {
  seq: number;
  label: string;
  day: number;
  phase: TracePhase;
  state: { flow: Record<string, unknown>; run: Record<string, unknown>; meta: Record<string, unknown> };
}

export interface Trace {
  schema_version: 1;
  policy: string;
  source_revision: string;
  data_manifest: TraceManifestEntry[];
  checkpoints: TraceCheckpoint[];
}

export interface CompareOptions {
  /** Inclusive prefix: only checkpoints with `seq <= throughSeq` are compared. */
  throughSeq?: number;
  /** Exact JSON Pointer paths relative to `state` that must not be compared. */
  ignorePaths?: string[];
}

export interface TraceDifference {
  seq: number | null;
  label: string | null;
  day: number | null;
  phase: TracePhase | null;
  /** JSON Pointer relative to the compared `state`, or a synthetic top-level path. */
  path: string;
  expected: unknown;
  actual: unknown;
}

export interface TraceCompareResult {
  equal: boolean;
  comparedCheckpoints: number;
  comparedFields: number;
  difference: TraceDifference | null;
}

export class TraceShapeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TraceShapeError';
  }
}

export class TraceConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TraceConfigError';
  }
}

const VALID_PHASES = new Set<string>(['morning', 'afternoon', 'evening', 'night']);
const FORBIDDEN_IGNORE_PATHS = ['', '/flow', '/run', '/meta'];

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isManifestEntry(value: unknown): value is TraceManifestEntry {
  const entry = value as Record<string, unknown>;
  return isPlainObject(entry) && typeof entry.path === 'string' && typeof entry.sha256 === 'string';
}

function isCheckpoint(value: unknown): value is TraceCheckpoint {
  const object = value as Record<string, unknown>;
  if (!isPlainObject(object)) return false;
  if (typeof object.seq !== 'number' || !Number.isFinite(object.seq)) return false;
  if (typeof object.label !== 'string') return false;
  if (typeof object.day !== 'number' || !Number.isFinite(object.day)) return false;
  if (typeof object.phase !== 'string' || !VALID_PHASES.has(object.phase)) return false;
  const state = object.state as Record<string, unknown> | undefined;
  return isPlainObject(state) && isPlainObject(state.flow) && isPlainObject(state.run) && isPlainObject(state.meta);
}

export function isTrace(value: unknown): value is Trace {
  const object = value as Record<string, unknown>;
  return (
    isPlainObject(object) &&
    object.schema_version === 1 &&
    typeof object.policy === 'string' &&
    typeof object.source_revision === 'string' &&
    Array.isArray(object.data_manifest) &&
    object.data_manifest.every(isManifestEntry) &&
    Array.isArray(object.checkpoints) &&
    object.checkpoints.every(isCheckpoint)
  );
}

function selectPrefix(checkpoints: TraceCheckpoint[], throughSeq: number | undefined): TraceCheckpoint[] {
  if (throughSeq === undefined) return checkpoints;
  const end = checkpoints.findIndex((checkpoint) => checkpoint.seq === throughSeq);
  if (end === -1) return [];
  return checkpoints.slice(0, end + 1);
}

function validateIgnorePaths(ignorePaths: string[], checkpoints: TraceCheckpoint[]): void {
  for (const path of ignorePaths) {
    if (typeof path !== 'string') throw new TraceConfigError('ignorePaths entries must be strings');
    if (FORBIDDEN_IGNORE_PATHS.includes(path)) {
      throw new TraceConfigError(`ignore path ${path} is a root state area and cannot be ignored`);
    }
    let existsAnywhere = false;
    for (const checkpoint of checkpoints) {
      if (resolvePointer(checkpoint.state, path).exists) {
        existsAnywhere = true;
        break;
      }
    }
    if (!existsAnywhere) {
      throw new TraceConfigError(`ignore path ${path} does not exist in compared checkpoints`);
    }
  }
}

// RFC 6902 JSON Pointer resolution against a JSON value.
function resolvePointer(root: unknown, pointer: string): { exists: boolean; value: unknown } {
  if (pointer === '') return { exists: true, value: root };
  if (!pointer.startsWith('/')) return { exists: false, value: undefined };
  let current: unknown = root;
  for (const raw of pointer.slice(1).split('/')) {
    const key = raw.replace(/~1/g, '/').replace(/~0/g, '~');
    if (Array.isArray(current)) {
      const index = Number(key);
      if (!Number.isInteger(index) || index < 0 || index >= current.length) {
        return { exists: false, value: undefined };
      }
      current = current[index];
    } else if (isPlainObject(current)) {
      if (!(key in current)) return { exists: false, value: undefined };
      current = current[key];
    } else {
      return { exists: false, value: undefined };
    }
  }
  return { exists: true, value: current };
}

interface LeafCompare {
  equal: boolean;
  difference: TraceDifference | null;
  fields: number;
}

function differenceAt(path: string, expected: unknown, actual: unknown): TraceDifference {
  return { seq: null, label: null, day: null, phase: null, path, expected, actual };
}

function compareObjects(
  expected: Record<string, unknown>,
  actual: Record<string, unknown>,
  path: string,
  ignored: Set<string>,
): LeafCompare {
  if (Object.keys(expected).length === 0 && Object.keys(actual).length === 0) {
    return { equal: true, difference: null, fields: 1 };
  }
  let fields = 0;
  const keys = new Set<string>();
  for (const key of Object.keys(expected)) keys.add(key);
  for (const key of Object.keys(actual)) keys.add(key);
  for (const key of keys) {
    const childPath = path === '' ? `/${key}` : `${path}/${key}`;
    // An ignored path is skipped even when one side lacks it (unported fields may be absent).
    if (ignored.has(childPath)) continue;
    const expectedHas = Object.prototype.hasOwnProperty.call(expected, key);
    const actualHas = Object.prototype.hasOwnProperty.call(actual, key);
    if (!expectedHas || !actualHas) {
      return {
        equal: false,
        difference: differenceAt(childPath, expectedHas ? expected[key] : MISSING, actualHas ? actual[key] : MISSING),
        fields: fields + 1,
      };
    }
    const child = compareValues(expected[key], actual[key], childPath, ignored);
    fields += child.fields;
    if (!child.equal) return { equal: false, difference: child.difference, fields };
  }
  return { equal: true, difference: null, fields };
}

function compareArrays(
  expected: unknown[],
  actual: unknown[],
  path: string,
  ignored: Set<string>,
): LeafCompare {
  if (expected.length === 0 && actual.length === 0) {
    return { equal: true, difference: null, fields: 1 };
  }
  let fields = 0;
  const length = Math.max(expected.length, actual.length);
  for (let i = 0; i < length; i += 1) {
    const childPath = `${path}/${i}`;
    if (i >= expected.length) {
      return { equal: false, difference: differenceAt(childPath, MISSING, actual[i]), fields: fields + 1 };
    }
    if (i >= actual.length) {
      return { equal: false, difference: differenceAt(childPath, expected[i], MISSING), fields: fields + 1 };
    }
    const child = compareValues(expected[i], actual[i], childPath, ignored);
    fields += child.fields;
    if (!child.equal) return { equal: false, difference: child.difference, fields };
  }
  return { equal: true, difference: null, fields };
}

function compareValues(
  expected: unknown,
  actual: unknown,
  path: string,
  ignored: Set<string>,
): LeafCompare {
  if (ignored.has(path)) return { equal: true, difference: null, fields: 0 };

  if (expected === null && actual === null) return { equal: true, difference: null, fields: 1 };
  if (expected === null || actual === null) {
    return { equal: false, difference: differenceAt(path, expected, actual), fields: 1 };
  }

  const expectedType = typeof expected;
  const actualType = typeof actual;
  if (expectedType !== actualType) {
    return { equal: false, difference: differenceAt(path, expected, actual), fields: 1 };
  }
  if (expectedType !== 'object') {
    if (expected === actual) return { equal: true, difference: null, fields: 1 };
    return { equal: false, difference: differenceAt(path, expected, actual), fields: 1 };
  }

  if (Array.isArray(expected) && Array.isArray(actual)) return compareArrays(expected, actual, path, ignored);
  if (!Array.isArray(expected) && !Array.isArray(actual))
    return compareObjects(expected as Record<string, unknown>, actual as Record<string, unknown>, path, ignored);
  return { equal: false, difference: differenceAt(path, expected, actual), fields: 1 };
}

function manifestsEqual(expected: TraceManifestEntry[], actual: TraceManifestEntry[]): boolean {
  if (expected.length !== actual.length) return false;
  for (let i = 0; i < expected.length; i += 1) {
    if (expected[i].path !== actual[i].path || expected[i].sha256 !== actual[i].sha256) return false;
  }
  return true;
}

function checkpointDifference(
  checkpoint: TraceCheckpoint | null,
  path: string,
  expected: unknown,
  actual: unknown,
): TraceDifference {
  return {
    seq: checkpoint === null ? null : checkpoint.seq,
    label: checkpoint === null ? null : checkpoint.label,
    day: checkpoint === null ? null : checkpoint.day,
    phase: checkpoint === null ? null : checkpoint.phase,
    path,
    expected,
    actual,
  };
}

function finish(
  equal: boolean,
  comparedCheckpoints: number,
  comparedFields: number,
  difference: TraceDifference | null,
): TraceCompareResult {
  return { equal, comparedCheckpoints, comparedFields, difference };
}

export function compareTraces(expected: Trace, actual: Trace, options: CompareOptions = {}): TraceCompareResult {
  const { throughSeq, ignorePaths = [] } = options;

  if (throughSeq !== undefined && (!Number.isInteger(throughSeq) || throughSeq < 0)) {
    throw new TraceConfigError('throughSeq must be a non-negative integer');
  }

  if (!isTrace(expected) || !isTrace(actual)) {
    throw new TraceShapeError(
      'trace shape is invalid: schema_version, policy, source_revision, data_manifest and checkpoints are required',
    );
  }

  const expectedSelected = selectPrefix(expected.checkpoints, throughSeq);
  const actualSelected = selectPrefix(actual.checkpoints, throughSeq);

  // A scope beyond the baseline is a configuration error; an actual trace missing part of
  // the prefix is a checkpoint mismatch, never a shorter-length success.
  if (throughSeq !== undefined && expectedSelected.length === 0) {
    throw new TraceConfigError(`throughSeq ${throughSeq} selects zero checkpoints`);
  }
  if (throughSeq !== undefined && actualSelected.length === 0) {
    const missingAt = expectedSelected[Math.min(actual.checkpoints.length, expectedSelected.length - 1)];
    return finish(false, 0, 0, checkpointDifference(missingAt, '/checkpoints', missingAt.seq, MISSING));
  }

  validateIgnorePaths(ignorePaths, [...expectedSelected, ...actualSelected]);
  const ignored = new Set(ignorePaths);

  // Contract A: baseline identity first — schema_version, policy, then data_manifest.
  // A data_manifest mismatch is "baseline not applicable", never a gameplay diff.
  if (expected.schema_version !== actual.schema_version) {
    return finish(
      false,
      0,
      0,
      checkpointDifference(null, '/schema_version', expected.schema_version, actual.schema_version),
    );
  }
  if (expected.policy !== actual.policy) {
    return finish(false, 0, 0, checkpointDifference(null, '/policy', expected.policy, actual.policy));
  }
  if (!manifestsEqual(expected.data_manifest, actual.data_manifest)) {
    return finish(false, 0, 0, checkpointDifference(null, '/data_manifest', expected.data_manifest, actual.data_manifest));
  }

  let comparedCheckpoints = 0;
  let comparedFields = 0;
  const length = Math.max(expectedSelected.length, actualSelected.length);
  for (let i = 0; i < length; i += 1) {
    const left = expectedSelected[i];
    const right = actualSelected[i];
    if (left === undefined || right === undefined) {
      const present = left ?? right;
      return finish(
        false,
        comparedCheckpoints,
        comparedFields,
        checkpointDifference(
          present,
          '/checkpoints',
          left === undefined ? MISSING : left.seq,
          right === undefined ? MISSING : right.seq,
        ),
      );
    }
    if (left.seq !== right.seq) {
      return finish(false, comparedCheckpoints, comparedFields, checkpointDifference(left, '/seq', left.seq, right.seq));
    }
    if (left.label !== right.label) {
      return finish(false, comparedCheckpoints, comparedFields, checkpointDifference(left, '/label', left.label, right.label));
    }
    if (left.day !== right.day) {
      return finish(false, comparedCheckpoints, comparedFields, checkpointDifference(left, '/day', left.day, right.day));
    }
    if (left.phase !== right.phase) {
      return finish(false, comparedCheckpoints, comparedFields, checkpointDifference(left, '/phase', left.phase, right.phase));
    }
    const state = compareValues(left.state, right.state, '', ignored);
    comparedCheckpoints += 1;
    comparedFields += state.fields;
    if (!state.equal) {
      return finish(
        false,
        comparedCheckpoints,
        comparedFields,
        checkpointDifference(left, state.difference!.path, state.difference!.expected, state.difference!.actual),
      );
    }
  }

  return finish(comparedCheckpoints > 0 && comparedFields > 0, comparedCheckpoints, comparedFields, null);
}
