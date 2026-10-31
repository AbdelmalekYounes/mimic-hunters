# MIMIC HUNTERS — Validation de la V0.3.2 (publication privée et playtests réels)

Branche `feature/v0.3.2-private-playtest`, partie de `feature/v0.3.1-validation` (efe1910,
identique à `origin`). Aucune branche précédente modifiée, rien fusionné. **Le jeu n'a jamais été
rendu public.** Aucun produit Robux, aucun compte créé, aucun testeur invité, aucun mot de passe
saisi.

Légende : ✅ **réel** = exécuté sur Roblox (vrai DataStore, expérience publiée) · 🧪 simulé ·
🧑 demande ton intervention · ⛔ non exécuté.

## 1. Résultats

| Contrôle | Résultat |
|---|---|
| Lune | **299 réussis, 0 échoué** |
| luau-lsp, Selene, StyLua | 0 erreur de type ; 0 erreur, 0 avertissement ; formatage conforme |
| Studio, bureau caché, 4 sessions | **104 réussis, 0 échoué, 0 ignoré** (régressions V0.1 à V0.3.1 comprises) |
| Studio dans la VM, 4 sessions | **104 réussis, 0 échoué, 0 ignoré** (exécution 20261031-150018) |
| **Vrai DataStore** (contrôle automatique, expérience privée) | ✅ **11/11** (exécution 0109ef9a) |
| **Vrai jeu + vrai DataStore**, deux sessions Studio | ✅ exemplaires, vitrines et style identiques |
| Serveur Roblox publié (rejoint par un vrai client) | ⛔ 🧑 (§ 4) |

## 2. Par étape

| Étape | État | Détail |
|---|---|---|
| 1 — Préparer | ✅ | branche créée ; scripts compatibles (2 places construites, la version jouable ne contient **aucun** script de contrôle) ; suite complète passée avant tout déploiement (104/104, 299/299) |
| 2 — Créer l'expérience privée | ✅ (sauf 8 joueurs : 🧑) | voir [PRIVATE_TEST_PUBLISH.md](PRIVATE_TEST_PUBLISH.md) : compte vérifié, nouvelle expérience, privée, API Studio activée pour elle seule |
| 3 — Vrai DataStore | ✅ 11/11 | [REAL_DATASTORE_VALIDATION.md](REAL_DATASTORE_VALIDATION.md) |
| 4 — Déployer le jeu | ✅ déployé · ⚠️ vérifié dans Studio seulement | jeu publié sans contrôle ; démarrage, village (41 objets, carte générée), sauvegarde sur le DataStore de l'expérience et persistance entre deux sessions vérifiés **dans une session Studio du lieu publié** ; sur serveur publié : 🧑 |
| 5 — Préparer le playtest | ✅ préparé | [TESTER_GUIDE.md](TESTER_GUIDE.md) (texte à envoyer + étapes d'invitation) ; aucun testeur invité |
| 6 — Performance et expérience | ✅ préparé · ⛔ mesuré | grilles appareils et première session : [PLAYTEST_RESULTS.md](PLAYTEST_RESULTS.md) (modèle vide) ; aucune mesure sur téléphone ou tablette réels |
| 7 — Analytics | ⚠️ | `AnalyticsServer` présent dans le jeu publié ; **réception dans le Creator Hub non confirmée** (aucune partie sur serveur publié) |
| 8 — Corriger | ✅ | aucun P0/P1 de jeu constaté pendant ces tests réels ; 3 anomalies d'outillage corrigées (§ 3) |
| 9 — Validation finale | ✅ | § 1 |

## 3. Problèmes trouvés et corrigés

| Problème | Gravité | Correction |
|---|---|---|
| Contrôle DataStore : 5–9 en échec sur le vrai DataStore alors que les données étaient intactes (ordre des clés de `HttpService:JSONEncode` non garanti) | test (faux négatif) | comparaison champ par champ qui nomme la première différence ; 9/9 puis 11/11 |
| Déploiement : « Publier sous → Écrire par dessus » bloqué dans Studio | outillage | import d'un modèle dans le lieu ouvert depuis Roblox, puis Publier (`deploy/`) |
| Script d'installation : `Lighting.Technology` interdit à la barre de commande ; l'erreur faisait annuler la commande et détruisait le contenu de la copie locale (rien n'a été publié dans cet état) | outillage | ligne retirée (déjà Voxel) ; contenu vérifié avant chaque publication |

## 4. Ce qui reste à faire par toi

1. **8 joueurs par serveur** : Creator Hub → Configurer → Lieux (2 min).
2. **Test sur serveur publié** (M1–M4 de PRIVATE_TEST_PUBLISH.md) : jouer avec `youyou31110`,
   quitter, revenir, vérifier les Mimics ; arrêter un serveur pendant une partie.
3. **Inviter 3 à 5 testeurs** (amis Roblox de `youyou31110`) : Fichier → Inviter des testeurs
   anticipés.
4. **Séance de 20 minutes** avec [PLAYTEST_PLAN.md](PLAYTEST_PLAN.md), notes dans
   [PLAYTEST_RESULTS.md](PLAYTEST_RESULTS.md) ; statistiques dans le Creator Hub 24–48 h après.

## 5. Fonctionnalités vérifiées sur l'infrastructure Roblox

| Fonctionnalité | Où | État |
|---|---|---|
| Création d'une expérience privée, réglages, publication | Studio ↔ Roblox | ✅ réel |
| DataStore : 11 scénarios (profil, sauvegarde, verrous, concurrence, migration, corruption, libération, écriture déjà appliquée) | vrai DataStore de l'expérience | ✅ réel |
| Jeu complet : démarrage, carte, profil chargé depuis le DataStore, sauvegarde au départ, rechargement identique | session Studio du lieu publié, vrai DataStore | ✅ réel (serveur local de Studio) |
| Jeu sur un serveur publié, plusieurs vrais comptes, appareils réels, statistiques | serveurs Roblox | ⛔ 🧑 |

## 6. Verdict

| Question | Verdict | Pourquoi |
|---|---|---|
| Prêt pour un playtest privé | ✅ **Oui**, dès que tu as réglé les 8 joueurs et fait le test M1–M4 | le vrai DataStore se comporte comme prévu sur 11 scénarios ; le jeu publié charge et sauvegarde sur le DataStore de l'expérience privée ; aucun problème critique connu |
| Bloqué par un problème critique | ❌ Non | aucun P0/P1 constaté |
| Prêt pour la V0.4 | ⏸️ **Pas encore** | il manque toujours l'essentiel de cette phase : de vrais joueurs, de vrais appareils, un vrai serveur publié. Décision après la première séance (PLAYTEST_RESULTS.md § 9) |
| Publication publique | ❌ Non prêt | mêmes raisons ; jamais fait sans ton accord |
