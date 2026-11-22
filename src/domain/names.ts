/**
 * Baby names: filter the bundled list and deal it one card at a time.
 * Pure — the list comes in, the next card goes out.
 */

export type NameGender = 'f' | 'm' | 'u';
export type NameSet = 'en' | 'zh';

export interface BabyName {
  /** "en:Iris" · "zh:欣怡" */
  id: string;
  set: NameSet;
  /** Latin spelling, or pinyin for Chinese names. */
  name: string;
  hanzi?: string;
  gender: NameGender;
  /** US rank over the last five years of SSA counts; undefined when outside it. */
  rank?: number;
  /** Year of the most births since 1950. */
  peak?: number;
  origin?: string;
  language?: string;
  meaning: string;
  tags: string[];
}

export type GenderPick = 'f' | 'm' | 'all';

export interface NamePrefs {
  set: NameSet;
  gender: GenderPick;
  /** Every tag must match. "popular" and "rare" are read from the rank. */
  tags: string[];
}

export interface NameState extends NamePrefs {
  surname: string;
  liked: string[];
  passed: string[];
  /** Fixes the shuffle, so the deck keeps its order between launches. */
  seed: number;
}

export const DEFAULT_NAMES: NameState = {
  set: 'en',
  gender: 'all',
  tags: [],
  surname: '',
  liked: [],
  passed: [],
  seed: 1,
};

export const POPULAR_RANK = 200;
export const RARE_RANK = 2000;

export const matches = (n: BabyName, prefs: NamePrefs): boolean => {
  if (n.set !== prefs.set) return false;
  if (prefs.gender !== 'all' && n.gender !== prefs.gender && n.gender !== 'u') return false;
  return prefs.tags.every(tag =>
    tag === 'popular'
      ? n.rank !== undefined && n.rank <= POPULAR_RANK
      : tag === 'rare'
      ? n.rank === undefined || n.rank > RARE_RANK
      : n.tags.includes(tag),
  );
};

/** Stable pseudo-random order: the same seed gives the same deck. */
const score = (id: string, seed: number) => {
  let h = 2166136261 ^ seed;
  for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 16777619);
  return h >>> 0;
};

/** Names still to show for these prefs, in deck order. */
export function deck(all: BabyName[], state: NameState): BabyName[] {
  const seen = new Set([...state.liked, ...state.passed]);
  return all
    .filter(n => matches(n, state) && !seen.has(n.id))
    .sort((a, b) => score(a.id, state.seed) - score(b.id, state.seed));
}

/** How many names fit the prefs at all, seen or not. */
export const fitting = (all: BabyName[], prefs: NamePrefs) => all.filter(n => matches(n, prefs)).length;

export const like = (s: NameState, id: string): NameState => ({
  ...s,
  liked: s.liked.includes(id) ? s.liked : [...s.liked, id],
  passed: s.passed.filter(x => x !== id),
});

export const pass = (s: NameState, id: string): NameState => ({
  ...s,
  passed: s.passed.includes(id) ? s.passed : [...s.passed, id],
});

export const unlike = (s: NameState, id: string): NameState => ({ ...s, liked: s.liked.filter(x => x !== id) });

/** Brings back the passed names that fit the prefs, reshuffled. */
export const reshuffle = (all: BabyName[], s: NameState): NameState => {
  const fit = new Set(all.filter(n => matches(n, s)).map(n => n.id));
  return { ...s, passed: s.passed.filter(id => !fit.has(id)), seed: s.seed + 1 };
};

/** "#12 in the US" · "Rare in the US" */
export const rankLabel = (n: BabyName): string | null => {
  if (n.set !== 'en') return null;
  if (n.rank === undefined || n.rank > RARE_RANK) return 'Rare in the US';
  return `#${n.rank.toLocaleString('en-US')} in the US`;
};
