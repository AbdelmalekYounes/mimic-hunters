# MIMIC HUNTERS — Données persistantes (V0.2, V0.3, V0.3.1)

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
  meta = { lock = { jobId, sessionId, at }?, savedAt, writes,
           hasData,     -- V0.3.1 : des données ont déjà été écrites (leur disparition = illisible)
           commit }     -- V0.3.1 : identifiant de la dernière écriture (réponse perdue ≠ verrou perdu)
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
| v2 (V0.2) | v3 | ajoute `museum` (6 vitrines vides, styles par défaut) et `hunts` ; **tout le reste est conservé** (exemplaires, objectifs, cosmétiques, réglages) |
| v4+ | — | **refusé** (`FutureVersion`) : un ancien serveur n'écrase jamais un profil plus récent |

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
`FutureVersion`, `Corrupt`, `Degraded` (V0.3.1) — message affiché pour chacun.

### Fiabilisation V0.3.1 (audit, [V031_AUDIT.md](V031_AUDIT.md))

| Règle | Mise en œuvre | Test |
|---|---|---|
| Un seul chargement à la fois par joueur, annulé si le joueur part | `ProfileService.load(userId, wanted)` | `profile_concurrency › P1` |
| Libération ciblée : un ancien chargement ne libère jamais la session d'un nouveau | `release(userId, data, sessionId)` | `P1 › libération ciblée` |
| Départ puis fermeture : une seule libération, avec les données | session `Releasing` attendue, pas relancée | `P2` |
| Fermeture bornée à 24 s (BindToClose ≈ 30 s), réessais compris | échéance globale ; attentes plafonnées ; sessions non libérées journalisées | `P3` (DataStore lent et en panne) |
| Enregistrement illisible (non-table, `data` non-table, `data` disparue alors que `hasData`) | `Corrupt` : rien n'est écrit, rien n'est effacé, captures désactivées | `P4` |
| Exemplaire illisible au chargement | mis en **quarantaine** dans le profil (`quarantine`, 50 au plus), compté et journalisé, jamais effacé | `P5` |
| Champ inconnu (version plus récente, même schéma) | conservé tel quel | `P5` |
| 2 sauvegardes périodiques consécutives en échec (chacune déjà réessayée 5 fois) | statut `Degraded` : profil gardé en mémoire, **captures et modifications du musée suspendues**, message ; retour à `Ready` au premier succès | `P6`, `persistence › panne prolongée` |
| Écriture appliquée mais réponse perdue | identifiant `commit` reconnu au nouvel essai : « Saved », pas « verrou perdu » | `P7` |
| DataStore inaccessible au démarrage d'un serveur publié | stockage « indisponible » : profils `Unavailable`, aucune acquisition, le serveur continue (jamais de repli mémoire en jeu publié) | revue de code (API Roblox) |

## 4. Réseau

| Événement | Sens | Contenu |
|---|---|---|
| `CollectionSnapshot` | serveur → client | collection complète à la connexion (résumé + exemplaires) |
| `CollectionDelta` | serveur → client | exemplaire ajouté + résumé, après chaque capture |
| `CollectionResult` | serveur → client | réponse à un favori, un cosmétique ou un réglage |
| `ProfileStatus` | serveur → client | état du profil |
| `SetFavorite`, `EquipCosmetic`, `UpdateSettings` | client → serveur | demandes validées par le serveur (propriété, déblocage, types, anti-spam) |

## 5. Schéma v3 : musées (V0.3)

```text
museum = {
  slots = { specimenId | "" } × 6,      -- identifiants seulement, jamais une copie du Mimic
  wall, lighting, pedestal, theme,      -- identifiants d'options (Config/MuseumStyles)
}
hunts = {
  played, completed, best,              -- Museum Hunt : parties, réussites complètes, record
  museums = { ["<userId>"] = lastAt },  -- musées où au moins une copie a été trouvée
  museumOrder = { "<userId>" },         -- borné à 200 (MaxHuntMuseums)
}
```

| Règle | Où |
|---|---|
| Une vitrine ne référence qu'un exemplaire **possédé** | `Collection.exhibit` (refus `NotOwned`) et `ProfileSchema.sanitize` (vitrine vidée) |
| Un exemplaire n'est jamais dans deux vitrines | `Collection.exhibit` (`AlreadyExhibited`) et `sanitize` (doublon vidé) |
| Exposer ne crée ni ne déplace aucun exemplaire | la vitrine ne stocke qu'un identifiant ; tests « owned / totalCaptures inchangés » |
| Référence devenue invalide | vitrine affichée vide (`museumView`), l'exemplaire, s'il existe, reste dans la collection |
| Style inconnu | gardé dans le profil, rendu avec l'option par défaut (`MuseumStyles.resolve`) |
| Modifications concurrentes | verrou de session de `ProfileService` : un second serveur n'a pas de profil sûr → `ProfileUnavailable` |

Les parcelles ne sont **pas** persistées : elles sont attribuées à chaque connexion
(`PlotRegistry`), et le musée est reconstruit à partir du profil.

Réseau (V0.3) :

| Événement | Sens | Contenu |
|---|---|---|
| `RequestTravel(kind, target?)` | client → serveur | `base`, `village` ou `museum` + propriétaire ; destination choisie par le serveur |
| `SetExhibit(slot, id?)`, `MoveExhibit(a, b)`, `SetMuseumStyle(kind, id)` | client → serveur | toujours sur la collection du demandeur |
| `RequestMuseums` → `MuseumList` | aller-retour | statistiques publiques des musées présents |
| `StartMuseumHunt(ownerId)` | client → serveur | lancement du défi (portée, état, délais vérifiés) |
| `MuseumInfo`, `MuseumResult`, `HuntUpdate` | serveur → client | parcelle, résultats, déroulement du défi |

Limite inchangée : le vrai DataStore n'a été validé dans aucune expérience publiée ; toute la
persistance a été testée avec le stockage simulé (Lune) et le stockage mémoire de Studio. Un
contrôle automatique sur un vrai DataStore est prêt : [PRIVATE_TEST_PUBLISH.md](PRIVATE_TEST_PUBLISH.md).