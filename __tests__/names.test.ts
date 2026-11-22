import {
  DEFAULT_NAMES,
  deck,
  fitting,
  like,
  matches,
  pass,
  rankLabel,
  reshuffle,
  unlike,
  type BabyName,
  type NameState,
} from '../src/domain/names';

const n = (name: string, extra: Partial<BabyName> = {}): BabyName => ({
  id: `en:${name}`,
  set: 'en',
  name,
  gender: 'f',
  meaning: '',
  tags: [],
  ...extra,
});

const ALL = [
  n('Iris', { rank: 150, tags: ['flower'] }),
  n('Hannah', { rank: 40, tags: ['bible'] }),
  n('Noah', { gender: 'm', rank: 2, tags: ['bible'] }),
  n('Riley', { gender: 'u', rank: 300 }),
  n('Zina', { rank: undefined }),
  { ...n('Xinyi'), id: 'zh:欣怡', set: 'zh' as const, hanzi: '欣怡' },
];

describe('names', () => {
  it('filters by set, gender (unisex fits both) and every tag', () => {
    const girls = { ...DEFAULT_NAMES, gender: 'f' as const };
    expect(ALL.filter(x => matches(x, girls)).map(x => x.name)).toEqual(['Iris', 'Hannah', 'Riley', 'Zina']);
    expect(ALL.filter(x => matches(x, { ...girls, tags: ['bible'] })).map(x => x.name)).toEqual(['Hannah']);
    expect(ALL.filter(x => matches(x, { ...DEFAULT_NAMES, set: 'zh' })).map(x => x.id)).toEqual(['zh:欣怡']);
  });

  it('reads popular and rare from the rank', () => {
    expect(ALL.filter(x => matches(x, { ...DEFAULT_NAMES, tags: ['popular'] })).map(x => x.name)).toEqual([
      'Iris',
      'Hannah',
      'Noah',
    ]);
    expect(ALL.filter(x => matches(x, { ...DEFAULT_NAMES, tags: ['rare'] })).map(x => x.name)).toEqual(['Zina']);
  });

  it('deals a stable order that skips liked and passed names', () => {
    const first = deck(ALL, DEFAULT_NAMES).map(x => x.id);
    expect(deck(ALL, DEFAULT_NAMES).map(x => x.id)).toEqual(first);
    expect(first).toHaveLength(5);
    const s = pass(like(DEFAULT_NAMES, first[0]), first[1]);
    expect(deck(ALL, s).map(x => x.id)).toEqual(first.slice(2));
  });

  it('liking a passed name moves it, and unliking drops it', () => {
    const s = like(pass(DEFAULT_NAMES, 'en:Iris'), 'en:Iris');
    expect(s.liked).toEqual(['en:Iris']);
    expect(s.passed).toEqual([]);
    expect(unlike(s, 'en:Iris').liked).toEqual([]);
  });

  it('reshuffle brings back only the passed names that fit, keeping likes', () => {
    let s: NameState = { ...DEFAULT_NAMES, gender: 'm' };
    s = like(pass(pass(s, 'en:Noah'), 'en:Iris'), 'en:Riley');
    const r = reshuffle(ALL, s);
    expect(r.passed).toEqual(['en:Iris']);
    expect(r.liked).toEqual(['en:Riley']);
    expect(r.seed).toBe(s.seed + 1);
    expect(fitting(ALL, s)).toBe(2);
  });

  it('labels rank', () => {
    expect(rankLabel(ALL[0])).toBe('#150 in the US');
    expect(rankLabel(ALL[4])).toBe('Rare in the US');
    expect(rankLabel(ALL[5])).toBeNull();
  });
});

describe('bundled names', () => {
  const { NAMES } = require('../src/content/names') as typeof import('../src/content/names');

  it('has thousands of English names and hundreds of Chinese, each complete and unique', () => {
    const en = NAMES.filter(x => x.set === 'en');
    const zh = NAMES.filter(x => x.set === 'zh');
    expect(en.length).toBeGreaterThan(4000);
    expect(zh.length).toBeGreaterThan(300);
    expect(new Set(NAMES.map(x => x.id)).size).toBe(NAMES.length);
    for (const x of NAMES) {
      expect(['f', 'm', 'u']).toContain(x.gender);
      expect(x.meaning.length).toBeGreaterThan(0);
    }
    expect(zh.every(x => x.hanzi)).toBe(true);
  });
});
