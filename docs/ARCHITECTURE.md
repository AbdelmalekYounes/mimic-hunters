# MIMIC HUNTERS — Architecture et choix techniques (V0.3)

## 1. Principe directeur

**Toute la logique de jeu autoritaire vit dans des modules purs, sans API Roblox**
(`src/server/Core`, `src/shared/Logic`). Le serveur Roblox n'est qu'un adaptateur :
il reçoit les requêtes, lit la position réelle du personnage et l'heure, appelle
`HuntWorld`, puis diffuse les événements que `HuntWorld` retourne.

Conséquence : les règles, la sécurité et les accès concurrents se testent dans Lune,
en millisecondes, avec une horloge et une graine aléatoire contrôlées.

```
 Client (StarterPlayerScripts)          Serveur (ServerScriptService)
 ─────────────────────────────          ───────────────────────────────────────────
 ScannerController ── RequestScan ───▶  HuntServer (adaptateur)
                   ── RequestInspect ─▶   │  position = HumanoidRootPart du serveur
 CaptureController ── RequestCapture ─▶   │  now = os.clock(), latence = GetNetworkPing
                   ── SubmitPulse ────▶   ▼
                                        HuntWorld (pur)  ──▶ events {name, userId?, payload}
 MimicVisuals   ◀── MimicUpdate / Clue ─┤   ├ MimicStateMachine   ├ CaptureLedger
 CaptureController ◀── PulseResult … ───┤   ├ EncounterGenerator  ├ RewardValidator
 CollectionController ◀── Inventory… ───┘   ├ CaptureMinigame     ├ SessionInventory
                                            ├ RateLimiter         └ TutorialFlow
```

## 2. Séparation des responsabilités

| Domaine | Module(s) |
|---|---|
| Configuration et catalogue | `shared/Config/GameConfig`, `MimicCatalog`, `Rarities`, `Sounds` |
| Génération des rencontres | `server/Core/EncounterGenerator`, `shared/Logic/WeightedPicker`, `Rng` |
| Interactions et récompenses (serveur) | `server/Core/HuntWorld`, `MimicStateMachine`, `CaptureLedger`, `RewardValidator` |
| Détection (client) | `client/Controllers/ScannerController`, `MimicVisuals` (indices) |
| Minijeu | `shared/Logic/CaptureMinigame` (règles), `client/Controllers/CaptureController` (affichage) |
| Inventaire de session | `server/Core/SessionInventory`, `server/Services/MemoryProfileStore` |
| Interface | `client/UI/Theme`, `Hud` (positions calculées par `shared/Logic/HudLayout`, pur et testé), `CollectionController`, `TutorialController` |
| Génération de la carte | `server/Map/MapLayout` (données), `MapBuilder`, `LightingSetup`, `shared/Builders/*` |

## 3. États d'un Mimic

```
Disguised ──reveal──▶ Revealed ──startCapture──▶ Capturing ──complete──▶ Captured (retiré)
    ▲                    │ 8 s                       │ échec / 14 s / joueur parti
    └─────settle──── Fleeing ◀────────────────────────┘
          (nouvel emplacement du même type, 2,2 s plus tard)
```

- `Revealed` et `Capturing` sont verrouillés sur un `ownerId`.
- `Captured` est terminal : l'enregistrement est supprimé et un remplaçant est planifié.
- Chaque transition vérifie l'état, le propriétaire et l'identifiant de tentative.
- `audience` = `nil` pour un Mimic partagé (événements diffusés à tous), `userId` pour le Mimic
  personnel du tutoriel (événements envoyés à ce seul joueur).

### Concurrence

Le serveur Luau exécute les gestionnaires d'événements un par un, et **aucune transition ne
cède la main** (pas de `task.wait`, pas d'appel bloquant entre la vérification et l'écriture).
Deux requêtes simultanées ne peuvent donc pas s'entrelacer : la première valide gagne, la
seconde voit l'état déjà modifié et échoue proprement (`Busy`, `NotOwner`, `AlreadyCapturing`…).
Les tests `hunt_world.spec.luau › interactions simultanées` rejouent ces courses.

## 4. Minijeu : pourquoi le client ne peut pas tricher

1. Le serveur crée la tentative et tire l'étape (vitesse, zone, phase) avec son propre RNG.
2. Le client affiche le curseur avec la **même fonction** `CaptureMinigame.cursorAt`.
3. À l'impulsion, le client envoie seulement `(attemptId, tempsÉcouléDepuisDébutÉtape)`.
4. Le serveur borne ce temps dans `[écouléServeur − fenêtre, écouléServeur]`, avec
   `fenêtre = clamp(ping + 0,08, 0,12, 0,40)` s, puis évalue lui-même la position.
5. Chaque impulsion acceptée relance une étape : client et serveur se resynchronisent à chaque échange.

Un tricheur peut au mieux choisir son instant dans la fenêtre de latence (≤ 0,4 s, souvent
0,12 s) ; il ne peut ni déclarer « réussi », ni rejouer une impulsion (délai minimal 0,2 s,
plafond de 12 impulsions), ni dépasser le délai de la tentative.

## 5. Protections

| Menace | Protection | Test |
|---|---|---|
| Spam des RemoteEvents | `RateLimiter` (seaux à jetons par joueur et par action) + délais de recharge | `guards.spec`, `hunt_world.spec › limite le spam` |
| Capture hors de portée | Position du `HumanoidRootPart` lue côté serveur ; portée horizontale + tolérance verticale | `hunt_world.spec › hors de portée`, `depuis le ciel` |
| Captures simultanées incohérentes | Verrou `ownerId`, une tentative active par joueur (`CaptureLedger`) | `interactions simultanées` |
| Objets inexistants / données invalides | `Validation.isId` (motif, longueur), types vérifiés, ids inconnus refusés | `rejette les données invalides` |
| Tentatives répétées | Statut de tentative terminal, `Resolved` sur rejeu | `ne duplique jamais une récompense` |
| Attribution multiple d'une récompense | `CaptureLedger:markRewarded` + `SessionInventory:add` idempotent par `attemptId` + `RewardValidator` | `rewards.spec` |
| Manipulation du résultat côté client | Le client n'envoie jamais de résultat ; temps borné (§4) ; fenêtre de latence elle-même bornée | `capture.spec › anti-triche`, `ignore un faux temps de latence` |
| Fuite d'information | Le client ne reçoit jamais la liste des Mimics cachés ; les ids de Mimic ne sont pas dérivés des objets ; indices limités aux joueurs proches | `envoie l'état initial`, `indices uniquement aux joueurs proches` |
| Gestionnaire qui plante | Chaque handler serveur est enveloppé dans `pcall` (`guarded`) | — (revue de code) |

## 6. Données et persistance (V0.2)

Détail complet : [DATA_SCHEMA.md](DATA_SCHEMA.md).

| Module | Rôle | Testé |
|---|---|---|
| `Core/ProfileSchema` | profil v2, migration depuis la V0.1, réparation, versions futures refusées | Lune |
| `Core/Collection` | exemplaires individuels, idempotence par clé de capture, codex, favoris, objectifs, cosmétiques, réglages | Lune + Studio |
| `Core/ProfileService` | chargement verrouillé, sauvegardes (capture, 60 s, départ, fermeture), réessais, budget | Lune (pannes, verrous, serveurs concurrents) |
| `Core/MemoryBackend` | stockage simulé (tests, repli Studio) | Lune + Studio |
| `Services/DataStoreBackend` | `UpdateAsync` ; DataStore distinct en Studio ; repli mémoire si inaccessible | **non testé sur un vrai DataStore** (place non publiée) |
| `Services/HuntServer` | relie les deux : profil chargé avant l'entrée dans le monde, `_ProfileChanged` → sauvegarde | Studio |

`HuntWorld` reste pur : il reçoit des données brutes (migrées par `ProfileSchema`), refuse
toute capture tant que le profil n'est pas sûr (`ready = false`), et signale les modifications
par des événements internes (`_ProfileChanged`, `_CosmeticsChanged`) que `HuntServer`
traite sans jamais les envoyer au client.

Mutations : tirées dans `HuntWorld._resolveSuccess` avec le générateur du serveur
(`Config/Mutations`). L'apparence d'un exemplaire (`Logic/SpecimenLook`) se recalcule à
partir de sa graine sur chaque client : rien d'autre que la graine et la mutation n'est stocké.

## 7. Rendu et performances

- Carte : quelques centaines de Parts ancrées (nombre exact non mesuré), générées en 7 à 8 ms
  (temps affiché par le serveur dans Studio). `StreamingEnabled = false`
  (petite carte, cohérence garantie des 41 objets côté client).
- Objets : le pivot de chaque Model est sa base au sol (`PrimaryPart.PivotOffset`), ce qui
  permet de poser, tourner et animer n'importe quel objet de la même façon.
- Animations : 100 % client, procédurales (`TweenService:GetValue` + `PivotTo`/`ScaleTo`).
  Aucune animation de Mimic n'est répliquée. Côté serveur, seuls 3 cristaux décoratifs ont un Tween.
- Indices : envoyés par `FireClient` aux seuls joueurs à moins de 60 studs.
- Boucle serveur : un `tick` toutes les 0,2 s (expirations, réapparitions, indices).

## 8. Choix écartés

- **Révéler l'état « Mimic » par un attribut répliqué** : simple, mais un exploiteur verrait
  tous les Mimics. Remplacé par des événements ciblés.
- **Faire juger le minijeu par le client** : interdit par le cahier des charges.
- **Pipeline Blender / rigs** : inutile pour la V0.1 ; Parts + animations procédurales suffisent.
- **Carte enregistrée dans le .rbxl** : la génération par script garde la carte versionnée
  dans Git, diffable et reproductible.

## 9. Musées et Museum Hunt (V0.3)

Même découpage que la chasse : un cœur pur testé dans Lune, un adaptateur Roblox mince.

| Module | Rôle | Testé |
|---|---|---|
| `Map/MuseumLayout` | plan du quartier : 8 parcelles, avenue, socles, cachettes, panneau (données pures) | Lune |
| `Core/PlotRegistry` | une parcelle par joueur, jamais partagée, file d'attente, libération | Lune |
| `Core/MuseumCore` | parcelles, déplacements, vitrines, styles, visites, Museum Hunt ; retourne des événements | Lune + Studio |
| `Core/Collection` (ajouts) | `exhibit`, `clearSlot`, `moveExhibit`, `setMuseumStyle`, `museumView`, `recordHunt` | Lune |
| `Map/MuseumBuilder` | géométrie (Parts), rendu des Mimics exposés (`MimicModelBuilder` + `SpecimenLook`), styles | Studio |
| `Services/MuseumServer` | RemoteEvents, événements internes (rendu, téléportation, objets de chasse) | Studio |
| `Controllers/MuseumController` | déplacements, Mimics « vivants », fiche d'inspection | Studio |
| `Controllers/HuntController`, `UI/MuseumTab`, `UI/VisitsTab` | défi, mode décoration, visites | Studio |

**Événements internes** (jamais envoyés au client) : `_MuseumRender`, `_MuseumClear`,
`_Teleport`, `_HuntSpawn`, `_HuntRemoveProp`, `_HuntDespawn` (plus `_ProfileChanged`).
`HuntServer` les transmet à `MuseumServer`. Pendant une Museum Hunt, il route aussi
`RequestScan` et `RequestInspect` (identifiants `MH…`) vers le défi : le joueur garde
les mêmes commandes.

**Sécurité.** Aucune requête de modification ne prend de propriétaire cible : vitrines et
styles portent toujours sur la collection du demandeur. Un visiteur ne peut donc rien modifier
chez un autre, par construction. La Museum Hunt ne lit que des vues : les copies sont des
données (espèce, graine, mutation) et l'adaptateur ne reçoit jamais l'information « copie ou
leurre » (seuls `kind` et `spot` partent vers `_HuntSpawn`).

**Anti-abus de la Museum Hunt** : portée de lancement (12 studs du panneau) et d'examen
(11 studs de la cachette) ; un défi par musée et par visiteur ; 20 s entre deux défis ;
cachettes inventées ou déjà trouvées refusées ; anti-spam ; annulation si le propriétaire part
(musée détruit), si le visiteur part ou quitte le jardin. Récompenses bornées : record personnel,
compteur de musées **différents** (une fois par musée), objectif à 3 musées. Deux comptes qui
s'aident ne gagnent chacun qu'un musée de plus.

**Budget de performance** (mesuré dans Studio, PC et mobile simulé) :

| Élément | Budget | Mesuré |
|---|---|---|
| Parts par musée, Mimics compris | ≤ 450 | 168 (6 Mimics) |
| Lumières du quartier | ≤ 30 | 24 (2 par musée + 6 lanternes + éclats Chromatic) |
| Mimics animés côté client | 12 (PC), 6 (tactile), à moins de 70 studs | plafond respecté |
| Effets de mutation | à moins de 45 studs (35 en tactile), lumière coupée au-delà | — |
| Particules | aucune dans les musées (révélations de la chasse seulement) | — |
| Aperçus 3D actifs | fiche, sélecteur et cartes de la page seulement ; vidés à la fermeture | — |

Les animations des Mimics exposés ne changent que l'affichage local (`PivotTo` sur les modèles
répliqués) : rien n'est envoyé au serveur, et la vitrine solide les contient.