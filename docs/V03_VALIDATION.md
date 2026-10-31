# MIMIC HUNTERS — Validation de la V0.3

Branche `feature/v0.3-museums` (partie de `feature/v0.2-collection` ce7b205). Ni `main` ni la
branche V0.2 n'ont été modifiées. Rien n'a été publié sur Roblox, aucun produit Robux n'existe,
aucun achat n'est implémenté.

Légende : **codé** = écrit, relu · ✅ = vérifié par un test exécuté · 👁️ = vérifié visuellement
sur une capture d'écran réelle (Studio dans la VM VMware) · 🧑 = demande une validation humaine ·
⚠️ = partiel · ❌ = non vérifié.

## 1. Résultats des outils (31/10/2026)

| Commande | Résultat |
|---|---|
| `lune run tests/run` | **269 réussis, 0 échoué** (V0.2 : 223) |
| `selene src`, suites Studio | 0 erreur, 0 avertissement |
| `stylua --check src tests` | conforme |
| `test.cmd` (Studio sur bureau caché, 4 sessions) | **84 réussis, 0 échoué, 0 ignoré**, ≈ 3 min 40 (V0.2 : 60) ; aucune fenêtre sur le bureau, premier plan jamais pris (avant le dernier ajout : hauteur minimale du HUD, vérifiée ensuite dans la VM) |
| `test-vm.cmd` (Studio visible dans la VM) | **84 réussis, 0 échoué, 0 ignoré** (exécution 20261031-105054, code final, 80 captures) ; client PC + mobile seuls : 56/56 (20261031-103607, captures de la section 3) |

Nouveaux tests Lune : disposition du quartier (8), musées : parcelles, vitrines, styles, visites,
protections (17), Museum Hunt (14), migration v2 → v3 et réparation du profil, persistance des
musées (4), disposition des boutons MA BASE / VILLAGE sur 9 tailles d'écran.

Nouveaux contrôles Studio : 6 côté serveur (quartier, rendu des 6 Mimics et des mutations,
refus et retrait, sauvegarde et reconnexion, objets de chasse, libération de parcelle) et
9 côté client, joués sur PC **et** en téléphone simulé (MA BASE, exposer et examiner, onglet
Vitrines et sélecteur, personnalisation, visite, panneau Visites et protections, Museum Hunt
complète par le réseau, budget de performance, retour au village).

## 2. Par jalon

### Jalon 1 — Bases personnelles

| Exigence | État |
|---|---|
| Quartier des collectionneurs, 8 parcelles fixes, attribuées par le serveur | ✅ Lune + Studio · 👁️ |
| Parcelle libérée au départ, rendue au premier joueur en attente | ✅ (Lune, Studio `musee.liberation_parcelle`) |
| Plus de parcelles libres : le jeu continue, file d'attente, message | ✅ Lune (9e joueur) · ❌ jamais vu à 9 vrais joueurs |
| Musée reconstruit depuis le profil à chaque connexion (parcelles non persistées) | ✅ |
| Entrée avec le nom du propriétaire, salle, 6 vitrines, éclairage, panneau de statistiques, emplacement d'amélioration, zone de défi | codé · ✅ (présence des éléments) · 👁️ |
| Boutons MA BASE (B) et VILLAGE (V), destination choisie par le serveur | ✅ (PC et mobile simulé) · 👁️ |

### Jalon 2 — Exposer ses Mimics

| Exigence | État |
|---|---|
| Choisir une vitrine, sélectionner, remplacer, retirer, réorganiser (échange) | ✅ Lune + réseau Studio |
| Vitrines occupées visibles, exemplaires déjà exposés marqués dans le sélecteur | ✅ · 👁️ |
| Un exemplaire jamais dans deux vitrines ; exemplaire d'un autre refusé | ✅ (`AlreadyExhibited`, `NotOwned`, aussi après réparation du profil) |
| Exposer ne crée ni ne déplace aucun Mimic | ✅ (nombre d'exemplaires et `totalCaptures` inchangés) |
| Rendu exact (`MimicModelBuilder` + `SpecimenLook`), mutations conservées | ✅ (attributs espèce, graine, mutation, taille des modèles) · 👁️ Chromatic et Spectral |
| Animations légères : respiration, clignement, déplacement occasionnel, réaction à l'approche, effet de mutation rare | codé · ✅ (plafond et distance) · 👁️ images fixes seulement · 🧑 ressenti en mouvement |
| Fiche d'inspection (nom, rareté, mutation, taille, numéro, collectionneur), utilisable sur mobile | ✅ (PC et mobile simulé) · 👁️ |

### Jalon 3 — Sauvegarde des musées

| Exigence | État |
|---|---|
| Schéma v3, migration v2 → v3 sans perte de Mimics | ✅ (exemplaires, codex, objectifs, cosmétiques, réglages comparés avant/après) |
| Vérification de propriété et des doublons, références invalides ignorées | ✅ (`sanitize` vide la vitrine, l'exemplaire reste dans la collection) |
| Pas de modifications concurrentes | ✅ verrou de session (Lune, deux « serveurs » simulés) |
| Seuls les identifiants sont stockés | ✅ |
| Reconnexion : vitrines et styles identiques | ✅ Lune + Studio `musee.sauvegarde_reconnexion_studio` (stockage mémoire) |
| **Vrai DataStore, deux vrais serveurs** | ❌ **non validé** : la place n'est pas publiée, Studio utilise le stockage mémoire. Aucune persistance réelle inter-serveurs n'est revendiquée. |

### Jalon 4 — Personnalisation

3 couleurs de murs et sols, 3 ambiances lumineuses, 3 styles de socle plus le socle Étoilé
(récompense de l'objectif « Première vitrine »), 3 thèmes ; gratuit, refusé si verrouillé,
sauvegardé, visible des visiteurs (attribut `Styles` lu par le client du visiteur) :
✅ Lune + Studio · 👁️. Style inconnu dans un profil : rendu par défaut, valeur gardée ✅.

### Jalon 5 — Visites

| Exigence | État |
|---|---|
| Liste : nom, espèces découvertes, Mimics exposés, mutations exposées, bouton Visiter | ✅ · 👁️ |
| Se déplacer, examiner, voir le panneau, revenir | ✅ (réseau Studio, PC et mobile simulé) · 👁️ |
| Un visiteur ne modifie jamais rien | ✅ par construction (aucune requête ne prend de propriétaire cible) et par test (requêtes forgées sans effet sur le musée visité) |

Limite : dans Studio, les « autres joueurs » sont des profils simulés côté serveur (collectionneur
−5005), pas un second client réel. 🧑 visite entre deux vrais comptes.

### Jalon 6 — Museum Hunt

| Exigence | État |
|---|---|
| Défi de 75 s (dans la plage 60–90 s), 3 copies tirées des Mimics du propriétaire, leurres | ✅ Lune + partie complète par le réseau dans Studio · 👁️ |
| Score, record personnel, musées différents, cosmétique garanti (titre « Explorateur » à 3 musées) | ✅ |
| Copies choisies par le serveur ; le client ne reçoit jamais « copie ou leurre » avant de trouver | ✅ (contenu de `_HuntSpawn` testé) |
| Contrôles de distance (lancement 12, examen 11, zone 26 studs) | ✅ |
| Aucun résultat fabriqué par le client, cachettes inventées ou déjà trouvées refusées | ✅ |
| Pas de sessions simultanées, délai de 20 s entre deux défis, anti-spam | ✅ |
| Pas de farm par entente : récompense une fois par musée différent | ✅ (Lune) |
| Annulation si le propriétaire part, si le visiteur part ou quitte la zone | ✅ (Lune + Studio) |
| Plaisir du défi, difficulté | 🧑 |

### Jalon 7 — Interfaces

HUD, onglets Musée et Visites, sélecteur, fiche, barre de défi et carte de résultat :
géométrie testée sur 9 tailles (PC 1920×1080 à téléphone 640×302), sans chevauchement ✅ ;
parcours complets en mobile simulé dans Studio ✅ · 👁️. Deux défauts trouvés et corrigés grâce
aux tests et captures : vitrines coupées en bas de l'onglet Musée, mini-jeu de capture sous
MA BASE en 640×302. ❌ vrai téléphone et vraie tablette.

Hauteur minimale prise en charge : **300 px** de vue de jeu (`HudLayout.MinHeight`, un téléphone
en paysage en fait ≈ 300). Une exécution dans la VM a donné au client PC une vue de 667×232 :
le signal du scanner sortait alors par le haut. En dessous de 300 px, HUD et minijeu ne tiennent
plus ensemble ; le contrôle Studio se déclare alors **ignoré** (avec la taille mesurée) au lieu
de réussir, et un test Lune fige cette limite. Pas de disposition spéciale pour ces vues.

### Jalon 8 — Performance

| Élément | Budget | Mesuré (Studio) |
|---|---|---|
| Parts par musée, Mimics compris | ≤ 450 | 168 |
| Parts du quartier (2 musées meublés) | — | 521 |
| Lumières du quartier | ≤ 30 | 24 |
| Mimics animés | 12 PC / 6 tactile | 7 PC (tous ceux à portée) / 6 mobile simulé |
| Temps d'image | — | 16,6 ms dans les deux vues |

⚠️ **Indicatif seulement** : 16,6 ms est le plafond de la synchronisation verticale ; mesuré
sur le bureau caché et dans la VM (GPU virtuel), jamais sur un téléphone. La simulation mobile de
Studio n'est pas une mesure de performance sur téléphone réel.

## 3. Captures d'écran réelles (VM VMware, Studio 1920×1080)

Exécution `test-vm.cmd` 20261031-103607 (sessions client PC et mobile, 56/56 réussis). Le
« collectionneur 5005 » est un profil simulé côté serveur (6 Mimics, un Chromatic en vitrine 2,
un Spectral en vitrine 3) ; le joueur est le compte de test de Studio.

| Fichier | Contenu |
|---|---|
| [01](screenshots/v03/01_musee_vide_pc.jpg) | **musée vide** du joueur : 6 vitrines, panneau de statistiques, nom à l'entrée |
| [02](screenshots/v03/02_onglet_musee_pc.jpg) | onglet Musée : vitrine 1 occupée (Choisir / Retirer / déplacer), 5 libres |
| [03](screenshots/v03/03_selecteur_pc.jpg) | **sélecteur** pour la vitrine 2 : l'exemplaire déjà exposé est marqué « Exposé (vitrine 1) » |
| [04](screenshots/v03/04_fiche_inspection_pc.jpg) | fiche d'inspection d'un Mimic exposé (rareté, apparence, taille, numéro, collection) |
| [05](screenshots/v03/05_six_mimics_exposes_pc.jpg) | **six Mimics exposés** chez le collectionneur, panneau « Exposés 6/6 · Mutations exposées 3 » |
| [06](screenshots/v03/06_vitrine_chromatic_pc.jpg) | **Mimic Chromatic en vitrine** (Lumino, tête irisée) |
| [07](screenshots/v03/07_vitrine_spectral_pc.jpg) | **Mimic Spectral en vitrine** (Posty translucide, yeux lumineux) |
| [08](screenshots/v03/08_onglet_visites_pc.jpg) | onglet Visites : « Ton musée » et le musée du collectionneur avec ses statistiques |
| [09](screenshots/v03/09_visite_collectionneur_pc.jpg) | **visite** : arrivée devant le musée du collectionneur, invite « Lancer le défi » |
| [10](screenshots/v03/10_museum_hunt_signal_pc.jpg) | **Museum Hunt** : barre « 0/3 trouvés » avec le temps restant, signal du scanner |
| [11](screenshots/v03/11_museum_hunt_trouve_pc.jpg) | Museum Hunt : « Trouvé : Chairy ! », leurres « ordinaires » |
| [12](screenshots/v03/12_museum_hunt_resultat_pc.jpg) | carte de résultat : 346 points, 3/3, record personnel, musées différents |
| [13](screenshots/v03/13_onglet_musee_mobile.jpg) | onglet Musée en iPhone 13 **simulé** |
| [14](screenshots/v03/14_selecteur_mobile.jpg) | sélecteur en mobile simulé |
| [15](screenshots/v03/15_visites_mobile.jpg) | onglet Visites en mobile simulé |
| [16](screenshots/v03/16_museum_hunt_mobile.jpg) | Museum Hunt en mobile simulé : barre, signal, invite tactile |
| [17](screenshots/v03/17_museum_hunt_resultat_mobile.jpg) | résultat de la Museum Hunt en mobile simulé |

Les images sont recadrées sur la vue de jeu de Studio (fenêtre de la VM) ; le téléphone simulé
y est petit : ce n'est pas l'écran d'un vrai téléphone.

Toutes sont des captures de Studio prises par `test-vm.cmd` pendant les tests ; aucune image
n'a été retouchée ou générée.

## 4. À valider par un humain avant publication

| Point | Pourquoi | Ce qu'il faudrait |
|---|---|---|
| Vrai DataStore, reconnexion sur un autre serveur, `BindToClose` | exige une place publiée (interdit sans ton accord) | publication privée de test |
| Visites et Museum Hunt entre deux vrais comptes | Studio simule l'autre joueur côté serveur | test à 2+ joueurs |
| Vrai téléphone, vraie tablette, performances | Studio simule l'écran et le tactile seulement | appareils réels + MicroProfiler |
| Animations et effets en mouvement | captures fixes toutes les 2 s | regarder le jeu |
| Sons | tests en sourdine | écoute |
| 9 joueurs ou plus (file d'attente) | testé dans Lune seulement | serveur rempli |

## 5. Risques et limites

- **DataStore réel non validé** (inchangé depuis la V0.2) : toute la persistance a été testée
  avec les stockages simulés (Lune et mémoire de Studio).
- Le bureau caché n'isole pas le clavier et la souris de l'utilisateur ; le bouclier de la suite
  client neutralise ces entrées, la VM n'a pas ce problème (voir [TESTING.md](TESTING.md)).
- La suite client dure maintenant ≈ 95 s par session (PC et mobile) ; délais relevés en
  conséquence (`askClient` 180 s, suite 300 s, exécution 900 s).
- Défauts trouvés grâce aux captures de la VM, puis corrigés : le panneau de statistiques
  restait à 0 après une capture (corrigé, couvert par un test) ; une nouvelle version de Studio
  ouvrait une fenêtre « Migration vers Voxel Lighting » par-dessus le jeu (la place fixe
  désormais `Lighting.Technology = Voxel`, rendu le plus proche de l'ancien mode).
- Une exécution dans la VM a échoué parce que l'ordinateur s'est mis en veille pendant le test
  (5 h d'interruption, aucune session rendue) ; relancée à l'identique, elle a réussi.
- Types `--!strict` non vérifiés par `luau-lsp` (non installé).
