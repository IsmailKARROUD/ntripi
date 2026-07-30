// test/core/text_precheck_test.dart
//
// The precheck's job is to be quiet. It replaced a scraped 21k-entry wordlist
// that flagged `beach`, `queue`, `fish`, `after` and the bare pronoun `i` —
// about a third of ordinary travel prose — which is the failure mode that
// teaches people to ignore the hint entirely.
//
// So the load-bearing half of this file is the benign corpus: real-shaped
// itinerary prose in all six app languages, plus the place names that defeat
// naive substring filters. Every one of them must come back clean. The
// offensive corpus is the cheaper half — the backend classifier is the
// authority, so a miss there costs far less than a false positive here.

import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/core/moderation/text_precheck.dart';

void main() {
  group('stays quiet on ordinary travel prose', () {
    const benign = <String>[
      // English — including the words the old scraped list tripped on.
      'We started the day at the harbour, then walked up to the old town.',
      'Beautiful beach, calm water, great for kids and easy parking.',
      'Book the museum online, the queue at the door was over an hour.',
      'Cheap eats near the port: grilled fish, salad, and a cold drink.',
      'The hostel bar gets loud after midnight, ask for a room upstairs.',
      'I walked to the market and bought fresh bread and cheese.',
      'Take the early ferry, eg the 9am one, and bring plenty of water.',
      'Day 3: hike to the summit, then descend to the refuge for the night.',
      'The room was spic and span and the host left us a bottle of wine.',
      'A chink of light came through the shutters at sunrise.',
      'Rapeseed fields all along the road between the two villages.',
      'We rented bikes and rode the coastal path to the lighthouse.',
      'An analysis of the local wine trade, and a titbit of history.',
      'Assemble at the pass, then classic switchbacks down to the lake.',
      // Place names that defeat substring filters — the documented trap.
      'Visited Bitche in Moselle, Condom in the Gers, and Wank in Bavaria.',
      'Sexbierum in Friesland is a lovely quiet village worth the detour.',
      'Scunthorpe and Penistone are on the same rail line in Yorkshire.',
      'Cockermouth is a market town in Cumbria near Bassenthwaite Lake.',
      // French.
      'La plage est magnifique et le port sert un poisson delicieux.',
      'Ce restaurant est excellent et le service est tres rapide.',
      // Spanish — "negro" (black) and "cono" (cone) must not fire.
      'El museo abre a las diez y la entrada cuesta ocho euros por persona.',
      'El gato negro dormia en la plaza junto al cono de helado.',
      // German.
      'Der Bahnhof liegt zehn Minuten zu Fuss vom Hotel entfernt.',
      'Das Fruehstueck war gut und das Personal sehr freundlich.',
      // Arabic and Chinese.
      'استمتعنا كثيرا بزيارة المدينة القديمة والسوق التقليدي',
      '我们参观了老城区和当地的市场，依靠公交车很方便',
    ];

    for (final text in benign) {
      test('clean: "${text.substring(0, text.length.clamp(0, 48))}…"', () async {
        expect(await looksOffensive(text), isFalse);
      });
    }
  });

  group('flags unambiguous abuse', () {
    const offensive = <String>[
      'this place was absolute shit, the host was a fucking asshole',
      'what a bitch of a hike, the driver was a cunt',
      'the owner is a bastard, do not stay here',
      'le patron est un connard et un salopard',
      'que hijo de puta, nos robo el dinero',
      'der Typ ist ein Arschloch und ein Wichser',
      '这个地方的老板是个傻逼',
    ];

    for (final text in offensive) {
      test('flags: "${text.substring(0, text.length.clamp(0, 40))}…"',
          () async {
        expect(await looksOffensive(text), isTrue);
      });
    }
  });

  group('leet and censored spellings', () {
    test('folds digit and symbol substitutions', () async {
      expect(await looksOffensive('complete sh!t service'), isTrue);
      expect(await looksOffensive('you are a f@ggot'), isTrue);
      expect(await looksOffensive('what a b1tch'), isTrue);
    });

    test('catches censored spellings whose vowel is gone', () async {
      expect(await looksOffensive('f*ck this place'), isTrue);
      expect(await looksOffensive('total sh*t'), isTrue);
    });
  });

  group('stretched spellings', () {
    test('collapses repeated letters onto the list', () async {
      expect(await looksOffensive('fuuck this place'), isTrue);
      expect(await looksOffensive('what a shiiit hostel'), isTrue);
      expect(await looksOffensive('fuckkk the owner'), isTrue);
      expect(await looksOffensive('fuucking rude staff'), isTrue);
    });

    test('a token without a repeat is never squeezed', () async {
      // The guard that keeps squeeze-matching from reopening the place-name
      // problem: `Niger` squeezes to itself, `nigger` squeezes to `niger`.
      expect(await looksOffensive('We crossed into Niger from Agadez.'), isFalse);
      expect(await looksOffensive('Nigeria has excellent street food.'), isFalse);
    });

    test('doubled letters in ordinary words stay clean', () async {
      expect(await looksOffensive('The coffee at the summit hut was terrific.'),
          isFalse);
      expect(await looksOffensive('Bitte melden Sie sich an der Rezeption.'),
          isFalse);
      expect(await looksOffensive('El perro dormia en la terraza soleada.'),
          isFalse);
    });
  });

  group('matches whole tokens, never substrings', () {
    test('an offensive word inside a longer word does not fire', () async {
      // If any of these fired, every place name would be a coin flip.
      expect(await looksOffensive('Scunthorpe'), isFalse);
      expect(await looksOffensive('Cockermouth'), isFalse);
      expect(await looksOffensive('assumption'), isFalse);
      expect(await looksOffensive('classic'), isFalse);
      expect(await looksOffensive('Penistone'), isFalse);
    });

    test('the same word standing alone does fire', () async {
      expect(await looksOffensive('what a cunt'), isTrue);
    });
  });

  group('degrades to clean', () {
    test('empty and whitespace-only text', () async {
      expect(await looksOffensive(''), isFalse);
      expect(await looksOffensive('   \n\t '), isFalse);
    });

    test('punctuation and emoji only', () async {
      expect(await looksOffensive('!!! ??? 🎒🗺️'), isFalse);
    });
  });
}
