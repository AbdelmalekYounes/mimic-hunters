# MIMIC HUNTERS — Préparer une publication privée de test (V0.3.1)

> **Rien n'a été publié.** Ce document prépare une publication que **toi seul** peux
> autoriser. Aucune expérience Roblox n'a été créée, aucun réglage de compte ou d'expérience n'a
> été modifié.

## 1. Pourquoi publier

Studio, sur une place non publiée, n'a pas accès aux DataStores : toute la persistance a été
testée avec des stockages simulés (Lune, mémoire de Studio). Trois choses ne se vérifient que
sur une expérience publiée :

| À vérifier | Comment |
|---|---|
| Le vrai DataStore (`UpdateAsync`, verrous, latence réelle) | script de contrôle automatique (§ 3) |
| Deux serveurs réellement distincts, fermeture réelle (`BindToClose`) | manipulations manuelles (§ 4) |
| Plusieurs vrais joueurs (visites, Museum Hunt, captures concurrentes) | playtest ([PLAYTEST_PLAN.md](PLAYTEST_PLAN.md)) |

## 2. Principe de sécurité

- Une **expérience de test séparée**, privée, créée pour l'occasion (par exemple
  « MIMIC HUNTERS — Test privé »). Les DataStores appartiennent à l'expérience : ceux du test
  ne peuvent jamais toucher ceux d'une future expérience publique.
- Le script de contrôle écrit dans un DataStore **dédié** (`MimicHunters_DataStoreCheck_v031`),
  avec des clés `check_<exécution>_<n>` où `n` est négatif (impossible pour un vrai joueur). Il
  ne supprime rien.
- Le jeu lui-même écrit dans `MimicHunters_Profiles_v2` **de l'expérience de test** : ce sont
  des profils de test.
- Aucune opération destructive, aucun produit Robux, aucune modification de sécurité du
  compte.

## 3. Contrôle automatique du vrai DataStore

Fichiers :

- `datastore-check.project.json` : le jeu + le contrôle. **Ne jamais publier ce fichier sur
  une expérience publique.**
- `tests/datastore/DataStoreCheck.luau` : 9 scénarios (1, 2–4, 5–9, 10, 13, 14, 15, corruption,
  16 partiel), exécutés par le vrai `ProfileService`.
- `tests/datastore/RealDataStoreCheck.server.luau` : lanceur Roblox.
- Le script a été vérifié sur un DataStore simulé (`tests/specs/datastore_check.spec.luau` :
  9/9). Cela prouve que le script est juste, **pas** que le vrai DataStore se comporte pareil.

Étapes, à faire toi-même ou à m'autoriser explicitement à faire dans la VM :

1. Construire la place : `rojo build datastore-check.project.json -o build/DataStoreCheck.rbxl`.
2. L'ouvrir dans Studio, puis **Fichier → Publier sur Roblox sous… → Nouvelle expérience**,
   nom « MIMIC HUNTERS — Test privé ». Accès : **privé**.
3. Paramètres du jeu → Sécurité → **Activer l'accès de Studio aux services d'API**, sur
   **cette expérience de test uniquement**.
4. Lancer **Jouer** (ou **Exécuter**). La sortie affiche une ligne `[DataStoreCheck]` par
   scénario, puis le total (attribut `DataStoreCheck` de Workspace). Durée ≈ 1 à 2 min.
5. Me transmettre la sortie (copie du texte) pour que je l'ajoute au rapport.

## 4. Vérifications manuelles (vrais serveurs)

À faire sur l'expérience de test, avec la place normale (`default.project.json`) publiée.

| # | Scénario | Manipulation | Attendu |
|---|---|---|---|
| M1 | Reconnexion sur un autre serveur | capturer 1 Mimic, quitter, rejoindre un **autre** serveur (Creator Hub → Serveurs, ou ami sur un autre serveur) | le Mimic est là, même numéro, même mutation |
| M2 | Changement de serveur rapide | rejoindre un 2e serveur sans attendre | message « encore ouvert sur un autre serveur », puis chargement < 1 min, rien de perdu |
| M3 | Fermeture du serveur | capturer, puis arrêter le serveur (Creator Hub → Arrêter tous les serveurs) | à la reconnexion, la capture est là |
| M4 | Exposition + reconnexion | exposer 6 Mimics, changer les 4 styles, quitter, revenir | musée identique |
| M5 | Plusieurs joueurs | voir [PLAYTEST_PLAN.md](PLAYTEST_PLAN.md) | — |

Les pannes réelles de DataStore (scénarios 11 et 12) ne se provoquent pas à la demande : elles
restent couvertes par les tests simulés (pannes injectées, panne prolongée → acquisitions
suspendues).

## 5. Ce qui reste bloqué sans publication

Scénarios 4 (vrai second serveur), 14 (vrai arrêt brutal), 16 (vrai `BindToClose`), latence et
quotas réels du DataStore, comportement avec plusieurs vrais joueurs. Tant que ce n'est pas fait,
les rapports gardent la mention « vrai DataStore non validé ».

## 6. Ce dont j'ai besoin de ta part

- Ton **autorisation explicite** pour créer l'expérience de test et activer l'accès API dessus,
  ou que tu fasses les étapes 2 et 3 toi-même.
- Pour les vérifications manuelles et le playtest : 1 à 4 autres comptes que **tu** invites
  (je ne crée et n'utilise aucun compte).
