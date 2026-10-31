# MIMIC HUNTERS — Validation de la V0.3.1

Branche `feature/v0.3.1-validation`, partie de `feature/v0.3-museums` (912f203, vérifiée
identique à `origin`). `main`, `feature/v0.2-collection` et `feature/v0.3-museums` n'ont pas
été modifiées. **Rien n'a été publié** sur Roblox, aucun réglage de compte ou d'expérience n'a été
touché, aucun compte n'a été créé ni utilisé, aucun produit Robux n'existe.

Légende : ✅ vérifié par un test exécuté · 👁️ vu sur une capture réelle (Studio dans la VM) ·
🧑 demande une validation humaine · ⛔ bloqué sans publication privée · ⚠️ partiel.

## 1. Résultats (31/10/2026)

| Contrôle | Résultat |
|---|---|
| Lune (logique pure) | **299 réussis, 0 échoué** (V0.3 : 269) |
| luau-lsp (types `--!strict`, nouveau) | **0 erreur** (45 au départ, toutes des faux positifs) |
| Selene, StyLua | 0 erreur, 0 avertissement ; formatage conforme |
| Studio, bureau caché, 4 sessions | **104 réussis, 0 échoué, 0 ignoré** (code final, ≈ 4 min 45 ; aucune fenêtre sur le bureau, premier plan jamais pris) |
| Studio dans la VM, 4 sessions | **104 réussis, 0 échoué, 0 ignoré** (exécution 20261031-120653, luau-lsp installé par Rokit dans la VM) |
| Contrôle du vrai DataStore | ⛔ préparé, **non exécuté** (exige une publication privée) |

Contrôles Studio : 84 en V0.3 → 104 (multijoueur à deux clients, mesures de performance,
guide, mesures de playtest ; certains contrôles sont joués sur PC et en mobile simulé).

## 2. Par jalon

### Jalon 1 — Audit technique

Rapport complet : [V031_AUDIT.md](V031_AUDIT.md). Aucun défaut critique. 10 constats de
persistance (jalon 2), 9 d'autorité serveur dont 1 élevé, 7 de performance. luau-lsp ajouté à
la chaîne (étape « Luau : analyse de types », bloquante). Documentation V0.1 obsolète corrigée.

Correctifs de sécurité (tous testés, Lune) : objets de la Museum Hunt envoyés triés (l'ordre
trahissait les copies — **élevé**) ; leurres du même type que les copies ; délai entre deux défis
après une sortie du jardin ; musée sans vitrine refusé (fuite d'exemplaires non exposés) ;
cosmétique équipé seulement dans son emplacement ; anti-spam avant tout refus ; seau séparé pour
la liste des musées ; déplacement refusé pendant une capture.

### Jalon 2 — Sauvegardes

| # | Scénario demandé | Simulé (Lune / Studio mémoire) | Vrai DataStore |
|---|---|---|---|
| 1 | Première connexion, profil vide | ✅ | ⛔ (script prêt) |
| 2 | Capture puis sauvegarde | ✅ | ⛔ (script prêt) |
| 3 | Déconnexion, reconnexion | ✅ Lune + Studio | ⛔ (script prêt) |
| 4 | Reconnexion sur un autre serveur | ✅ deux « serveurs » simulés | ⛔ (script : 2e service ; vrai 2e serveur : manuel) |
| 5 | Exemplaires identiques, mutations différentes | ✅ (aller-retour complet) | ⛔ (script prêt) |
| 6 | Favoris | ✅ | ⛔ (script prêt) |
| 7 | Six vitrines | ✅ (les 6 remplies) | ⛔ (script prêt) |
| 8 | Personnalisations (4 réglages) | ✅ | ⛔ (script prêt) |
| 9 | Objectifs et cosmétiques (+ stats de chasse) | ✅ | ⛔ (script prêt) |
| 10 | Migration V0.2 → V0.3 | ✅ | ⛔ (script prêt) |
| 11 | Erreur temporaire | ✅ pannes injectées | ⛔ non provocable sur demande |
| 12 | Échec prolongé | ✅ (+ nouveau statut `Degraded` : acquisitions suspendues) | ⛔ non provocable sur demande |
| 13 | Deux serveurs, même profil | ✅ | ⛔ (script prêt) |
| 14 | Fermeture inattendue (verrou laissé) | ✅ | ⛔ (script : verrou périmé ; vrai arrêt : manuel) |
| 15 | Perte ou expiration du verrou | ✅ | ⛔ (script prêt) |
| 16 | BindToClose | ✅ (échéance, chevauchement avec le départ) | ⛔ (script partiel ; vrai arrêt : manuel) |

Fiabilité attendue : pas de doublon sur requête répétée ✅ · pas d'écrasement par une ancienne
session ✅ · profil corrompu jamais chargé comme neuf ✅ (**corrigé**, P4) · pas d'effacement
silencieux ✅ (**corrigé** : quarantaine, P5) · identifiants conservés ✅ · aucune acquisition en
état non sûr ✅ (**étendu** : panne prolongée, P6) · messages compréhensibles ✅ (`Degraded`,
`SaveUnavailable`).

Tests de concurrence (`tests/lib/Scheduler`, ordonnanceur coopératif) : 12, dont **7 échouent
sur l'ancien code** (vérifié en échangeant temporairement les versions ; le test de fermeture
bornée a dû être renforcé pour échouer) — preuve qu'ils détectent bien les défauts corrigés.

Publication privée préparée, **non faite** : [PRIVATE_TEST_PUBLISH.md](PRIVATE_TEST_PUBLISH.md)
(expérience de test séparée, DataStore dédié, clés de test, aucune suppression ; script vérifié
sur un DataStore simulé, 9/9).

### Jalon 3 — Multijoueur

| Scénario | Automatisé | Vrais comptes |
|---|---|---|
| Deux joueurs, même serveur | ✅ 2 clients Studio | 🧑 playtest R1 |
| Parcelles différentes | ✅ (vues par chaque client) | 🧑 |
| Visites croisées | ✅ | 🧑 R2 |
| Mutations identiques pour tous | ✅ (attributs et Parts vus par les 2 clients) | 🧑 R3 |
| Vitrine modifiée pendant une visite | ✅ (vue par le visiteur) | 🧑 R4 |
| Visiteur ne modifie rien | ✅ (requêtes forgées) | — |
| Deux joueurs, même Mimic | ✅ (un seul lance la capture) | 🧑 R5 |
| Deux défis, même musée | ✅ (un seul, l'autre « occupé ») | 🧑 R6 |
| Propriétaire part pendant un défi | ✅ (visiteur prévenu) | 🧑 R7 |
| Visiteur part pendant un défi | ✅ Lune | — |
| Parcelle réattribuée proprement | ✅ (aucun reste du joueur parti) | — |
| Aucune fuite de collection | ✅ (identifiants reçus par chaque client) | — |

Les « deux clients » sont deux clients locaux de Studio (même machine, latence quasi nulle).
Aucun scénario n'exige deux vrais comptes pour la logique ; de vrais comptes sur un serveur
publié restent nécessaires pour la latence et la réplication réelles (protocole :
[PLAYTEST_PLAN.md](PLAYTEST_PLAN.md) § 7).

### Jalon 4 — Performance

| Mesure (comptage, Studio) | Avant | Après |
|---|---|---|
| Instances reconstruites par un changement de style de musée | 106 | **0** |
| Instances reconstruites par une vitrine changée | 115 | **31** |
| Instances créées à la réouverture du panneau Collection (2 Mimics) | 801 (PC) / 827 (mobile) | **21** |
| Requêtes envoyées par l'onglet Visites à l'ouverture | 10 | **1** |

Autres améliorations : éclats de mutation éteints à distance en « Effets réduits » (régression
corrigée) ; aperçu de la carte de capture vidé ; Mimics révélés animés à 30 Hz et à moins de
90 studs ; barre de défi 4 fois/s au lieu de chaque image. **Mode « Effets réduits » utile** :
plus de clignotement (7–16 Hz) ni de changement de couleur rapide, plus d'éclair de révélation,
exposés immobiles, pas de zoom d'ouverture.

Inchangé et toujours vrai : 168 Parts au plus par musée, 24 lumières dans le quartier, animations
plafonnées (12 PC, 6 tactile). ⚠️ Pas de mesure de temps CPU/GPU, de mémoire ni d'images par
seconde exploitable : la VM et le bureau caché plafonnent à la synchronisation verticale
(16,6 ms) et n'ont pas de vrai GPU. **Aucune mesure sur téléphone réel** : la simulation mobile
de Studio n'en tient pas lieu. 🧑 Mesures sur appareils physiques au playtest (MicroProfiler).

### Jalon 5 — Équilibrage

Analyse complète : [BALANCE.md](BALANCE.md) (simulation `lune run tools/balance`).
- **Museum Hunt** : tout défi finissait en 6–8 s et examiner au hasard valait presque la chasse
  (381 contre 434 points). Rééquilibrée (indices un par un, premier indice après 5–10 s, raté
  −40 points et 2,5 s) : scanner 429, indices 399, hasard ≈ 270 ; 10 à 25 s par défi.
- **Mutations** (inchangées) : au moins une mutation rare pour 68 à 90 % des joueurs en 20 min
  (1 à 2 captures/min, hypothèse) ; Spectral pour 26 à 45 % : rares sans être introuvables.
- **Codex** (inchangé) : médiane de 24 captures pour les 6 espèces.
- 🧑 Rythme réel de capture, frustration, plaisir : au playtest.

### Jalon 6 — Expérience

- Guide de première session (une consigne à la fois : collection → MA BASE → vitrine →
  visites) ✅ Studio · 👁️ captures 01–03, 09.
- Museum Hunt : règles en une phrase, raté expliqué ✅ · 👁️ captures 04–05, 10–11.
- Musée : refus jamais silencieux (« Ce Mimic est déjà exposé dans une autre vitrine ») 👁️ 03.
- Accord des noms d'objets (« un coffre », pas « une coffre ») ✅ Lune — **corrigé après les
  captures** : la capture 05 montre encore l'ancienne formulation.
- Aperçu vide en rouvrant un exemplaire sur téléphone : corrigé ✅ (code) · 🧑 à revoir sur
  téléphone.
- Aucun risque de perdre un Mimic en changeant de vitrine : une vitrine ne stocke qu'un
  identifiant, déplacer = échanger ✅ (tests V0.3).

Vérifications humaines (non automatisables, **non faites**) :

| # | À vérifier | Fait ? |
|---|---|---|
| H1 | Sons du scanner (un bip par barre), révélation, capture : audibles, pas agaçants | ☐ |
| H2 | Sons de la Museum Hunt (lancement, trouvaille, raté, fin) synchronisés avec l'écran | ☐ |
| H3 | Animations des exposés (respiration, clignement, réaction) naturelles en mouvement | ☐ |
| H4 | Révélation et capture : durée, lisibilité ; « Effets réduits » réellement confortable | ☐ |
| H5 | Guide : consignes comprises, pas envahissantes | ☐ |
| H6 | Téléphone et tablette réels : rien de coupé, boutons faciles à toucher | ☐ |

### Jalon 7 — Mesures de playtest

`Core/SessionMetrics` (pur) + `Services/AnalyticsServer` : entonnoir d'intégration (8 étapes) et
événements personnalisés (temps avant 1re capture, Codex, base, exposition, visite ; captures
réussies et ratées ; mutations ; Museum Hunts ; durée de session). API vérifiée dans la
documentation Roblox actuelle (`LogOnboardingFunnelStepEvent`, `LogCustomEvent` ; les méthodes
`Fire…` sont dépréciées). Aucune donnée personnelle ; indépendant des profils.

- ✅ Lune (4 tests, dont l'absence de toute donnée personnelle dans les appels).
- ✅ Studio : le parcours du client de test est suivi (7 étapes : premier scan → Museum Hunt
  réussie) et **rien n'est envoyé depuis Studio**.
- ⛔ Envoi réel à AnalyticsService et affichage dans le Creator Hub : non observés (exige la
  publication).

Plan de test avec 3 à 5 joueurs : [PLAYTEST_PLAN.md](PLAYTEST_PLAN.md) (20 minutes, grilles,
questionnaire, hiérarchisation). Aucune réponse de testeur n'a été inventée.

### Jalon 8 — Fiabilité et finition

Suite complète exécutée (§ 1) : Lune, Selene, StyLua, luau-lsp, 4 sessions Studio sur le bureau
caché et dans la VM (régressions V0.1, V0.2, V0.3 comprises : tutoriel, captures, mutations,
collection, sauvegarde, musées, visites, Museum Hunt, interfaces PC et mobile simulé,
multijoueur). Bugs trouvés et corrigés pendant ce jalon : article des noms d'objets ; deux tests
qui ne respectaient pas le nouveau délai après un raté.

## 3. Captures d'écran réelles (VM VMware, Studio maximisé)

Exécution `test-vm.cmd` 20261031-120653 (104/104). Images recadrées sur la vue de jeu ; le
téléphone est **simulé** par Studio.

| Fichier | Contenu |
|---|---|
| [01](screenshots/v031/01_guide_vers_ma_base_pc.jpg) | guide : « Expose tes Mimics dans ton musée personnel : appuie sur [B] » |
| [02](screenshots/v031/02_guide_dans_son_musee_pc.jpg) | guide dans son musée, onglet Musée ouvert |
| [03](screenshots/v031/03_refus_explique_et_guide_visites_pc.jpg) | refus expliqué (« déjà exposé ») et guide vers les visites |
| [04](screenshots/v031/04_museum_hunt_regles_pc.jpg) | Museum Hunt : règles au lancement |
| [05](screenshots/v031/05_museum_hunt_rate_explique_pc.jpg) | raté expliqué (−40 points) — montre encore « une coffre », corrigé depuis |
| [06](screenshots/v031/06_museum_hunt_resultat_pc.jpg) | résultat : 244 points, 3/3, 4 ratés (le test examine tout) |
| [07](screenshots/v031/07_vitrine_chromatic_pc.jpg) | vitrine Chromatic (régression V0.3) |
| [08](screenshots/v031/08_vitrine_spectral_pc.jpg) | vitrine Spectral (régression V0.3) |
| [09](screenshots/v031/09_guide_mobile.jpg) | guide en téléphone simulé |
| [10](screenshots/v031/10_museum_hunt_mobile.jpg) | Museum Hunt en téléphone simulé |
| [11](screenshots/v031/11_museum_hunt_rate_mobile.jpg) | raté expliqué en téléphone simulé |

Aucune image générée ou retouchée.

## 4. Limitations réelles

1. **Vrai DataStore non validé** : aucune expérience publiée ; toute la persistance est testée
   sur des stockages simulés. Le contrôle automatique est prêt mais pas exécuté.
2. **Aucun vrai joueur** : plaisir, compréhension, envie de revenir, frustration : inconnus.
3. **Aucun appareil physique** : performances et ergonomie mobile seulement simulées.
4. **Multijoueur** : deux clients locaux de Studio, pas deux vrais comptes sur un vrai serveur.
5. **Sons et animations** : jamais écoutés ni regardés en mouvement (captures fixes toutes les
   2 s).
6. **Analytics** : envoi réel jamais observé.
7. **Équilibrage** : simulations avec des bots parfaits et un rythme de capture supposé.
8. Le bureau caché n'isole pas le clavier et la souris de l'utilisateur (bouclier dans la suite
   client) ; la VM n'a pas ce problème.

## 5. Verdict

| Statut | Verdict | Justification |
|---|---|---|
| **Prêt pour playtest privé** | ✅ **Oui, après ta publication privée** | Aucun défaut critique connu ; les défauts de sauvegarde trouvés par l'audit sont corrigés et couverts par des tests qui échouaient avant ; 299 tests Lune et 104 contrôles Studio passent, dans la VM aussi ; le multijoueur est vérifié à deux clients ; le plan de playtest et les mesures sont prêts. Un playtest privé sur une expérience de test ne met en jeu que des profils de test. Étape préalable recommandée : exécuter le contrôle du vrai DataStore (§ 3 de PRIVATE_TEST_PUBLISH.md). |
| **Encore bloqué par des problèmes critiques** | ❌ **Non** | Aucun problème critique connu. Le seul point qui pourrait le devenir — le comportement du vrai DataStore — se vérifie précisément pendant cette phase privée. |
| **Prêt pour le développement V0.4** | ⏸️ **Pas encore** | Techniquement, la base est stable. Mais la V0.4 ajoute du contenu : il faut d'abord savoir, avec de vrais joueurs, si la boucle actuelle plaît (objectif annoncé de cette phase). Recommandation : playtest, corrections P1/P2, puis V0.4. |
| **Non prêt pour publication publique** | ✅ **Exact : non prêt** | Vrai DataStore non validé, aucun vrai joueur, aucun appareil réel, sons non écoutés, analytics non observées ; `MaxPlayers` du serveur à régler (8 parcelles). |

Des tests automatisés réussis ne valent pas une validation par de vrais joueurs : les cases 🧑
et ⛔ de ce rapport restent ouvertes tant que le playtest n'a pas eu lieu.
