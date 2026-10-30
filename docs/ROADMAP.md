# MIMIC HUNTERS — Roadmap

## V0.1 — Vertical slice de chasse (état actuel)

| Jalon | Contenu | État |
|---|---|---|
| 0 — Fondations | Rojo, Rokit, Git, arborescence, config, tests Lune, lint, formatage | ✅ fait |
| 1 — Carte et Mimics | 3 zones générées par script, 40 objets + tutoriel, 6 espèces, animations | ✅ fait |
| 2 — Gameplay | Scanner, indices, examen, minijeu, validation serveur | ✅ fait |
| 3 — Récompenses et interface | Inventaire de session, découverte, raretés, HUD PC/mobile, Codex | ✅ fait |
| 4 — Validation | 123 tests automatisés, partie solo dans Studio, captures | 🟡 partiel (voir V01_VALIDATION.md) |

### À terminer avant de clore la V0.1

1. Test **2 joueurs** dans Studio (*Clients et serveurs*) : course à la révélation, capture
   en parallèle, départ en pleine capture.
2. Test **mobile** avec l'émulateur d'appareils de Studio : taille et position des boutons,
   toucher d'un objet, bouton IMPULSION.
3. Vérification visuelle des 6 révélations, des 3 styles de fuite et de la carte de découverte.
4. Passage **luau-lsp analyze** (types `--!strict`) et correction des avertissements.
5. Mesure de performance (MicroProfiler) avec plusieurs joueurs.
6. Session de jeu « à froid » avec 3 à 5 testeurs : chronométrer les objectifs 30 s / 90 s / 5 min / 10 min.

## V0.2 — Persistance et réglages

- `DataStoreProfileStore` (même interface que `MemoryProfileStore`) : `UpdateAsync`,
  réessais, verrou de session, migration par `version`.
- Équilibrage à partir des sessions de test : fréquence des indices, portées, largeurs de zone.
- Sons dédiés (assets libres de droits validés) à la place des sons intégrés.
- Paramètres d'accessibilité : vitesse du minijeu réduite, indices visuels renforcés.
- Analytics minimales (temps avant première capture, taux d'échec par espèce).

## V0.3 — Profondeur de chasse

- Nouvelles espèces et nouveaux types d'objets (au moins un par zone).
- Comportements actifs : Mimics qui changent d'objet pendant la chasse, qui imitent un objet voisin.
- Variantes de minijeu par espèce (double zone, zone mobile).
- Chasses collectives : un Mimic géant qui demande plusieurs chasseurs.

## Plus tard (non commencé, volontairement)

Base personnelle, mutations rares, musée, échanges, événements, économie. Ces systèmes
ne seront ouverts qu'une fois la boucle Chercher → Capturer validée en test joueur.
Aucun produit Robux n'est prévu avant cette validation.
