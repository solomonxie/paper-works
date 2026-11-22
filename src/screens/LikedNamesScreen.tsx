import React, { useState } from 'react';
import { ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { NAMES_BY_ID } from '../content/names';
import { unlike, type BabyName } from '../domain/names';
import { Card, Rows, SectionHeader, SwipeRow, space, type, usePalette } from '../ui';
import { genderLabel, saveNames, useNames } from './NamesScreen';

const GROUPS = [
  ['f', 'Girls'],
  ['m', 'Boys'],
  ['u', 'Either'],
] as const;

export function LikedNamesScreen() {
  const p = usePalette();
  const names = useNames();
  const [surname, setSurname] = useState(names.surname);
  const liked = names.liked.map(id => NAMES_BY_ID.get(id)).filter((n): n is BabyName => !!n);
  const full = (n: BabyName) =>
    n.hanzi ? `${n.hanzi} ${n.name}` : [n.name, names.surname].filter(Boolean).join(' ');

  return (
    <ScrollView style={{ backgroundColor: p.bg }} contentContainerStyle={styles.content}>
      <SectionHeader title="Surname" />
      <Card>
        <TextInput
          value={surname}
          onChangeText={setSurname}
          onEndEditing={() => saveNames({ ...names, surname: surname.trim() })}
          placeholder="Shown after every name"
          placeholderTextColor={p.faint}
          returnKeyType="done"
          style={[type.body, styles.input, { color: p.text }]}
          accessibilityLabel="Surname"
        />
      </Card>
      {!liked.length ? (
        <Text style={[type.body, styles.empty, { color: p.dim }]}>Tap ♥ Like on a name to keep it here.</Text>
      ) : null}
      {GROUPS.map(([g, title]) => {
        const group = liked.filter(n => n.gender === g);
        if (!group.length) return null;
        return (
          <View key={g}>
            <SectionHeader title={title} count={group.length} />
            <Card>
              <Rows>
                {group.map(n => (
                  <SwipeRow
                    key={n.id}
                    trailing={[{ label: 'Remove', color: p.late, onPress: () => saveNames(unlike(names, n.id)) }]}>
                    <View style={[styles.row, { backgroundColor: p.card }]} accessibilityLabel={`${full(n)}, ${genderLabel[n.gender]}, ${n.meaning}`}>
                      <Text style={[type.label, styles.name, { color: p.text }]} numberOfLines={1}>
                        {full(n)}
                      </Text>
                      <Text style={[type.caption, styles.meaning, { color: p.dim }]} numberOfLines={1}>
                        {n.meaning}
                      </Text>
                    </View>
                  </SwipeRow>
                ))}
              </Rows>
            </Card>
          </View>
        );
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { paddingBottom: 80 },
  input: { padding: space.lg },
  empty: { padding: space.lg },
  row: { flexDirection: 'row', alignItems: 'center', padding: space.lg, gap: space.md },
  name: { flexShrink: 0, maxWidth: '55%' },
  meaning: { flex: 1, textAlign: 'right' },
});
