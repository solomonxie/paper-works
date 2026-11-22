# Baby names

Each Baby names plan has its own likes, history and filters; the screen is opened per plan
(`Route.names(planId:)`). Title "Baby names" with the linked event as subtitle; `⋯` menu:
`Change event…`, `Remove plan`. Pushed from a `Baby names` plan row on the home Plans section
([`plans.md`](plans.md)), or from a Baby due or Child born chapter's `Opens`
([`timeline.md`](timeline.md)); added from the Library or those events. One card at a time from the bundled list; every
name is kept on the device.

```
 ‹         Baby names           ☰1,204 ⟲ ›  ← → list mode (list.bullet) + names left · History (clock.arrow.circlepath)
 (♀ Girls)(♂ Boys)(✦ Both)                ← tinted capsules: rose · teal · amber,
                                               selected = solid fill, white text
 ( English | 中文 )              ( ≡ Filters · 3 )   ← compact switch · opens sheet; count
                                                      of active tags + origins + letters
  ╭────────────────────────────────────╮
 ╭┴────────────────────────────────────┴╮   ← next cards peek out, tilted
 │ ░░ soft gradient by gender ░░░░░░░░░ │   ← girls rose/coral · boys teal/blue
 │                                      │     either amber/violet; fills the screen
 │  Iris                                │  ← first name, huge, rounded bold
 │  Xie                                 │  ← surname, lighter; "+ Surname" when none
 │  "Rainbow"                           │  ← meaning, quote line
 │  Related  (2 liked)                  │  ← one card per family; badge when some liked
 │  (Irisa)(Irisha)(Iryss) +4 more        │  ← chips wrap, 10 shown, "+N more" expands
 │                                      │
 │ (♀ Girl)(🌐 Greek)(💬 English, Dutch) │  ← pills wrap
 │ (▂▄ #150 in the US ▮▮▯)(📅 Peak 1910) │  ← tiny bar = how common; "Rare in the US"
 │ (🌸 Flower)(⚡ Mythology)             │  ← colored tag chips with icons
 ╰──────────────────────────────────────╯
     swipe → LIKE stamp · swipe ← SKIP stamp
        ( ✕ )    ( ↶ )    ( ♥ )          ← skip · undo (dim until a decision) · like
```

List mode (toolbar `list.bullet` ↔ `rectangle.stack`, remembered; card is the default).
Same filtered deck, one row per family, sorted A–Z (中文: by pinyin); filters stay on top. The toolbar toggle shows how many names are left, live:

```
 ‹         Baby names           ▤1,204 ⟲ ›  ← ▤ back to cards (rectangle.stack)
 (♀ Girls)(♂ Boys)(✦ Both)
 ( English | 中文 )              ( ≡ Filters )
 ( 🔍 Name or meaning               )      ← search
 1,204 names · Girls · Bible, Nature       ← live count · gender · filters
 A                                       A
   "Soul" · Latin · #900 in the US       ⋮
 R
 ● Rose Xie  · Rosa, Rosie…            ♡   ← gender dot · name, surname after (中文: surname first)
   "Rose flower" · Latin · #120 in the US     related family names in gray
```

Tap a row: its card pops up over the list (dimmed backdrop; tap the backdrop to dismiss).
The popup has the card-mode controls: ✕ / ♥ buttons and swipe left / right. Deciding
flies the card off, closes the popup and the row leaves the list. The rows themselves
have no swipe actions; their ♡ likes in one tap.

Filters sheet (medium/large detent; Clear, Done):

```
 Tags (any of them, Popular and Rare included); tags, origin and letters narrow each other
 (Popular)(Rare)(Bible)(Saint)(Nature)…       ← wrap
 Origin (any of)                              ← English only
 (English)(Hebrew)(Greek)(Latin)(Irish)…      ← 12 most common origins in the list
 More origins…                                ← shows up to 60
 First letter (any of)                        ← both languages; 中文 uses pinyin
 (A 12)(B 30)(C 25)…(Z 9)                     ← A–Z chips with small gray counts; letters with no names left out
```

Related chips: tap one to like that spelling (tinted), tap again to
unlike; light haptic. A liked chip is tinted, with no heart icon. The card stays put while chips are tapped; only ✕, ♥, a
swipe or a filter change moves on. ♥ / swipe right likes the main name and keeps
liked chips; ✕ / swipe left skips the main name only (liked chips stay liked) and
hides the whole family. Undo restores the card and the earlier state. Chip likes
show in History as their own rows.

Chips are ordered by how many names they match for the current language and gender (count shown small, gray); Popular/Rare stay first.

中文 chips are built from the tags present in Chinese names, labelled in Chinese, 热门 first, the rest count-sorted:
诗词 poetry, 节气 solarterm, 成语 idiom, 圣经 bible, 热门 popular, 历史 historical, 名人 famous, 自然, 品德, 星辰, 花卉, 珠玉, 文雅, 经典, 现代.
For Chinese names 热门 is an ordinary tag (no rank); there is no Rare.

Origin is the name's origin or language, combined with tags. First letter is the
name's initial (accents folded; 中文: first letter of the pinyin), any of the picked
letters, narrowing with tags and origin. Switching English/中文 clears tags and origins,
and keeps only the letters that still have names. The edge swipe back is off on this screen (it clashes
with card swipes); the back button works.

Chinese names (`中文`): characters huge, pinyin under them, with the 中文 surname in front;
origin, language and popularity pills are left out. Tag pills use Chinese labels with icons
(poetry text.book.closed, solarterm sun.haze, idiom character.book.closed, popular flame, historical scroll, famous star).

Source (optional, `names-zh.json` 6th column): shown under the meaning as a quote block, serif, smaller, thin
vertical rule on the left. `作者《篇名》：句子。` renders as 「句子」 plus "— 作者《篇名》" on its own line;
other sources ("成语：宁静致远", "李清照，号易安居士") show as is. List rows and the History popup show the short
source ("曹植《洛神赋》" / "成语：宁静致远") after the meaning.

List rows: a real `List`, no swipe actions; the heart on the row likes. The row opens via a plain
button, not a tap gesture. No A–Z side index: the normal scroll bar is enough.

```
│  谢欣怡                              │  ← 中文 surname first, as written
│  Xīnyí                               │  ← given name's pinyin only (no tone guessing)
│  + 姓 / 谢                           │  ← edits the 中文 surname
│  "Joyful and harmonious"             │
```

Out of names for the filters:

```
╭────────────────────────────────────────╮
│ That's every name for these filters.   │
│ 1,204 seen · 12 liked                  │
│ ( Go through the skipped ones again )  │  ← reshuffles the skipped, keeps likes
╰────────────────────────────────────────╯
```

## History

```
 ‹         History
 SURNAME
 English                          Xie   ›   ← edit in place
 中文                              谢   ›   ← used on 中文 rows and cards
 [ All 15 | Liked 12 | Skipped 3 ]          ← segmented filter with counts
 ──────────────────────────────────────────
 ♥  Iris Xie            Rainbow     Today
 ♡  Noah Xie            Rest        Yesterday
 ♥  Hannah Xie          Grace       3 days ago
 ♥  谢欣怡              Joyful…     Earlier   ← decided before dates were kept
```

Newest decision first. Tap the heart (filled = liked, outline gray = skipped):
flip like ↔ skip with a light haptic (counts as a new decision, moves to the
top). Tap a row: its full card (same NameCard as the deck, with Related chips)
pops up over a dimmed backdrop with a spring scale-in; tap the card or backdrop
to dismiss. Swipe left: Remove, which puts the name back in the deck (Delete for
custom names). VoiceOver: the row opens the card; custom actions Like/Skip and Remove.

**+ (toolbar)** opens a small form: English/中文 switch, name (中文: characters +
optional pinyin), Girl/Boy/Either, optional meaning and origin. Save adds it as
liked and pops its card, tagged "Your name". If the name already exists in the
bundled list (case-insensitive; 中文 by characters) the form shows "Already in
the list — will use its meaning and origin" with the meaning, and Save just likes
the bundled name. Custom names (`custom:` ids, stored in names state) are never
in the deck; no Undo (none exists for names).

## Notes

- Meanings and origins are a short guide written for this list, not a
  dictionary. Ranks come from US Social Security counts for the last five
  years (public domain); Bible tags and hints from Hitchcock's Bible Names
  (1869, public domain). About shows the sources.
- Liked and skipped names, with the day each was decided, live in settings, so backups carry them.

List mode: tap a row and its card pops up over the list (dimmed backdrop); tap the
card or the backdrop to dismiss. Related chips on it still like. The list keeps its
place and the mode doesn't change.
