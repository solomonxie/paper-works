import type { BabyName, NameGender } from '../../domain/names';
import en from './en.json';
import zh from './zh.json';

/** Built by scripts/names (see its README): [name, gender, rank, peak, origin, language, meaning, tags]. */
type EnRow = [string, NameGender, number | null, number, string, string, string, string];
/** [pinyin, hanzi, gender, meaning, tags] */
type ZhRow = [string, string, NameGender, string, string];

const words = (s: string) => (s ? s.split(' ') : []);

export const NAMES: BabyName[] = [
  ...(en as EnRow[]).map(([name, gender, rank, peak, origin, language, meaning, tags]) => ({
    id: `en:${name}`,
    set: 'en' as const,
    name,
    gender,
    rank: rank ?? undefined,
    peak,
    origin,
    language,
    meaning,
    tags: words(tags),
  })),
  ...(zh as ZhRow[]).map(([name, hanzi, gender, meaning, tags]) => ({
    id: `zh:${hanzi}`,
    set: 'zh' as const,
    name,
    hanzi,
    gender,
    origin: 'Chinese',
    language: 'Chinese',
    meaning,
    tags: words(tags),
  })),
];

export const NAMES_BY_ID = new Map(NAMES.map(n => [n.id, n]));

/** Latest year in the SSA counts the ranks come from. */
export const NAMES_YEAR = 2025;
