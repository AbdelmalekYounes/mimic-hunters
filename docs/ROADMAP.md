# MIMIC HUNTERS — Roadmap

## V0.1 — Vertical slice de chasse

| Jalon | Contenu | État |
|---|---|---|
| 0 — Fondations | Rojo, Rokit, Git, arborescence, config, tests Lune, lint, formatage | ✅ fait |
| 1 — Carte et Mimics | 3 zones générées par script, 40 objets + tutoriel, 6 espèces, animations | ✅ fait |
| 2 — Gameplay | Scanner, indices, examen, minijeu, validation serveur | ✅ fait |
| 3 — Récompenses et interface | Inventaire de session, découverte, raretés, HUD PC/mobile, Codex | ✅ fait |
| 4 — Validation | 158 tests Lune + 44 tests Studio automatisés (`test.cmd`), partie solo, captures | 🟡 partiel : vérifications visuelles restantes (voir TESTING.md) |

### À terminer avant de clore la V0.1

1. ~~Test **2 joueurs** dans Studio~~ : automatisé (`test.cmd`, session multiplayer). Reste la
   course à la révélation entre deux vrais clients (couverte côté serveur avec de faux joueurs).
2. ~~Test **mobile**~~ : disposition tactile et géométrie à l'écran automatisées (simulation d'appareil,
   disposition compacte pour téléphone). Restent le confort tactile et un vrai téléphone.
3. Vérification visuelle des 6 révélations, des 3 styles de fuite et de la carte de découverte.
4. Passage **luau-lsp analyze** (types `--!strict`) et correction des avertissements.
5. Mesure de performance (MicroProfiler) avec plusieurs joueurs.
6. Session de jeu « à froid » avec 3 à 5 testeurs : chronométrer les objectifs 30 s / 90 s / 5 min / 10 min.

## V0.2 — Collection persistante, mutations, progression (branche `feature/v0.2-collection`)

| Jalon | Contenu | État |
|---|---|---|
| 1 — Sauvegardes | profil v2, `UpdateAsync`, verrou de session, réessais, budget, migration, DataStore Studio distinct | ✅ fait (**vrai DataStore non testé** : place non publiée) |
| 2 — Exemplaires | identifiant serveur, espèce, rareté, mutation, graine d'apparence, date, favori | ✅ fait |
| 3 — Mutations | Chromatic 4 %, Spectral 1,5 %, tirage serveur, révélation dédiée | ✅ fait |
| 4 — Codex et inventaire | panneau Collection, filtres, tris, pages, fiche 3D, favoris, complétion | ✅ fait |
| 5 — Objectifs | 6 objectifs, titres et couleurs de scanner garantis | ✅ fait |
| 6 — Ressenti | sons du scanner, capture, effets par rareté, pastille de nouveauté, réglages | ✅ fait (rendu vérifié sur captures, sons non écoutés) |

Bilan détaillé : [V02_VALIDATION.md](V02_VALIDATION.md).

### Avant une publication (à décider avec toi)

1. Essai du vrai DataStore : publication **privée** de la place + accès API activé dans Studio
   (nécessite ton autorisation), puis tests de rechargement entre deux serveurs réels.
2. Session de jeu avec de vrais joueurs : envie de collectionner, lisibilité des mutations.
3. Vrai téléphone (la simulation de Studio n'en tient pas lieu) et mesures de performance.

## V0.2.x — Suite possible

- Équilibrage à partir des sessions de test : fréquence des indices, portées, largeurs de zone.
- Sons dédiés (assets libres de droits validés) à la place des sons intégrés.
- Paramètres d'accessibilité : vitesse du minijeu réduite, indices visuels renforcés.
- Analytics minimales (temps avant première capture, taux d'échec par espèce).
- Relâcher des exemplaires (aujourd'hui la collection est plafonnée à 2000).

## V0.3 — Profondeur de chasse

- Nouvelles espèces et nouveaux types d'objets (au moins un par zone).
- Comportements actifs : Mimics qui changent d'objet pendant la chasse, qui imitent un objet voisin.
- Variantes de minijeu par espèce (double zone, zone mobile).
- Chasses collectives : un Mimic géant qui demande plusieurs chasseurs.

## Plus tard (non commencé, volontairement)

Base personnelle, mutations avancées, musée, échanges, événements, économie (le modèle de données les prépare). Ces systèmes
ne seront ouverts qu'une fois la boucle Chercher → Capturer validée en test joueur.
Aucun produit Robux n'est prévu avant cette validation.
