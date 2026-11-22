import React, { useLayoutEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { NAMES } from '../content/names';
import {
  DEFAULT_NAMES,
  deck,
  fitting,
  like,
  pass,
  rankLabel,
  reshuffle,
  type BabyName,
  type GenderPick,
  type NameSet,
  type NameState,
} from '../domain/names';
import type { Routes } from '../navigation/routes';
import { haptic } from '../platform';
import { actions, useStore } from '../state/store';
import { Button, Card, radius, space, type, usePalette } from '../ui';

export const TAGS = ['popular', 'rare', 'bible', 'saint', 'nature', 'flower', 'virtue', 'mythology', 'royal', 'literary', 'celestial', 'gem'];
const TAGS_ZH = ['nature', 'virtue', 'celestial', 'flower', 'gem', 'literary', 'classic', 'modern'];
export const genderLabel = { f: 'Girl', m: 'Boy', u: 'Either' } as const;
const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export const useNames = (): NameState => useStore(s => s.settings.names) ?? DEFAULT_NAMES;
export const saveNames = (names: NameState) => actions.updateSettings({ names });

export function NamesScreen({ navigation }: NativeStackScreenProps<Routes, 'Names'>) {
  const p = usePalette();
  const names = useNames();
  const [last, setLast] = useState<NameState | null>(null);
  const [editingSurname, setEditingSurname] = useState(false);
  const cards = useMemo(() => deck(NAMES, names), [names]);
  const card = cards[0];

  useLayoutEffect(() => {
    navigation.setOptions({
      title: 'Baby names',
      headerRight: () => (
        <Button
          title={`♥ ${names.liked.length}`}
          kind="plain"
          onPress={() => navigation.navigate('LikedNames')}
          accessibilityHint="Opens the names you liked"
        />
      ),
    });
  }, [navigation, names.liked.length]);

  const update = (next: NameState) => {
    setLast(null);
    saveNames(next);
  };
  const decide = (liked: boolean) => {
    if (!card) return;
    setLast(names);
    haptic(liked ? 'success' : 'light');
    saveNames(liked ? like(names, card.id) : pass(names, card.id));
  };
  const toggleTag = (tag: string) =>
    update({ ...names, tags: names.tags.includes(tag) ? names.tags.filter(t => t !== tag) : [...names.tags, tag] });

  return (
    <View style={[styles.flex, { backgroundColor: p.bg }]}>
      <ScrollView contentContainerStyle={styles.content}>
        <View style={styles.row}>
          <Segment
            options={[['f', 'Girls'], ['m', 'Boys'], ['all', 'Both']]}
            value={names.gender}
            onChange={g => update({ ...names, gender: g as GenderPick })}
          />
          <Segment
            options={[['en', 'English'], ['zh', '中文']]}
            value={names.set}
            onChange={s => update({ ...names, set: s as NameSet, tags: [] })}
          />
        </View>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chips}>
          {(names.set === 'zh' ? TAGS_ZH : TAGS).map(tag => (
            <Chip key={tag} label={cap(tag)} on={names.tags.includes(tag)} onPress={() => toggleTag(tag)} />
          ))}
        </ScrollView>

        {card ? (
          <NameCard
            name={card}
            surname={names.surname}
            onSurname={() => setEditingSurname(true)}
            editingSurname={editingSurname}
            onSurnameDone={surname => {
              setEditingSurname(false);
              saveNames({ ...names, surname });
            }}
          />
        ) : (
          <Card style={styles.done}>
            <Text style={[type.body, { color: p.text }]}>That's every name for these filters.</Text>
            <Text style={[type.caption, { color: p.dim }]}>
              {fitting(NAMES, names).toLocaleString('en-US')} seen · {names.liked.length} liked
            </Text>
            <Button title="Go through the skipped ones again" kind="plain" onPress={() => update(reshuffle(NAMES, names))} />
          </Card>
        )}
      </ScrollView>

      {card ? (
        <View style={[styles.bar, { backgroundColor: p.bg }]}>
          <View style={styles.buttons}>
            <Button title="Next" style={styles.flex} onPress={() => decide(false)} />
            <Button title="♥ Like" kind="primary" style={styles.flex} onPress={() => decide(true)} />
          </View>
          {last ? (
            <Button
              title="Undo"
              kind="plain"
              onPress={() => {
                saveNames(last);
                setLast(null);
              }}
            />
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

function NameCard({
  name,
  surname,
  onSurname,
  editingSurname,
  onSurnameDone,
}: {
  name: BabyName;
  surname: string;
  onSurname: () => void;
  editingSurname: boolean;
  onSurnameDone: (s: string) => void;
}) {
  const p = usePalette();
  const [draft, setDraft] = useState(surname);
  const rank = rankLabel(name);
  const rows: [string, string | undefined][] =
    name.set === 'en'
      ? [
          ['Origin', name.origin],
          ['Used in', name.language],
          ['Popularity', rank ?? undefined],
          ['Peak year', name.peak ? String(name.peak) : undefined],
        ]
      : [];
  const surnameView = editingSurname ? (
    <TextInput
      autoFocus
      value={draft}
      onChangeText={setDraft}
      onSubmitEditing={() => onSurnameDone(draft.trim())}
      onBlur={() => onSurnameDone(draft.trim())}
      placeholder="Surname"
      placeholderTextColor={p.faint}
      returnKeyType="done"
      style={[styles.surname, { color: p.dim }]}
      accessibilityLabel="Surname"
    />
  ) : (
    <Pressable onPress={onSurname} accessibilityRole="button" accessibilityHint="Edits the surname shown on every card">
      <Text style={[surname ? styles.surname : type.label, { color: surname ? p.faint : p.accent }]}>
        {surname || '+ Surname'}
      </Text>
    </Pressable>
  );

  return (
    <Card style={styles.card}>
      {name.hanzi ? (
        <>
          <Text style={[styles.first, { color: p.text }]}>{name.hanzi}</Text>
          <View style={styles.line}>
            <Text style={[type.headline, { color: p.dim }]}>{name.name} · </Text>
            {surnameView}
          </View>
        </>
      ) : (
        <>
          <Text style={[styles.first, { color: p.text }]} adjustsFontSizeToFit numberOfLines={1}>
            {name.name}
          </Text>
          {surnameView}
        </>
      )}
      <Text style={[type.headline, styles.meaning, { color: p.text }]}>{name.meaning}</Text>
      {rows
        .filter((r): r is [string, string] => !!r[1])
        .map(([label, value]) => (
          <View key={label} style={styles.meta}>
            <Text style={[type.caption, styles.metaLabel, { color: p.dim }]}>{label}</Text>
            <Text style={[type.body, styles.flex, { color: p.text }]}>{value}</Text>
          </View>
        ))}
      <Text style={[type.body, { color: p.text }]}>{genderLabel[name.gender]}</Text>
      {name.tags.length ? (
        <View style={styles.tags}>
          {name.tags.map(t => (
            <Text key={t} style={[type.caption, styles.tag, { color: p.accent, backgroundColor: p.accentSoft }]}>
              {t}
            </Text>
          ))}
        </View>
      ) : null}
    </Card>
  );
}

function Segment({ options, value, onChange }: { options: [string, string][]; value: string; onChange: (v: string) => void }) {
  const p = usePalette();
  return (
    <View style={[styles.segment, { backgroundColor: p.card }]} accessibilityRole="tablist">
      {options.map(([v, label]) => {
        const on = v === value;
        return (
          <Pressable
            key={v}
            onPress={() => onChange(v)}
            accessibilityRole="tab"
            accessibilityState={{ selected: on }}
            style={[styles.segmentItem, on && { backgroundColor: p.accent }]}>
            <Text style={[type.caption, { color: on ? p.onAccent : p.text }]}>{label}</Text>
          </Pressable>
        );
      })}
    </View>
  );
}

function Chip({ label, on, onPress }: { label: string; on: boolean; onPress: () => void }) {
  const p = usePalette();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityState={{ selected: on }}
      style={[styles.chip, { backgroundColor: on ? p.accent : p.card }]}>
      <Text style={[type.caption, { color: on ? p.onAccent : p.text }]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  content: { paddingBottom: 140, gap: space.md, paddingTop: space.sm },
  row: { flexDirection: 'row', gap: space.sm, paddingHorizontal: space.lg },
  chips: { gap: space.sm, paddingHorizontal: space.lg },
  chip: { paddingHorizontal: space.md, paddingVertical: 6, borderRadius: 16 },
  segment: { flexDirection: 'row', borderRadius: radius.md, padding: 2 },
  segmentItem: { paddingHorizontal: space.md, paddingVertical: 6, borderRadius: radius.sm },
  card: { padding: space.xl, gap: space.sm },
  first: { fontSize: 48, fontWeight: '700' },
  surname: { fontSize: 36, fontWeight: '700', padding: 0 },
  line: { flexDirection: 'row', alignItems: 'center' },
  meaning: { marginTop: space.md, marginBottom: space.sm },
  meta: { flexDirection: 'row', alignItems: 'baseline' },
  metaLabel: { width: 96 },
  tags: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm, marginTop: space.sm },
  tag: { paddingHorizontal: space.sm, paddingVertical: 3, borderRadius: radius.sm, overflow: 'hidden' },
  done: { padding: space.lg, gap: space.sm },
  bar: { position: 'absolute', left: 0, right: 0, bottom: 0, padding: space.lg, paddingBottom: space.xxl, gap: space.xs },
  buttons: { flexDirection: 'row', gap: space.md },
});
