import { describe, it, expect } from 'bun:test';

import { parseOnceScheduleValue } from './ipc.js';

describe('parseOnceScheduleValue', () => {
  it('treats naive timestamps as UTC', () => {
    const result = parseOnceScheduleValue('2026-02-20T00:30:00');
    expect(result).toBe('2026-02-20T00:30:00.000Z');
  });

  it('preserves timestamps with Z suffix', () => {
    const result = parseOnceScheduleValue('2026-02-20T00:30:00Z');
    expect(result).toBe('2026-02-20T00:30:00.000Z');
  });

  it('preserves timestamps with lowercase z suffix', () => {
    const result = parseOnceScheduleValue('2026-02-20T00:30:00z');
    expect(result).toBe('2026-02-20T00:30:00.000Z');
  });

  it('preserves timestamps with positive UTC offset', () => {
    const result = parseOnceScheduleValue('2026-02-20T02:30:00+02:00');
    expect(result).toBe('2026-02-20T00:30:00.000Z');
  });

  it('preserves timestamps with negative UTC offset', () => {
    const result = parseOnceScheduleValue('2026-02-19T19:30:00-05:00');
    expect(result).toBe('2026-02-20T00:30:00.000Z');
  });

  it('returns null for invalid timestamps', () => {
    expect(parseOnceScheduleValue('not-a-date')).toBeNull();
    expect(parseOnceScheduleValue('')).toBeNull();
  });
});
