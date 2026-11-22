# Baby names data

Builds `src/content/names/en.json` and `zh.json`. Run once; the output is committed.

1. `names.zip` from https://www.ssa.gov/oact/babynames/names.zip (US Social Security counts, public domain; the site blocks scripted downloads, so save it from a browser), unzipped to `<work>/ssa`.
2. Hitchcock's Bible Names (1869, public domain): https://www.ccel.org/ccel/h/hitchcock/bible_names/cache/bible_names.txt
3. `python3 base.py <work>/ssa <work>/base.json` — names from the last five years plus any top-400 name since 1950, with gender, rank and peak year.
4. `python3 bible.py bible_names.txt <work>/bible.json` — Bible meanings, used as hints.
5. Origin, language, meaning and tags are written per name into `<work>/meta/batch-*.jsonl`; Chinese names into `<work>/meta/chinese.jsonl` and `zh-*.jsonl` (poetry with exact source lines, solar terms, idioms, popular, historical, famous), merged by characters (a short guide, not a dictionary).
6. `python3 merge.py <work> ../../src/content/names`
