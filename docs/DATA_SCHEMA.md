# MIMIC HUNTERS — Données persistantes (V0.2)

## 1. Audit de la V0.1 (point de départ)

| Élément V0.1 | Limite constatée |
|---|---|
| `SessionInventory` : un compteur par espèce (`count`, `discoveryOrder`) | aucun exemplaire individuel : impossible de distinguer deux Chairy, d'ajouter une mutation, un favori, une date |
| Idempotence par identifiant de tentative (`"A12"`) | unique dans **un** serveur seulement : non fiable une fois les données partagées entre serveurs |
| `MemoryProfileStore` | mémoire du serveur : tout est perdu à l'arrêt ; aucun verrou, aucune gestion d'erreur |
| Profil `{ version = 1, inventory, tutorialDone }` | pas de favoris, réglages, objectifs ni cosmétiques |

## 2. Schéma v2 (`src/server/Core/ProfileSchema.luau`)

Une clé DataStore par joueur (`player_<userId>`), contenant :

```text
record = {
  data = Profile,                       -- le profil ci-dessous
  meta = { lock = { jobId, sessionId, at }?, savedAt, writes }
}

Profile = {
  schemaVersion = 2,
  createdAt, updatedAt,                 -- os.time()
  nextSerial,                           -- compteur d'exemplaires, ne recule jamais
  specimens  = { [id] = Specimen },
  codex      = { [speciesId] = { discoveredAt, order, captured, mutations = { [mutation] = true } } },
  grants     = { [captureKey] = specimenId },   -- idempotence (100 dernières captures)
  grantOrder = { captureKey },
  objectives = { [objectiveId] = completedAt },
  cosmetics  = { title?, scannerColor, unlocked = { [rewardId] = true } },
  settings   = { sfx, reducedEffects },
  stats      = { totalCaptures, mutations = { [mutation] = count } },
  tutorialDone,
}

Specimen = { id, speciesId, rarity, mutation, seed, acquiredAt, favorite }
```

| Champ d'exemplaire | Règle |
|---|---|
| `id` | `S<userId d'origine>-<numéro>` attribué par le serveur. Le préfixe garde l'identifiant unique même si l'exemplaire change un jour de propriétaire (échanges futurs) |
| `rarity` | figée à la capture : un rééquilibrage du catalogue ne modifie pas ce qui est possédé |
| `mutation` | `Standard`, `Chromatic` ou `Spectral` ; tirée côté serveur à la capture réussie |
| `seed` | graine de la variation d'apparence, reproductible sur tous les clients |
| `acquiredAt`, `favorite` | date de capture (os.time) et favori |

Préparé pour la suite, sans être développé : musée (référencer des `id`), échanges (déplacer un
`Specimen` d'un profil à l'autre, l'`id` reste unique), mutations avancées (nouvelles valeurs de
`mutation`), comparaison de collections (`codex` + `stats`).

Limites : 2000 exemplaires par profil (≈ 140 octets chacun, loin des 4 Mo d'une clé). Au-delà,
la capture est refusée avec un message (aucune perte silencieuse).

### Migrations

`ProfileSchema.migrate(data)` applique les étapes N → N+1 puis répare les champs (`sanitize`).

| De | Vers | Transformation |
|---|---|---|
| rien | v2 | profil neuf |
| v1 (V0.1) | v2 | chaque capture comptée devient un exemplaire Standard (graine déterministe), codex reconstruit |
| v3+ | — | **refusé** (`FutureVersion`) : un ancien serveur n'écrase jamais un profil plus récent |

## 3. Sauvegarde (`ProfileService`, `DataStoreBackend`)

| Exigence | Mise en œuvre |
|---|---|
| Écritures atomiques | `UpdateAsync` uniquement ; la transformation est pure et rejouable |
| Sessions sûres | verrou `{ jobId, sessionId, at }` posé au chargement, vérifié et rafraîchi à chaque sauvegarde ; un verrou frais d'un autre serveur bloque le chargement (4 nouvelles tentatives espacées de 5 s) ; un verrou de plus de 6 min (serveur arrêté brutalement) est repris |
| Verrou perdu | sauvegarde refusée → session « Lost » → plus aucune acquisition, joueur déconnecté avec un message |
| Erreurs et limites | 5 tentatives avec délais 1, 2, 4, 8 s ; attente du budget `GetRequestBudgetForRequestType` ; au plus une écriture toutes les 7 s par clé |
| Quand | après chaque capture (≈ 7 s au plus), toutes les 60 s, au départ du joueur, à la fermeture du serveur (`BindToClose`) |
| Pas de perte ni de duplication | clé de capture `JobId:tentative` mémorisée dans le profil ; numéro d'exemplaire persistant ; un profil non chargé de manière sûre n'est **jamais** écrit |
| Pas d'acquisition sans profil sûr | `HuntWorld` refuse le démarrage d'une capture (`ProfileUnavailable`) ; nouvel essai de chargement toutes les 30 s |
| Studio ≠ jeu publié | Studio utilise `MimicHunters_Profiles_v2_STUDIO` ; si les DataStores sont inaccessibles (place locale), stockage en mémoire avec un avertissement |
| Tests | `MemoryBackend` : pannes injectées, budget réglable, plusieurs « serveurs » sur le même stockage |

États du profil vus par le joueur : `Loading`, `Ready`, `Unavailable`, `Locked`, `Lost`,
`FutureVersion`, `Corrupt` (message affiché pour chacun).

## 4. Réseau

| Événement | Sens | Contenu |
|---|---|---|
| `CollectionSnapshot` | serveur → client | collection complète à la connexion (résumé + exemplaires) |
| `CollectionDelta` | serveur → client | exemplaire ajouté + résumé, après chaque capture |
| `CollectionResult` | serveur → client | réponse à un favori, un cosmétique ou un réglage |
| `ProfileStatus` | serveur → client | état du profil |
| `SetFavorite`, `EquipCosmetic`, `UpdateSettings` | client → serveur | demandes validées par le serveur (propriété, déblocage, types, anti-spam) |
