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

## V0.3 — Musées personnels et Museum Hunt (branche `feature/v0.3-museums`)

| Jalon | Contenu | État |
|---|---|---|
| 1 — Bases personnelles | quartier, 8 parcelles, attribution serveur, file d'attente, musée, MA BASE / VILLAGE | ✅ |
| 2 — Exposer | onglet Musée, sélecteur, rendu exact (mutations), animations, fiche d'inspection | ✅ |
| 3 — Sauvegarde | profil v3, migration v2 → v3 sans perte, réparation, reconnexion | ✅ (**DataStore réel non validé**) |
| 4 — Personnalisation | murs, lumière, socles, thème ; socle Étoilé en récompense | ✅ |
| 5 — Visites | onglet Visites, visite, protections | ✅ |
| 6 — Museum Hunt | défi de 75 s, anti-abus, record, musées différents | ✅ |
| 7 — Interfaces | PC, téléphone, tablette (géométrie testée) | ✅ (vrai téléphone non testé) |
| 8 — Performance | budget défini et mesuré dans Studio | ⚠️ indicatif (VM / bureau caché) |

Bilan : [V03_VALIDATION.md](V03_VALIDATION.md).

## V0.3.1 — Validation, optimisation, équilibrage (branche `feature/v0.3.1-validation`)

| Jalon | Contenu | État |
|---|---|---|
| 1 — Audit | 3 volets + luau-lsp (45 → 0 erreur de type) ; 8 correctifs de sécurité | ✅ |
| 2 — Sauvegardes | 10 constats corrigés, 12 tests de concurrence, contrôle du vrai DataStore préparé | ✅ (**vrai DataStore toujours non validé**) |
| 3 — Multijoueur | 17 contrôles à deux vrais clients dans Studio ; protocole humain | ✅ (vrais comptes : playtest) |
| 4 — Performance | rendu incrémental, panneau, Visites, effets réduits ; mesures avant/après | ✅ (vrais appareils non mesurés) |
| 5 — Équilibrage | simulation ; Museum Hunt rééquilibrée ; mutations et Codex analysés | ✅ (à confirmer au playtest) |
| 6 — Expérience | guide de première session, règles du défi, messages de refus | ✅ (sons et ressenti : humain) |
| 7 — Mesures | SessionMetrics + AnalyticsService ; plan de playtest | ✅ (envoi réel non observé) |
| 8 — Finition | suite complète, VM, captures, rapport | voir [V031_VALIDATION.md](V031_VALIDATION.md) |

## V0.2.x — Suite possible

- Équilibrage à partir des sessions de test : fréquence des indices, portées, largeurs de zone.
- Sons dédiés (assets libres de droits validés) à la place des sons intégrés.
- Paramètres d'accessibilité : vitesse du minijeu réduite, indices visuels renforcés.
- ~~Analytics minimales~~ : faites en V0.3.1 (SessionMetrics).
- Relâcher des exemplaires (aujourd'hui la collection est plafonnée à 2000).

## V0.4 — Profondeur de chasse (idées)

- Nouvelles espèces et nouveaux types d'objets (au moins un par zone).
- Comportements actifs : Mimics qui changent d'objet pendant la chasse, qui imitent un objet voisin.
- Variantes de minijeu par espèce (double zone, zone mobile).
- Chasses collectives : un Mimic géant qui demande plusieurs chasseurs.

## Plus tard (non commencé, volontairement)

Base personnelle, mutations avancées, musée, échanges, événements, économie (le modèle de données les prépare). Ces systèmes
ne seront ouverts qu'une fois la boucle Chercher → Capturer validée en test joueur.
Aucun produit Robux n'est prévu avant cette validation.
