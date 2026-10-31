# MIMIC HUNTERS — Validation de la V0.2

Branche `feature/v0.2-collection` (partie de `main` 4145e86). `main` n'a pas été modifiée.
Rien n'a été publié sur Roblox, aucun produit Robux n'existe.

Légende : ✅ vérifié par un test exécuté · 👁️ vérifié visuellement sur captures d'écran réelles
(VM) · ⚠️ partiel · ❌ non vérifié.

## 1. Résultats des outils (31/10/2026)

| Commande | Résultat |
|---|---|
| `lune run tests/run` | **223 réussis, 0 échoué** (V0.1 : 158) |
| `selene src`, `selene` (tests, suites Studio) | 0 erreur, 0 avertissement |
| `stylua --check src tests` | conforme |
| `rojo build` | place construite |
| `test.cmd` (Studio sur bureau caché, 4 sessions) | **60 réussis, 0 échoué, 0 ignoré**, ≈ 2 min 10 |
| `test-vm.cmd` (Studio visible dans la VM VMware) | **60 réussis, 0 échoué** sur le commit 5afd80e, 49 à 55 captures d'écran par exécution |

Nouveaux tests Lune : schéma et migrations (8), collection (11), service de sauvegarde (14),
persistance de bout en bout (8), apparence des exemplaires (4), mutations (11), filtres et
tris (7), objectifs (8), disposition du HUD et du panneau (35, dont le panneau Collection).

## 2. Par jalon

### Jalon 1 — Sauvegardes persistantes

| Exigence | État | Preuve |
|---|---|---|
| `DataStoreService` + `UpdateAsync` | ⚠️ code écrit, **jamais exécuté sur un vrai DataStore** | la place n'est pas publiée : Studio bascule sur le stockage mémoire (vu dans le journal : « profils : mémoire (Studio) ») |
| Erreurs, réessais, limites | ✅ | pannes injectées (3 erreurs → succès après 1+2+4 s ; panne durable → « Unavailable » sans écriture) ; budget nul → attente puis envoi ; sauvegarde échouée gardée et refaite |
| Sessions sûres (pas d'écritures concurrentes) | ✅ | deux « serveurs » sur le même stockage : le second est bloqué tant que le premier tient la session ; verrou périmé repris ; l'ancien serveur ne peut plus écrire (« Lost ») |
| Captures, codex, favoris, paramètres, progression sauvegardés | ✅ | reconnexion sur un autre serveur : exemplaires, mutations, graines, favori, tutoriel, réglages identiques |
| Migration par version de schéma | ✅ | profil V0.1 → v2 ; version future refusée et **jamais écrasée** |
| Sauvegarde périodique / après capture / départ / fermeture | ✅ (logique) · ⚠️ `BindToClose` réel non observé | planification testée (7 s après une capture, 60 s sinon) ; `closeAll` testé dans Lune |
| Ni perte ni duplication de Mimics | ✅ | clé de capture persistante ; identifiants uniques sur 3 sessions ; même événement jamais accordé deux fois, y compris après rechargement |
| Pas d'acquisition sans profil sûr | ✅ | profil indisponible, verrouillé, futur ou corrompu → capture refusée (`ProfileUnavailable`), rien n'est écrit ; rattachement quand le stockage revient |
| Stockage simulé pour les tests | ✅ | `MemoryBackend` (Lune et Studio) |
| DataStore distinct pour Studio | ⚠️ | `MimicHunters_Profiles_v2_STUDIO` en Studio, `..._v2` en jeu publié : choix vérifié dans le code, pas sur un vrai DataStore |
| Cycle complet dans un vrai serveur Studio | ✅ | `sauvegarde.cycle_studio` : chargement, ajout, sauvegarde, départ, reconnexion, refus du doublon |

### Jalon 2 — Exemplaires individuels

| Exigence | État |
|---|---|
| Identifiant serveur unique (`S<userId>-<n>`), espèce, rareté figée, mutation, graine, date, favori | ✅ |
| Plusieurs exemplaires d'une espèce | ✅ · 👁️ (deux Chairy, Spectral et Commun, dans l'inventaire mobile) |
| Variation d'apparence reproductible | ✅ (même graine = même apparence ; 30+ apparences distinctes sur 40 graines) · 👁️ (tailles 99 %, 101 %, 106 % affichées) |
| Modèle prêt pour musée, échanges, mutations avancées, comparaison | conçu (DATA_SCHEMA.md), **non développé** comme demandé |

### Jalon 3 — Mutations

| Exigence | État |
|---|---|
| Chromatic (palette irisée, éclat) et Spectral (translucide, yeux lumineux, lueurs) | ✅ (modèles des 6 espèces construits dans Studio) · 👁️ |
| Tirage exclusivement serveur, à la capture réussie | ✅ (Lune + capture réelle forcée côté serveur + capture rare par le réseau, PC et mobile) |
| Probabilités centralisées et affichées | ✅ `Config/Mutations` : 94,5 / 4 / 1,5 % ; distribution conforme sur 200 000 tirages ; affichées dans le Codex, la fiche et la carte de capture 👁️ |
| Purement cosmétique | ✅ aucune donnée de gameplay ne lit la mutation |
| Modèles procéduraux existants, pas de nouveaux personnages | ✅ |
| Révélation satisfaisante et courte | 👁️ carte « CHROMATIC ! » / « SPECTRAL ! » ; éclair + anneau ≈ 0,8 s en plus · ❌ ressenti non jugé par un joueur |

### Jalon 4 — Codex et inventaire

Codex (découvertes et silhouettes, indices, pastilles des mutations), inventaire par pages, filtres
rareté / espèce / mutation / favoris, tri récents / rareté, fiche avec aperçu 3D animé, favoris,
compteur de complétion : ✅ testés dans Studio sur PC (fenêtre 1187×517) et en **simulation**
iPhone 13 (HUD 749×330), 👁️ sur les captures. Deux défauts trouvés grâce aux captures, puis
corrigés : pages de 100×100 px (codex et objectifs vides) et pastilles dans le désordre.
Le test de visibilité réelle des pages a été vérifié en réintroduisant le défaut : il échoue.

### Jalon 5 — Objectifs du collectionneur

6 objectifs, récompenses garanties (3 titres, 3 couleurs de scanner + Cyan par défaut),
validation serveur, rattrapage des anciens profils, équipement refusé si verrouillé, titre
affiché au-dessus du personnage : ✅ (Lune + Studio PC et mobile) · 👁️ onglet Objectifs.

### Jalon 6 — Ressenti

| Point | État |
|---|---|
| Sons du scanner (un bip par barre) | ⚠️ code et rythme écrits ; **sons non écoutés** (tests en sourdine) |
| Capture plus satisfaisante, effets par rareté | 👁️ en partie (images fixes toutes les 2 s : l'animation n'est pas jugée en mouvement) |
| Mise en valeur des nouveautés | 👁️ pastille « ! » sur CODEX, carte « NOUVELLE ESPÈCE » |
| Interface propre sur téléphone | ✅ géométrie (simulation) · 👁️ · ❌ vrai téléphone |
| Transitions rapides | ouverture du panneau 0,15 s (code) |
| Performances | ❌ non mesurées (MicroProfiler, appareils réels) |

## 3. Captures d'écran réelles (VM VMware, Studio)

| Fichier | Contenu |
|---|---|
| [01](screenshots/v02/01_revelation_chromatic_pc.jpg) | carte de capture « CHROMATIC ! » (PC) |
| [02](screenshots/v02/02_revelation_spectral_mobile.jpg) | « SPECTRAL ! » en iPhone 13 simulé, lueurs visibles |
| [03](screenshots/v02/03_codex_pc.jpg) | Codex : espèce découverte, silhouette « ??? », probabilités |
| [04](screenshots/v02/04_inventaire_fiche_pc.jpg) | fiche d'un exemplaire (date, numéro, taille, favori) |
| [05](screenshots/v02/05_inventaire_mobile_deux_exemplaires.jpg) | inventaire mobile : deux Chairy distincts |
| [06](screenshots/v02/06_objectifs_pc.jpg) | onglet Objectifs : validé, 2/3, 2/10 |
| [07](screenshots/v02/07_carte_chromatic_mobile_pastille.jpg) | carte Chromatic mobile et pastille « ! » |

La VM affiche Studio en 1024×768 : la vue de jeu est petite et le téléphone simulé y est coupé à
droite (Studio réduit son cadre) ; ce n'est pas l'écran réel du jeu.

## 4. Non réalisable ici (honnêtement)

| Point | Pourquoi | Ce qu'il faudrait |
|---|---|---|
| Vrai DataStore, deux vrais serveurs, `BindToClose` en production | exige une place publiée et l'accès API (interdit sans ton accord) | publication privée de test |
| Vrai téléphone, performances | Studio simule seulement l'écran et le tactile | appareil réel + MicroProfiler |
| Sons | tests en sourdine, aucune écoute automatisée | écoute humaine |
| Plaisir de collectionner | demande de vrais joueurs | session de test |
| Vérification des types `--!strict` | luau-lsp non installé | `luau-lsp analyze` |

## 5. Constat sur l'outillage de test

Le bureau Windows caché n'isole **pas** le clavier et la souris : pendant que le PC était utilisé,
des captures, impulsions et déplacements non demandés par le test ont atteint Studio (requêtes
visibles dans le journal horodaté). La suite client neutralise désormais ces entrées (bouclier) ;
les 3 exécutions suivantes étaient propres (seules les requêtes du test). La VM n'a pas ce
problème. Détails : [TESTING.md](TESTING.md).
