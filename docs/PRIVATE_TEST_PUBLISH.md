# MIMIC HUNTERS — Expérience privée de test (V0.3.2)

## 1. État (31/10/2026)

| Élément | Valeur | Vérifié |
|---|---|---|
| Nom | MIMIC HUNTERS — Private Test | ✅ Studio (paramètres d'expérience) |
| Propriétaire | `youyou31110` (ID 941826283) | ✅ `StudioService:GetUserId()` avant publication |
| Univers / lieu de départ | `10773995454` / `91525576925499` | ✅ `game.GameId`, `game.PlaceId` |
| Lien | https://www.roblox.com/games/91525576925499 (visible seulement du propriétaire et des testeurs invités) | ✅ un visiteur non connecté voit une page vide « Title Unavailable » ; l'API publique ne renvoie rien |
| Audience | **privée** : « Disponible uniquement pour vous et vos collaborateurs » | ✅ fenêtre Gérer l'audience, après chaque publication |
| Accès de Studio aux services API | activé (cette expérience seulement) | ✅ |
| Requêtes HTTP, ventes et téléports tiers | désactivés | ✅ |
| Création en équipe, partage de données (IA) | désactivés | ✅ |
| Produits Robux, monétisation | aucun | ✅ |
| Version jouable publiée | `default.project.json` (sans contrôle DataStore) | ✅ « INSTALLÉ … contrôle DataStore : false » puis « Nouveaux changements publiés » |
| Joueurs max par serveur | **pas encore réglé** (12 par défaut) | ⏳ à faire par toi (§ 3.1) |

Expérience existante « youyou31110's Place » : jamais touchée.

## 2. Mettre à jour le jeu sur l'expérience privée

« Publier sous → Écrire par dessus » restait bloqué dans Studio (« Importation en cours… » plus
de 3 minutes, deux essais). Méthode qui fonctionne (le jeu n'est que du code : la carte est
générée au démarrage) :

1. `rojo build deploy/import-game.project.json -o build/MimicImport-game.rbxm`
   (`deploy/import-check.project.json` pour la version avec le contrôle DataStore).
2. Studio : ouvrir le lieu depuis Roblox (`RobloxStudioBeta.exe -task EditPlace -placeId 91525576925499 -universeId 10773995454`).
3. Explorer → clic droit sur Workspace → Insérer → **Importer le modèle Roblox** → le fichier `.rbxm`.
4. Barre de commande : coller `deploy/install.luau` (sur une ligne), Exécuter →
   « INSTALLÉ true true true ».
5. **Fichier → Publier** (Alt+P).

Dans la VM, ces étapes sont pilotées par la télécommande : `test-vm.cmd -Remote`, puis
`tools\vm-do.ps1` (actions dans la VM seulement, jamais sur ton bureau).

## 3. Ce qui demande ton intervention

### 3.1 Huit joueurs par serveur (2 min)

Creator Hub (connecté en `youyou31110`) → Créations → *MIMIC HUNTERS — Private Test* →
**Configurer → Lieux** → le lieu → réglage du **nombre maximal de joueurs** : **8** → Enregistrer.
(Studio n'expose pas ce réglage ; la VM n'est pas connectée à Roblox dans son navigateur et je
n'entre aucun mot de passe.)

### 3.2 Test sur un vrai serveur publié (10 min)

Avec le compte `youyou31110`, sur ton PC ou ton téléphone (ou dans la VM après t'être connecté
toi-même dans Edge) :

| # | Manipulation | Attendu |
|---|---|---|
| M1 | rejoindre le jeu, capturer 2–3 Mimics, en exposer, changer une couleur, quitter | — |
| M2 | rejoindre une nouvelle session | mêmes Mimics (numéros, mutations), mêmes vitrines et couleurs |
| M3 | Creator Hub → Serveurs → arrêter les serveurs pendant une partie, puis revenir | dernière capture conservée |
| M4 | console (F9) → onglet Serveur : chercher `profils : DataStore MimicHunters_Profiles_v2` | le jeu publié utilise le DataStore de cette expérience |

Note les résultats dans [PLAYTEST_RESULTS.md](PLAYTEST_RESULTS.md) § 5.

### 3.3 Inviter des testeurs (quand tu veux)

Voir [TESTER_GUIDE.md](TESTER_GUIDE.md) : **Fichier → Inviter des testeurs anticipés** (10 amis
Roblox au plus du compte propriétaire, accès joueur seulement). Ne jamais cliquer « Publier
publiquement ».

### 3.4 Statistiques

Creator Hub → l'expérience → **Analytics** (entonnoir d'intégration, événements personnalisés),
24 à 48 h après des parties sur un serveur publié. Studio n'envoie rien (voulu).

## 4. Contrôle du vrai DataStore

Résultats : [REAL_DATASTORE_VALIDATION.md](REAL_DATASTORE_VALIDATION.md) (11/11). Pour le relancer :
version `import-check`, mode « Exécuter » dans Studio, lire les lignes `[DataStoreCheck]`.
