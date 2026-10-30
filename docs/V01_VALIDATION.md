# MIMIC HUNTERS — Rapport de validation V0.1

Date : 30/10/2026 · Environnement : Windows 11, Roblox Studio (version installée localement),
Rojo 7.7.1, Lune 0.11.1, Selene 0.27.1, StyLua 0.20.0.

Ce rapport distingue trois niveaux, sans les mélanger :

- **Implémenté** : le code existe.
- **Testé automatiquement** : couvert par les tests Lune (exécutés, résultats ci-dessous).
- **Vérifié dans Studio** : observé de mes yeux pendant une partie dans Studio (Play solo).

## 0. Mise à jour du 30/10/2026 (soir) : tests Studio automatisés

`test.cmd` exécute maintenant 4 sessions Studio sur un bureau Windows caché : 42 tests réussis,
2 ignorés, 0 échec, ≈ 75 s (voir [TESTING.md](TESTING.md)). Points qui étaient « non testés »
ci-dessous et qui sont désormais **testés automatiquement** :

| Point | Couverture automatique | Reste à vérifier à l'œil |
|---|---|---|
| 2 joueurs simultanés | 2 clients, déconnexion `LeaveTest`, reconnexion `AddPlayers`, autre joueur non affecté | interaction visuelle entre joueurs |
| Interface tactile | simulation `iphone_13` : `TouchEnabled`, disposition tactile, textes | géométrie, confort, téléphone réel |
| Carte « Nouvelle espèce » | affichée après une capture réelle (état de l'interface) | rendu visuel |
| Message final du tutoriel | étape `Done` confirmée côté serveur après la capture | rendu visuel du bandeau |
| Zone Commerciale | générée et non vide, objets posés au sol | aspect visuel |
| Objets posés au sol (régression du bug de pivot) | les 41 objets, y compris les 6 modèles d'espèce | — |

Toujours **non couverts** : rendu, animations, sons audibles, performance, géométrie à la taille d'écran réelle.

## 1. Résultats des outils (exécutés)

| Commande | Résultat |
|---|---|
| `lune run tests/run` | **123 réussis, 0 échoué** |
| `lune run tests/check` | 39 fichiers compilés, 0 erreur |
| `selene src` | 0 erreur, 0 avertissement |
| `selene .` (dans `tests/`, std luau) | 0 erreur, 0 avertissement |
| `stylua --check src tests` | conforme |
| `rojo build default.project.json -o build/MimicHunters.rbxl` | place construite |

Contrôle de la pertinence des tests : deux mutations volontaires ont été injectées puis retirées.
Suppression du bornage anti-triche du temps client : 3 tests échouent. Suppression de la
vérification du propriétaire : 2 tests échouent.

**Non exécuté** : vérification des types `--!strict` (luau-lsp n'est pas installé). Les
annotations de type n'ont donc pas été validées par un analyseur.

## 2. Tableau des fonctionnalités

| Fonctionnalité | Implémenté | Tests auto | Vérifié dans Studio |
|---|---|---|---|
| Place Rojo construite et lancée | ✅ | — | ✅ démarrage sans erreur de nos scripts |
| Génération de la carte (3 zones) | ✅ | ✅ données (`map_layout.spec`) | ✅ Village vu en détail ; Parc vu de loin ; **Zone Commerciale non visitée** |
| 40 objets + chaise de tutoriel | ✅ | ✅ nombre, ids, zones, espacements | ✅ « 41 objets » affiché ; objets debout (après correctif) |
| Objets normaux = Mimics au repos | ✅ (même constructeur) | — | ✅ aucune différence visible au repos |
| 6 espèces (id, nom, rareté, comportement…) | ✅ | ✅ `catalog.spec` | 🟡 **Chairy seulement** vu révélé (en partie solo) |
| Animations de révélation (6 styles) | ✅ | — | 🟡 style « Hop » (Chairy) vu ; 5 autres **non vus** |
| Animation de capture | ✅ | — | 🟡 fin observée (objet restauré) ; vol vers le joueur non capturé à l'image |
| Animation de fuite (3 styles) | ✅ | — | ❌ non observée |
| Indices (yeux, tortillement, etc.) | ✅ 8 types | ✅ diffusion limitée aux joueurs proches | ✅ yeux sur la chaise et sursaut au scan ; autres types non observés |
| Scanner (intensité, sursaut, recharge) | ✅ | ✅ | ✅ « TRÈS FORT » puis « MOYEN », barres, recharge visible |
| Examiner (ordinaire / Mimic / occupé) | ✅ | ✅ | ✅ cas Mimic ; cas « ordinaire » non observé à l'écran |
| Minijeu (jauge, zone, curseur, 2 réussites) | ✅ | ✅ `capture.spec` (20 tests) | ✅ affichage, impulsions Espace, journal serveur cohérent avec l'écran |
| Échec / délai de capture | ✅ | ✅ | ✅ délai de 45 s du tutoriel → Mimic recaché, retour à l'étape « Examiner » |
| Validation serveur (portée, état, délais, propriétaire) | ✅ | ✅ `hunt_world.spec › protections` | ✅ indirectement (captures acceptées et journalisées) |
| Anti-triche sur le temps client | ✅ | ✅ (avec mutation) | — non testable à la main |
| Récompense unique / idempotente | ✅ | ✅ rejeu ×20 sans doublon | — |
| Inventaire de session + compteur | ✅ | ✅ `rewards.spec` | ✅ « Captures : 1 · Espèces 1/6 », puis 2 |
| Codex (silhouettes, découverts) | ✅ | — | ✅ Chairy ×1 affiché, 5 silhouettes ; chevauchement de texte corrigé **sans re-vérification visuelle** |
| Carte « Nouvelle espèce » | ✅ | — | ❌ **non vue** (elle était déjà refermée lors de mes captures d'écran) |
| Message final du tutoriel | ✅ | ✅ étape `Done` atteinte | ❌ non vu (même raison) |
| Tutoriel guidé et garanti | ✅ | ✅ ratés illimités, recache au même endroit | ✅ bandeau Scan → Examiner → Capturer, marqueur « ? » |
| Interface PC | ✅ | — | ✅ |
| Interface tactile | ✅ (boutons dédiés, toucher d'objet) | — | ❌ **non testée** (émulateur d'appareil non utilisé) |
| Multijoueur : verrou, courses, départ | ✅ | ✅ 7 tests de concurrence | ❌ **non testé à 2 clients** dans Studio |
| Serveur peu peuplé (12 Mimics, ≥ 3/zone) | ✅ | ✅ 20 captures en boucle | — |
| Préparation sauvegarde (snapshot, store) | ✅ | ✅ aller-retour du profil | — |
| Performance avec tous les objets | — | — | 🟡 carte générée en 7-8 ms ; pas de mesure d'images/s ni de MicroProfiler |

## 3. Déroulé de la session Studio (Play solo)

1. Premier lancement : **bug visuel majeur**. Lampadaires enterrés, poubelles couchées,
   chaises enfoncées (`docs/screenshots/00_bug_pivot_avant_correction.jpg`). Cause : avec une
   `PrimaryPart`, Roblox ignore `Model.WorldPivot`, donc chaque objet était posé par son corps
   et non par sa base. Corrigé dans `PropBuilder` (`PivotOffset`). Vérifié après correctif
   (`01_spawn_indice_yeux.jpg`).
2. Console : `rbxasset://sounds/swoosh.wav` n'existe pas dans ce client (« Asset is not approved »).
   Remplacé par des sons intégrés. L'erreur n'apparaît plus ensuite.
3. Tutoriel : la chaise montre ses yeux dès l'apparition. `E` donne « SIGNAL : TRÈS FORT »,
   la chaise sursaute, le bandeau passe à « Examiner » et un « ? » apparaît. `F` révèle Chairy
   (étiquette, compte à rebours de 30 s, bouton « CAPTURER ! »). `F` ouvre le minijeu.
   Toute la séquence prend environ 3 s (`02_revelation_chairy.jpg`, `03_minijeu_capture.jpg`).
4. Minijeu : le journal serveur (Studio uniquement) confirme chaque impulsion, par exemple
   « impulsion A14 : réussie à 0.44 (1/0) ». Latence client → serveur mesurée : 32 ms.
   Un écart apparent entre l'écran et le jugement serveur a été examiné. `os.clock()` côté
   client mesure bien le temps réel (3,016 s pour `task.wait(3)`) ; l'écart venait du délai de
   mes captures d'écran, et le serveur était cohérent avec la trajectoire du curseur.
5. Capture réussie, puis Codex : Chairy ×1 (`04_codex.jpg`).
6. Des impulsions et déplacements que je n'avais pas envoyés sont apparus : la personne
   devant l'écran jouait en parallèle dans la même fenêtre. Sa partie a validé au passage le
   chemin **Mimic partagé** (« capture réussie : chairy (doublon) », `05_village_vers_parc.jpg`).
   J'ai alors arrêté de piloter Studio.
   La liaison de la gâchette `ButtonR2`, d'abord soupçonnée, a été retirée par précaution.

Erreur restante dans la console, **non liée au jeu** : `ContentId rbxassetid://203785492 failed`
provient de la Boîte à outils de Studio (contexte « Studio »).

## 4. Limitations connues

- **Non testé en Studio** : 2 joueurs simultanés, interface tactile, Zone Commerciale,
  révélations et fuites des 5 autres espèces, carte de découverte, message final du tutoriel.
- **Types stricts non vérifiés** (pas d'analyseur Luau installé).
- **Sons** : seuls des sons intégrés au client sont utilisés. `electronicpingshort.wav` et
  `button.wav` se chargent sans erreur ; `snap.wav` et `clickfast.wav` n'ont pas été
  confirmés à l'oreille. Aucun son n'a été écouté (vérification par la console uniquement).
- **Inventaire en mémoire** : perdu à la fermeture du serveur (attendu en V0.1).
  Une reconnexion sur le même serveur devrait conserver la collection (code en place, non testé).
- **Fenêtre de latence** : un tricheur peut choisir son instant d'impulsion dans une fenêtre
  de 0,12 à 0,4 s. Le gain est limité, mais il existe.
- **Visée automatique** : l'objet visé est celui que regarde la caméra dans la portée.
  À éprouver en test joueur, surtout sur mobile.
- **Plugin Rojo de Studio** trop ancien pour Rojo 7.7.1 (« Can't parse JSON ») : la
  synchronisation en direct ne fonctionne pas tant qu'il n'est pas mis à jour. Le build
  `.rbxl` fonctionne.
- Les objectifs de temps (30 s / 90 s / 5 min / 10 min) ne sont vérifiés que pour la première
  capture (environ 3 s dans le meilleur cas, en connaissant le jeu). Aucun test avec un joueur novice.

## 5. Corrections faites pendant la validation

| Problème | Correction |
|---|---|
| Objets mal posés (pivot ignoré avec PrimaryPart) | `body.PivotOffset = body.CFrame:Inverse()` dans `PropBuilder.build` |
| Son `swoosh.wav` indisponible | remplacé par `electronicpingshort.wav` / `button.wav` |
| Texte « Non découvert » chevauchant la rareté dans le Codex | libellé retiré, largeurs ajustées |
| Texte du minijeu chevauchant le bouton IMPULSION | largeur réduite, retour à la ligne |
| Lecture du scanner tronquée | panneau élargi (190 → 240 px) |
| Gâchette R2 de manette pouvant déclencher des impulsions | liaison retirée |
| Débogage | journal serveur des impulsions et captures + `_G.MimicHuntWorld` (Studio uniquement) |
