# MIMIC HUNTERS — V0.3.1 (validation, optimisation, équilibrage)

Jeu Roblox multijoueur de chasse et de collection : des créatures, les **Mimics**, se
déguisent en objets ordinaires. Le joueur les repère grâce à des indices, les examine,
puis les stabilise avec un court minijeu pour les capturer.

**Chercher → Détecter → Capturer → Découvrir → Collectionner.**

V0.3.1 (branche `feature/v0.3.1-validation`) : version de qualité, sans nouveau contenu —
audit technique, sauvegardes fiabilisées (accès concurrents, fermeture, données illisibles),
tests multijoueurs à deux clients, optimisations mesurées, Museum Hunt rééquilibrée, guide de
première session, mesures de playtest. Bilan : [docs/V031_VALIDATION.md](docs/V031_VALIDATION.md).

Nouveautés de la V0.3 (branche `feature/v0.3-museums`) :
- **musée personnel** pour chaque joueur, dans le Quartier des collectionneurs (bouton MA BASE) ;
- **6 vitrines** pour exposer ses vrais exemplaires, mutations comprises, animés et examinables ;
- **personnalisation** (murs, lumière, socles, thème) et **visites** des musées des autres joueurs ;
- **Museum Hunt** : une chasse de 75 s aux copies de Mimics cachées dans le jardin d'un musée.

Nouveautés de la V0.2 :
- **collection persistante** (DataStore, verrou de session, sauvegarde après chaque capture) ;
- chaque capture est un **exemplaire individuel** (identifiant, rareté, apparence unique, date, favori) ;
- deux **mutations** cosmétiques rares : Chromatic (4 %) et Spectral (1,5 %) ;
- panneau **Collection** : Codex, Inventaire filtrable avec fiche 3D, Objectifs ;
- **objectifs du collectionneur** avec titres et couleurs de scanner garantis.

Projet indépendant, créé de zéro (aucun code ni asset repris d'un autre projet).
Rien n'est publié : la place se construit et se teste en local.

## Prérequis

| Outil | Version | Rôle |
|---|---|---|
| [Roblox Studio](https://create.roblox.com/) | récente | Tester la place |
| [Rokit](https://github.com/rojo-rbx/rokit) | 1.2+ | Installe les outils ci-dessous |
| Rojo | 7.7.1 | Construit la place depuis `src/` |
| Lune | 0.11.1 | Exécute les tests de logique pure hors Roblox |
| Selene | 0.27.1 | Lint |
| StyLua | 0.20.0 | Formatage |
| Git | 2.4x | Versionnement |

Installation des outils (depuis la racine du projet) :

```bash
rokit install
```

Si Rokit est absent : téléchargez-le depuis https://github.com/rojo-rbx/rokit/releases,
puis relancez `rokit install`. Les versions sont épinglées dans `rokit.toml`.

## Construire et lancer

```bash
rojo build default.project.json -o build/MimicHunters.rbxl
```

Ouvrez ensuite `build/MimicHunters.rbxl` dans Roblox Studio et appuyez sur **Play (F5)**.
La carte n'existe pas en mode édition : elle est **générée par script au démarrage du serveur**
(environ 8 ms). La console affiche `[MimicHunters] v0.1.0 prêt : 41 objets…`.

Pour tester à plusieurs : Studio → onglet *Test* → *Clients et serveurs* → 2 joueurs.

Synchronisation en direct (facultatif) : `rojo serve`, puis *Connect* dans le plugin Rojo.
Le plugin doit correspondre à Rojo 7.7.x : un plugin plus ancien affiche « Can't parse JSON ».
Dans ce cas, mettez-le à jour avec `rojo plugin install`.

## Tests et qualité

**Commande unique** (Windows), sans prendre la main sur le bureau. Studio tourne sur un bureau
Windows caché ; détails et limites dans [docs/TESTING.md](docs/TESTING.md) :

```bat
test.cmd               :: ligne de commande + 4 sessions Roblox Studio, 104 tests (≈ 4 min 20)
test.cmd -SkipStudio   :: ligne de commande seulement (≈ 2 s)
```

Rapport : `build/test-reports/latest.md`. Commandes individuelles :

```bash
lune run tests/run          # 298 tests unitaires et d'intégration (logique pure)
lune run tools/balance      # simulation d'équilibrage (Museum Hunt, mutations, Codex)
lune run tests/run capture  # seulement les fichiers dont le nom contient « capture »
lune run tests/check        # compile tous les fichiers .luau (vérification de syntaxe)
selene src                  # lint (std Roblox)
stylua --check src tests    # formatage
```

Les tests chargent les **vrais modules** du jeu grâce à `tests/lib/Loader.luau`, qui simule
`script`, `require` et `game:GetService("ReplicatedStorage")`. Toute la logique serveur
(états, rencontres, capture, récompenses, anti-spam, concurrence) est testée sans Studio.

Non couvert par l'outillage actuel : la **vérification des types `--!strict`**. Pour l'ajouter,
installez [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp) (`rokit add JohnnyMorganz/luau-lsp`)
et lancez `luau-lsp analyze` avec les définitions Roblox et un `sourcemap.json`
(`rojo sourcemap -o sourcemap.json`).

## Commandes de jeu

| Action | PC | Mobile | Manette |
|---|---|---|---|
| Scanner | `E` | bouton SCAN | X |
| Examiner / Capturer | `F` ou clic sur l'objet | toucher l'objet ou bouton | Y |
| Impulsion (minijeu) | `Espace` ou clic | bouton IMPULSION | A |
| Collection (codex, inventaire, objectifs, musée, visites) | `C` | bouton CODEX | Select |
| Mon musée (sur place : mode décoration) | `B` | bouton MA BASE | — |
| Retour au Village | `V` | bouton VILLAGE | — |
| Examiner une vitrine / lancer la Museum Hunt | `G` / `E` (invites) | toucher l'invite | — |

## Arborescence

```
src/
  shared/              → ReplicatedStorage.Shared (client + serveur)
    Config/            GameConfig, MimicCatalog, Rarities, Mutations, Objectives,
                       MuseumStyles, Sounds
    Logic/             CaptureMinigame, CollectionQuery, HudLayout, SpecimenLook,
                       Rng, WeightedPicker, Validation (pur)
    Builders/          Geometry, PropBuilder, MimicModelBuilder (Parts uniquement)
    Net/Remotes        noms et création des RemoteEvents
  server/              → ServerScriptService.Server
    init.server.luau   point d'entrée
    Core/              logique serveur PURE et testée : HuntWorld, MimicStateMachine,
                       EncounterGenerator, CaptureLedger, RewardValidator, RateLimiter,
                       TutorialFlow, Collection, ProfileSchema, ProfileService,
                       MemoryBackend, MuseumCore, PlotRegistry
    Map/               MapLayout, MapBuilder, MuseumLayout, MuseumBuilder, LightingSetup
    Services/          HuntServer (adaptateur Roblox), MuseumServer, DataStoreBackend
  client/              → StarterPlayerScripts.Client
    Controllers/       PropTracker, MimicVisuals, ScannerController, CaptureController,
                       CollectionController, TutorialController, TitleController,
                       MuseumController, HuntController
    UI/                Theme, Hud, CollectionPanel, ModelView, ObjectivesTab,
                       MuseumTab, VisitsTab (interface construite en code)
    Util/              Signal, Animate, Audio, MutationFx
tests/                 Lune : run.luau, check.luau, lib/, specs/ ; Studio : tests/studio/
tools/                 test-all, studio-tests, luau-analyze, VM (vm-*.ps1)
docs/                  GAME_DESIGN, ARCHITECTURE, DATA_SCHEMA, TESTING, ROADMAP,
                       V01/V02/V03(/V031)_VALIDATION, PLAYTEST_PLAN, screenshots/
```

## Documentation

- [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) — boucle de jeu, espèces, détection, capture, première expérience
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — choix techniques, flux réseau, sécurité
- [docs/ROADMAP.md](docs/ROADMAP.md) — jalons et suite
- [docs/V01_VALIDATION.md](docs/V01_VALIDATION.md) — ce qui est implémenté, testé, et les limites
- [docs/V02_VALIDATION.md](docs/V02_VALIDATION.md) — bilan de la V0.2 (sauvegardes, collection, mutations, objectifs)
- [docs/DATA_SCHEMA.md](docs/DATA_SCHEMA.md) — schéma du profil, migrations, sauvegarde et verrou de session
- [docs/V03_VALIDATION.md](docs/V03_VALIDATION.md) — bilan de la V0.3 (musées, visites, Museum Hunt)
- [docs/V031_AUDIT.md](docs/V031_AUDIT.md) — audit technique V0.3.1 (persistance, sécurité, performances, types)
- [docs/V031_VALIDATION.md](docs/V031_VALIDATION.md) — bilan de la V0.3.1 et verdict
- [docs/BALANCE.md](docs/BALANCE.md) — analyse d'équilibrage (simulations)
- [docs/PLAYTEST_PLAN.md](docs/PLAYTEST_PLAN.md) — protocole de test avec 3 à 5 joueurs
- [docs/PRIVATE_TEST_PUBLISH.md](docs/PRIVATE_TEST_PUBLISH.md) — préparer une publication privée (rien n'est publié)
- [docs/TESTING.md](docs/TESTING.md) — tests automatisés Studio sans monopoliser le PC
- [docs/VM_SETUP.md](docs/VM_SETUP.md) — VM VMware pour les tests graphiques (`test-vm.cmd`)

## Outils de débogage (Studio uniquement)

En Studio, le serveur journalise chaque impulsion acceptée et chaque capture.
Il expose aussi le monde dans la barre de commande (contexte *Serveur*) :

```lua
local w = _G.MimicHuntWorld
for _, m in w:sharedMimics() do print(m.id, m.speciesId, m.slotId, m.state) end
```

Autres outils Studio : `_G.MimicProfiles` (service de profils et stockage utilisé) et l'attribut
`MH_ForceMutation` de Workspace (`"Chromatic"` ou `"Spectral"`) qui impose la mutation des
captures suivantes, pour les tests visuels.

Ces accès sont désactivés hors Studio (`RunService:IsStudio()`).
