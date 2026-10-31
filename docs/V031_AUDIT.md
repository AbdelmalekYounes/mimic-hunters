# MIMIC HUNTERS — Audit technique V0.3.1

Branche `feature/v0.3.1-validation`, partie de `feature/v0.3-museums` (912f203, identique à
`origin`). Audit fait le 31/10/2026 en lisant le code (≈ 14 800 lignes Luau) et la
documentation, en trois volets (persistance, autorité serveur et multijoueur, performances
client), plus une analyse de types `luau-lsp` ajoutée à la chaîne de validation.

Sévérités : **critique** (perte de données ou triche généralisée probable) · **élevée** ·
**moyenne** · **faible**. Colonne « Vérifié » : ✅ relu et confirmé dans le code avant
correction ; ⚠️ mécanisme lu, à confirmer en conditions réelles (réplication, concurrence
Roblox). Colonne « Statut » : jalon où le point est traité.

Aucun défaut **critique** n'a été trouvé. Le socle est sain : positions toujours lues côté
serveur, identifiants et nombres validés (NaN/∞ refusés), les 15 RemoteEvents client → serveur
sont limités, verrou de Mimic par joueur, récompense idempotente, lecture en échec jamais
traitée comme un profil neuf, ancienne session incapable d'écraser une plus récente
(`sessionId` vérifié dans `UpdateAsync`), aucune connexion `RenderStepped`/`Heartbeat` créée par
objet, aucune collection complète renvoyée en boucle.

## 1. Analyse de types (`luau-lsp`)

| Élément | Résultat |
|---|---|
| Outil | `luau-lsp` 1.70.1, épinglé dans `rokit.toml` ; définitions Roblox de la même version |
| Script | `tools/luau-analyze.ps1` (définitions + sourcemap Rojo + analyse de `src`) ; étape « Luau : analyse de types » de `test.cmd` et de la VM |
| Avant | **45 erreurs de type distinctes** (147 lignes, un module requis plusieurs fois est signalé plusieurs fois) |
| Après | **0 erreur** ; l'étape échoue dès qu'une erreur apparaît (vérifié en injectant une erreur) |
| Nature des 45 erreurs | faux positifs du vérificateur, aucun bug d'exécution : tableaux `{ CFrame, Vector3 }` inférés comme `{ CFrame }`, `pcall` sur une fonction sans retour, `x or {}`, statut rétréci puis modifié par un appel, comparaisons `Model == nil` |
| Correction | annotations explicites (types de tables, `:: any` ciblés), deux tableaux de murs convertis en enregistrements `{ cf, size }` ; aucun changement de comportement |
| Solveur | ancien solveur (défaut de luau-lsp) ; le nouveau (`LuauSolverV2`) donne autant de faux positifs (48) sur ce code |

## 2. Persistance (traitée au jalon 2)

| # | Sév. | Constat | Fichier | Vérifié | Statut |
|---|---|---|---|---|---|
| P1 | élevée | Deux `load` concurrents pour le même joueur (reconnexion pendant les nouvelles tentatives d'un profil verrouillé) : le second écrase la session du premier, puis `releaseUntouched` la libère → joueur « Ready » sans session, plus aucune sauvegarde, verrou libre | `ProfileService` (`load`, `_sessions[userId]`), `HuntServer` (`retryLoad`) | ⚠️ | J2 |
| P2 | moyenne | Double `release` (départ + `BindToClose`) : la seconde, sans données, peut se réveiller avant la première et libérer le verrou → les dernières secondes de jeu perdues | `ProfileService.release`, `closeAll` | ⚠️ | J2 |
| P3 | moyenne | `BindToClose` peut dépasser le délai de Roblox (≈ 30 s) : reprises + attente de budget + intervalle minimal de 7 s par clé | `ProfileService` | ⚠️ | J2 |
| P4 | moyenne | Enregistrement corrompu (non-table, ou table sans `data` déjà écrite) traité comme vide : remplacé dès le chargement | `ProfileService` (`acquireTransform`) | ⚠️ | J2 |
| P5 | moyenne | `sanitize` supprime sans journal les exemplaires invalides (définitif à la sauvegarde suivante) et tout champ inconnu (mise à jour progressive) | `ProfileSchema.sanitize` | ⚠️ | J2 |
| P6 | moyenne | Panne prolongée en cours de session : captures toujours acceptées, aucun signal au joueur | `ProfileService`, `HuntWorld` | ⚠️ | J2 |
| P7 | faible | `release` appliquée mais signalée en erreur (délai réseau) → `LockLost` à tort | `ProfileService` | ⚠️ | J2 |
| P8 | faible | `migrations[1]` produit directement un profil v3, puis `migrations[2]` s'applique encore (sans effet aujourd'hui) | `ProfileSchema` | ⚠️ | J2 |
| P9 | faible | `CaptureLedger._rewarded` grossit sans limite sur un serveur de longue durée (mémoire seulement) | `CaptureLedger` | ⚠️ | J2 |
| P10 | faible | `DataStoreBackend.choose` lève une erreur en jeu publié si `GetDataStore` échoue : arrêt complet de `HuntServer.start` | `DataStoreBackend` | ⚠️ | J2 |

Couverture des 16 scénarios de sauvegarde demandés : voir [V031_VALIDATION.md](V031_VALIDATION.md)
(jalon 2).

## 3. Autorité serveur et multijoueur

| # | Sév. | Constat | Fichier | Vérifié | Statut |
|---|---|---|---|---|---|
| S1 | élevée | Museum Hunt : les copies étaient tirées en premier et envoyées (puis créées) dans cet ordre → un client modifié lisant l'ordre des enfants du dossier trouvait les copies | `MuseumCore.startHunt`, `MuseumServer._HuntSpawn` | ✅ | **corrigé J1** : objets triés par cachette ; test « l'ordre ne désigne jamais les copies » (11 graines) |
| S2 | moyenne | Leurres de type aléatoire, copies du type de leur espèce : un coup d'œil sur les espèces exposées éliminait la plupart des leurres | `MuseumCore.startHunt` | ✅ | **corrigé J1** : les leurres reprennent les types des copies ; test |
| S3 | faible | Seules les copies émettent des indices (le `propId` de l'indice désigne la copie) | `MuseumCore.tick` ; même principe dans le monde | ✅ | **accepté** : c'est la mécanique de jeu (l'indice visuel est le cœur de la chasse) ; récompenses bornées |
| S4 | faible | Sortir du jardin annulait sans délai : relance immédiate pour une nouvelle disposition | `MuseumCore._cancelHunt` | ✅ | **corrigé J1** : le délai de 20 s s'applique ; test |
| S5 | faible | Musée sans vitrine : la chasse utilisait des exemplaires non exposés (espèce, mutation, graine envoyées au visiteur) | `Collection.huntSources` | ✅ | **corrigé J1** : refus `EmptyMuseum` ; test (aucun objet créé) |
| S6 | faible | Un cosmétique pouvait être équipé dans le mauvais emplacement (`equip("title", "Cyan")`) | `Collection.equip` | ✅ | **corrigé J1** : emplacement vérifié via le catalogue ; test |
| S7 | faible | Réponses de refus envoyées avant l'anti-spam (`NoHunt`, profil indisponible) : réponses illimitées | `MuseumCore.huntScan/huntInspect/_ownRequest`, `HuntWorld._collectionRequest` | ✅ | **corrigé J1** : anti-spam en premier ; test |
| S8 | faible | Déplacement rapide accepté pendant une capture : Mimic verrouillé jusqu'à 14 s | `MuseumCore.travel` | ✅ | **corrigé J1** : refus `Capturing` (message joueur) ; test |
| S9 | moyenne | Liste des musées et actions d'exposition partageaient le même seau anti-spam : l'onglet Visites (rafraîchi en rafale) bloquait l'exposition | `MuseumCore.list`, `GameConfig.RateLimits` | ✅ | **corrigé J1** (seau `MuseumList`) ; rafale côté client : J4 |
| S10 | info | Le `SpecimenId` affiché sur les vitrines contient l'identifiant du joueur et un numéro de série | `MuseumBuilder` | ✅ | accepté (données publiques par choix) |
| S11 | info | `MaxPlayers` du serveur publié non défini dans le dépôt (8 parcelles, file d'attente au-delà) | — | — | à régler à la publication (≤ 8 conseillé) |

## 4. Performances et fuites côté client (traitées aux jalons 4 et 6)

| # | Sév. | Constat | Fichier | Vérifié | Statut |
|---|---|---|---|---|---|
| C1 | élevée | Ouverture du panneau Collection : le zoom (UIScale) change la taille à chaque image → disposition + reconstruction complète des cartes ≈ 9 fois en 0,15 s (des milliers d'Instances) ; un clic, un favori reconstruisent aussi tous les aperçus | `CollectionPanel` | ⚠️ | J4 |
| C2 | moyenne | Onglet Visites : une requête `RequestMuseums` par rafraîchissement (≈ 10 à l'ouverture) | `VisitsTab` | ⚠️ | J4 (serveur déjà corrigé, S9) |
| C3 | moyenne | Le serveur reconstruit les 6 vitrines (≈ 200 à 300 Instances répliquées) à chaque action, même un simple changement de couleur | `MuseumCore._renderEvent`, `MuseumBuilder.renderExhibits` | ⚠️ | J4 |
| C4 | moyenne | « Effets réduits » laisse les lumières de mutation allumées à toute distance (régression : le test de distance est sauté) | `MutationFx` | ⚠️ | J4 |
| C5 | faible | Aperçus et animations qui continuent pour rien (carte de capture fermée, Mimics révélés animés sans distance max, barre de défi reformatée à chaque image, marqueur du tutoriel recréé) | `CollectionController`, `MimicVisuals`, `HuntController`, `TutorialController` | ⚠️ | J4 |
| C6 | faible | Yeux d'un exposé sorti du budget d'animation pendant un clignement ; aperçu vide en rouvrant le même exemplaire sur téléphone | `MuseumController`, `CollectionPanel` | ⚠️ | J6 |
| C7 | à vérifier | Connexions par joueur de `TitleController` jamais déconnectées (fuite si l'objet Player n'est pas détruit) | `TitleController` | ⚠️ | J4 |

« Effets réduits » aujourd'hui : supprime l'anneau de révélation, divise les particules par 3,
fige les teintes de mutation. Il ne traite **pas** les effets potentiellement gênants (indice
`glitch` qui change de couleur à chaque image, `flicker` à 7–16 Hz, éclair de révélation) :
à compléter au jalon 4.

## 5. Documentation obsolète (corrigée J1)

README (arborescence) et ARCHITECTURE (schéma, responsabilités, protections) décrivaient encore
`SessionInventory` et `MemoryProfileStore` (V0.1), qui n'existent plus : remplacés par
`Collection`, `ProfileSchema`, `ProfileService`, `MemoryBackend`, `DataStoreBackend`, et les
modules des musées. DATA_SCHEMA garde ces noms dans son audit historique de la V0.1 (voulu).

## 6. Dépendances

Outils épinglés (Rokit) : Rojo 7.7.1, Lune 0.11.1, Selene 0.27.1, StyLua 0.20.0, luau-lsp
1.70.1 (ajouté). Aucune API Roblox dépréciée relevée dans le code lu. Aucune dépendance
externe (Wally) : rien à mettre à jour.
