# MIMIC HUNTERS — Tests automatisés sans monopoliser le PC

## En bref

```bat
test.cmd                      :: tout : ligne de commande + Roblox Studio (≈ 75 s)
test.cmd -SkipStudio          :: ligne de commande seulement (≈ 2 s)
test.cmd -Sessions server     :: une seule session Studio (server, client, mobile, multiplayer)
test.cmd -Visible             :: Studio sur ton bureau (diagnostic uniquement : il prend la main)
```

Rapport : `build/test-reports/<horodatage>/report.md` (+ `report.json`), copie dans
`build/test-reports/latest.md`. Code de sortie 0 si tout réussit.

Pendant `test.cmd`, Roblox Studio tourne sur un **bureau Windows secondaire invisible**.
Mesuré sur 10 exécutions consécutives :
- **0 fenêtre** Studio sur ton bureau ;
- **aucune prise du premier plan** ;
- aucune entrée clavier/souris simulée.

Tu peux continuer à travailler pendant les tests (voir §5 pour ce qui reste partagé : CPU, GPU, mémoire, son).

## 1. Prérequis et installation

| Élément | Version testée | Remarque |
|---|---|---|
| Windows | 11 Pro | PowerShell 5.1 intégré suffit |
| Roblox Studio | 0.745.0.7451137 | Installé et **connecté à un compte** (sinon Studio attend une connexion → délai dépassé) |
| Rokit + outils | rojo 7.7.1, lune 0.11.1, selene 0.27.1, stylua 0.20.0 | `rokit install` |

Rien d'autre à installer : le lanceur du bureau caché (`tools/HiddenDesktopRunner.cs`) est
compilé à la volée par PowerShell (`Add-Type`). `-ExecutionPolicy Bypass` ne s'applique qu'au
processus lancé par `test.cmd` : **aucun réglage Windows n'est modifié**.

Studio est trouvé automatiquement (version la plus récente dans
`%LOCALAPPDATA%\Roblox\Versions`). Pour en imposer un :
`powershell -File tools\studio-tests.ps1 -StudioExe "C:\…\RobloxStudioBeta.exe"`.

## 2. Audit : ce qui est testable, et comment

Sources : documentation officielle Roblox ([CLI Studio](https://create.roblox.com/docs/studio/command-line-interface),
[StudioTestService](https://create.roblox.com/docs/reference/engine/classes/StudioTestService),
[StudioDeviceSimulatorService](https://create.roblox.com/docs/reference/engine/classes/StudioDeviceSimulatorService),
[VirtualInputManager](https://create.roblox.com/docs/reference/engine/classes/VirtualInputManager)),
puis vérification sur **la version installée** avec `RobloxStudioBeta.exe --fullApi` (niveaux de sécurité réels).

| Catégorie | Outil / API | Disponible ? | Niveau de sécurité (dump API local) | Utilisé |
|---|---|---|---|---|
| 1. Ligne de commande | Lune, Selene, luau-lsp (types), StyLua, Rojo | ✅ | — | ✅ |
| 2. Studio scripté | `--task RunScript` + `--localPlaceFile` + `--runScriptFile` + `--outputFile` + `--quitAfterExecution` | ✅ | « permissions de la barre de commande » | ✅ |
| 3a. Sessions de test | `StudioTestService.ExecuteRunModeAsync` / `ExecutePlayModeAsync` / `ExecuteMultiplayerTestAsync` | ✅ depuis RunScript | PluginSecurity | ✅ |
| 3b. Fin / arguments / joueurs | `EndTest`, `GetTestArgs`, `AddPlayers`, `LeaveTest`, `CanLeaveTest` | ✅ | None (dans une session) | ✅ |
| 3c. Simulation d'appareil | `StudioDeviceSimulatorService` (SetDeviceAsync, résolution, orientation…) | ✅ depuis RunScript, en édition | PluginSecurity | ✅ |
| 3d. Entrées virtuelles | `VirtualInputManager` | ❌ | **RobloxScriptSecurity** (« service interne sans fonctionnalité pour les développeurs ») | ❌ |
| 3e. Entrées virtuelles (ancien) | `VirtualUser` | ⚠️ | LocalUserSecurity | ❌ inutile : les tests appellent directement les RemoteEvents |
| 4. Interface graphique visible | rendu, géométrie à l'écran, son, ergonomie, performance | — | — | manuel / session isolée |

### Constats expérimentaux (non documentés par Roblox, vérifiés ici)

1. **`--outputFile` doit avoir l'extension `.log`**. Avec `.txt`, Studio n'écrit rien et ne
   signale rien. Le message « Output file must have a .log extension » n'est visible que dans le binaire.
2. Le fichier de sortie contient : l'écho du script, ses `print` / `warn`, **et la sortie des
   serveurs et clients des sessions lancées** (ex. `[MimicHunters] v0.1.0 prêt…`).
3. Lancer une session dès le début du script peut échouer : elle se termine en ~1 s, sans
   résultat. Le pilote attend donc 4 s, puis **réessaie une fois** toute session revenue sans résultat.
4. Une erreur de syntaxe dans le script RunScript **n'est signalée nulle part** : `tests/check`
   compile le pilote avant chaque lancement pour l'éviter.
5. `ExecuteMultiplayerTestAsync(2)` lance des **processus Studio clients séparés**. Ils héritent
   du bureau caché : aucun n'est apparu sur le bureau de l'utilisateur.
6. **Au démarrage du client, la caméra mesure 1×1 pixel** pendant une à deux secondes, le temps
   que Studio dimensionne la vue. *Correction du 30/10/2026* : on avait d'abord attribué ce
   1×1 au bureau caché, mais les captures de la VM ont montré une vue normale au même moment.
   En attendant jusqu'à 5 s, la vue est dimensionnée **aussi sur le bureau caché**
   (PC : 1187×575 ; iPhone 13 simulé : 749×389, encoches déduites), et la géométrie de
   l'interface se vérifie dans les deux cas.
7. La simulation d'appareil fonctionne depuis RunScript : avec `iphone_13`, le client voit
   `TouchEnabled = true`, `KeyboardEnabled = false`, et le HUD passe en disposition tactile.
   Le pilote arrête toujours la simulation à la fin (`StopSimulationAsync`).
8. `--fullApi` s'exécute en 1,8 s et ouvre brièvement une petite fenêtre. Ce dump a servi à vérifier les niveaux de sécurité.

## 3. Architecture

```
test.cmd ─▶ tools/test-all.ps1
              ├─ lune / selene / stylua / rojo           (processus sans fenêtre)
              └─ tools/studio-tests.ps1
                   ├─ rojo build → build/MimicHunters.rbxl
                   ├─ génère driver.luau = Driver.template + ServerSuite + ClientSuite + sessions
                   ├─ HiddenDesktopRunner (C#) : CreateDesktop + CreateProcess(lpDesktop)
                   │     RobloxStudioBeta.exe --task RunScript --localPlaceFile … --runScriptFile driver.luau
                   │                          --outputFile studio-output.log --quitAfterExecution
                   │        └─ driver (DataModel d'édition)
                   │             ├─ injecte MH_TestServer (Script) et MH_TestClient (LocalScript)
                   │             ├─ ExecuteRunModeAsync      → suite « server »
                   │             ├─ ExecutePlayModeAsync     → suite « client » (PC)
                   │             ├─ SetDeviceAsync + Play    → suite « client » (mobile simulé)
                   │             └─ ExecuteMultiplayerTestAsync(2) → suite « multiplayer »
                   │                  chaque session termine par EndTest(rapport) → ligne « @@MH@@ {json} »
                   └─ lit la sortie, copie les journaux Studio, écrit studio-results.json
```

- La suite serveur accède au vrai monde de jeu via `_G.MimicHuntWorld`, exposé **uniquement en
  Studio**. Elle utilise des faux joueurs à identifiants négatifs pour la concurrence.
- La suite client ne simule **aucune** touche : elle appelle les mêmes RemoteEvents que l'interface
  (`RequestScan`, `RequestInspect`, `RequestCapture`, `SubmitPulse`). Elle vise le centre de la zone
  avec `CaptureMinigame.cursorAt`, et lit ensuite l'état réel du HUD.
- La place n'est **jamais enregistrée** : les scripts injectés n'existent que dans le Studio de test.

## 4. Ce que couvre l'automatisation

| Exigence | Où | Comment |
|---|---|---|
| Démarrage du serveur | Studio · server | `_G.MimicHuntWorld`, `Workspace.Map` présents |
| Génération des trois zones | Studio · server | dossiers Village / Park / Market non vides, point d'apparition |
| 41 objets | Studio · server + Lune | tags, ids uniques, types, répartition 17/11/13 ; **posés au sol et debout** |
| Six espèces | Studio · server + Lune | construction de chaque modèle, yeux, attribut, pivot |
| États de révélation | Studio · server + Lune | Revealed/verrou, Busy, NotOwner, AlreadyCapturing, fuite puis recache (tick serveur réel) |
| Captures et récompenses | Studio · server/client + Lune | capture réelle, inventaire, rejeu ×5 sans doublon |
| Concurrence | Studio · server + Lune | deux captures en parallèle, impulsions entrelacées |
| Connexions / déconnexions | Studio · client + multiplayer | 1 joueur réel, 2 clients, `LeaveTest`, `AddPlayers` |
| Interface PC / mobile | Studio · client-pc / client-mobile | HUD construit, disposition PC vs tactile, bandeau, carte de découverte, compteur |
| Protections | Studio · server + Lune | portée, données invalides, ids inconnus, spam (Lune) |
| Sauvegardes (V0.2) | Lune + Studio · server | pannes injectées, budget, verrou frais / périmé, deux serveurs concurrents, verrou perdu, reconnexion, version future jamais écrasée ; cycle complet sur le vrai `ProfileService` de Studio (stockage mémoire) |
| Exemplaires et idempotence | Lune + Studio | identifiants uniques sur 3 sessions, même événement de capture jamais accordé deux fois (y compris après rechargement) |
| Mutations | Lune + Studio | distribution sur 200 000 tirages, tutoriel Standard, cohérence après reconnexion ; capture réelle forcée (serveur) et capture rare par le réseau (client PC : Chromatic, mobile : Spectral) |
| Musées (V0.3) | Lune + Studio · server / client-pc / client-mobile | 8 parcelles, attribution et file d'attente, rendu exact de 6 Mimics (couleurs, Chromatic, Spectral), refus (non possédé, doublon), retrait, réorganisation, libération, migration v2 → v3, reconnexion (ProfileService réel, stockage mémoire), MA BASE / VILLAGE, mode décoration, personnalisation visible, visite et protections |
| Museum Hunt (V0.3) | Lune + Studio | lancement et refus, copies jamais révélées, bandes du scanner, portée, cachettes inventées, fin au temps, annulation (propriétaire, visiteur, sortie du jardin), répétition limitée, spam ; partie complète jouée par le vrai client (PC et mobile simulé) |
| Performance (V0.3) | Studio · client | Parts par musée, lumières, Mimics animés plafonnés, temps d'image (indicatif) |
| Codex, inventaire, objectifs | Studio · client-pc / client-mobile | panneau dans l'écran, pages réellement visibles, codex découvert/manquant, fiche, favori aller-retour, objectif validé, titre affiché au-dessus du personnage |

Contrôle de pertinence : en réintroduisant volontairement le bug de pivot corrigé en V0.1,
la suite Studio échoue sur `carte.objets_poses_au_sol` (« V13 bas de l'objet à Y = −8,75 ») et
`especes.six_modeles`. Le code a ensuite été restauré.

## 5. Isolation du bureau — ce qui est vrai, ce qui ne l'est pas

| Aspect | Bureau caché (défaut) | `-Visible` | Mesure |
|---|---|---|---|
| Fenêtres Studio sur ton bureau | **0** | oui (2 à 3) | `EnumWindows` sur le bureau de l'utilisateur, toutes les 250 ms |
| Studio prend le premier plan | **non** (10/10 exécutions) | **oui dans 2 essais RunScript sur 4** (preuves de concept, avant `test.cmd`) | `GetForegroundWindow` → PID |
| Clavier / souris simulés | aucun | aucun | — |
| **Ton clavier et ta souris vers Studio** | **passent** (constaté le 31/10/2026) : tes clics et touches peuvent atteindre le Studio du bureau caché | idem | journal des requêtes : captures, impulsions et déplacements non demandés par le test |
| Processus arrêtés | uniquement ceux lancés par le test (délai dépassé) | idem | PID / parent PID |
| CPU, GPU, mémoire | **partagés** : Studio consomme environ 1 à 2 Go et du GPU pendant ~75 s | idem | non isolé |
| Son | coupé par la suite client (`Volume = 0`) | idem | **non mesuré** (pas d'écoute automatisée) |
| Dialogues de Studio (mise à jour, connexion expirée…) | invisibles → le test échoue au bout du délai (420 s par défaut) | visibles | — |

**Entrées de l'utilisateur.** Le bureau caché empêche Studio de s'afficher et de prendre le
premier plan, mais **pas** de recevoir le clavier et la souris : des captures, impulsions et
déplacements parasites sont apparus pendant que le PC était utilisé (requêtes non émises par
le test, visibles dans le journal horodaté du rapport). Cause probable : l'entrée brute de
Windows (Raw Input), non séparée par bureau ; non prouvée, faute de pouvoir simuler des
entrées sur ton bureau. Parade dans la suite client : priorité maximale qui absorbe les
touches et clics du jeu, couche transparente sur l'écran, personnage immobile. Le jeu n'est
pas modifié. La VM, elle, est totalement isolée.

Le bureau caché est un objet Windows standard (`CreateDesktop`) : il est créé pour la durée du
test, jamais affiché (`SwitchDesktop` n'est pas appelé), et disparaît avec les processus. Ce
n'est **pas** un bac à sable : Studio garde l'accès réseau, disque et compte Roblox.

L'indicateur « le premier plan a changé pendant le test » est conservé dans le rapport, mais il
compte aussi **tes propres** changements de fenêtre : seul « Studio a pris le premier plan » mesure une interruption causée par le test.

## 6. Tableau : sans monopoliser le bureau vs session graphique isolée

| Test | Sans monopoliser ton bureau | Session graphique visible nécessaire |
|---|---|---|
| Syntaxe, lint, formatage, build | ✅ CLI | |
| 158 tests de logique pure (états, rencontres, minijeu, récompenses, concurrence, anti-triche, spam, disposition du HUD sur 9 écrans) | ✅ CLI (Lune) | |
| Démarrage serveur, 3 zones, 41 objets posés, 6 espèces, RemoteEvents | ✅ Studio caché | |
| Révélation, capture, récompense, rejeu, fuite, réapparition dans le vrai jeu | ✅ Studio caché | |
| Concurrence dans le vrai jeu (2 captures parallèles) | ✅ Studio caché | |
| Connexion d'un client, tutoriel de bout en bout par le réseau | ✅ Studio caché | |
| 2 clients, déconnexion (`LeaveTest`), reconnexion (`AddPlayers`) | ✅ Studio caché | |
| Interface : construction, mode PC vs tactile, textes, carte de découverte, compteur | ✅ Studio caché | |
| Mode tactile via simulation d'appareil | ✅ Studio caché (simulation ≠ téléphone réel) | |
| Géométrie de l'interface à la taille d'écran (boutons dans l'écran) | ✅ Studio caché et VM : éléments dans l'écran et sans chevauchement (PC 1187×517 et 556×375, iPhone 13 simulé 749×331) | captures VM |
| Rendu : couleurs, lumière, animations de révélation/capture/fuite, particules | | ✅ |
| Lisibilité, confort tactile, son audible | | ✅ (humain) |
| Performance (images/s, MicroProfiler, mémoire client) | | ✅ — et **jamais** une mesure de téléphone réel en simulation |
| Vrai téléphone / tablette | | ✅ appareil réel (nécessite une publication privée : non fait) |

## 7. Pour les tests graphiques : options isolées (non mises en place)

Rien de ce qui suit n'a été installé ni configuré : chaque option demande ton accord.

| Option | Compatibilité Roblox / GPU | Avantages | Limites |
|---|---|---|---|
| **Second PC** (même compte ou compte de test), `test.cmd -Visible` | Studio supporté nativement | Rendu réel, aucune gêne | Une machine de plus ; session Windows ouverte requise |
| **Machine virtuelle Hyper-V** (Windows 11 Pro) **avec GPU-P** (partition du RTX 4080 SUPER) | Studio exige Direct3D 11 : sans GPU-P, l'adaptateur de base Hyper-V passe par le rendu logiciel WARP (très lent, non représentatif). GPU-P se configure en PowerShell admin et n'est pas officiellement supporté sur Windows client | Isolement complet, captures automatisables dans la VM | Activer Hyper-V = **modification système** (redémarrage) ; licence Windows ; ~8 Go RAM |
| **Windows Sandbox** (Pro) | vGPU activé par défaut, mais repart de zéro à chaque lancement : réinstallation de Studio et reconnexion au compte à chaque fois | Jetable | Connexion Roblox manuelle à chaque session ; fonctionnalité Windows à activer |
| **Moniteur virtuel** (« Meta Virtual Monitor » est déjà présent) | rendu réel sur GPU | Pas de VM | Les fenêtres restent dans **ta** session : prise de focus toujours possible → ne résout pas le problème |

**Choix retenu (30/10/2026) : VMware Workstation**, sans Hyper-V, donc sans effet sur les jeux
et les émulateurs. Les scripts sont prêts : `test-vm.cmd` pilote la VM sans fenêtre, et un agent
dans la VM exécute `test-all.ps1 -Visible -Screenshots`. Installation pas à pas et état de
vérification : [VM_SETUP.md](VM_SETUP.md). La VM est en service depuis le 30/10/2026.

Au quotidien, `test.cmd` (bureau caché) suffit pour l'intégration. `test-vm.cmd` sert aux
vérifications visuelles : captures d'écran du rendu, du HUD et du minijeu.

## 8. Dépannage

| Symptôme | Cause probable | Action |
|---|---|---|
| `session.absente` pour toutes les sessions, durée ~15 s | Erreur de syntaxe dans le pilote généré | `lune run tests/check tests/studio` |
| Délai dépassé (420 s) | Dialogue invisible de Studio : mise à jour, connexion expirée, récupération automatique | Ouvrir Studio normalement une fois, fermer le dialogue, relancer |
| `rbxassetid://203785492 failed` dans la sortie | Boîte à outils de Studio | Bruit connu, filtré du rapport |
| Session revenue avec `attempts = 2` | Démarrage trop précoce, relancé automatiquement | Rien à faire si elle a réussi |
| `client.hud.tient_dans_l_ecran` ignoré | Vue restée sous 320×240 après 5 s d'attente | Inhabituel : relancer, ou vérifier avec `-Visible` ou dans la VM |
| Plugin Rojo : « Can't parse JSON » | Plugin plus ancien que Rojo 7.7.1 | `rojo plugin install` (sans effet sur `test.cmd`) |

## 9. Fichiers

| Fichier | Rôle |
|---|---|
| `test.cmd` | Commande unique |
| `tools/test-all.ps1` | Orchestration, contexte, rapport Markdown/JSON |
| `tools/studio-tests.ps1` | Build, génération du pilote, lancement de Studio, analyse |
| `tools/HiddenDesktopRunner.cs` | Lancement sur bureau caché + mesures d'isolation |
| `test-vm.cmd`, `tools/vm-tests.ps1` | Hôte : démarre la VM sans fenêtre, dépose la tâche, récupère le rapport |
| `tools/vm-agent.ps1`, `tools/vm-guest-setup.ps1` | Invité : agent de tests et préparation unique de la VM |
| `tests/studio/Driver.template.luau` | Pilote RunScript (sessions, simulation d'appareil, réessai) |
| `tests/studio/ServerSuite.server.luau` | Tests dans le serveur de session |
| `tests/studio/ClientSuite.client.luau` | Tests dans le client de session (réseau + HUD) |
| `tests/run.luau`, `tests/check.luau`, `tests/specs/` | Tests Lune existants (inchangés) |
