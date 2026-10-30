# MIMIC HUNTERS — Machine virtuelle de tests graphiques (VMware Workstation)

## Pourquoi une VM

`test.cmd` fait tourner Studio sur un bureau Windows caché : rien ne s'affiche chez toi, mais
personne ne voit le rendu. La VM apporte ce qui manque, **sans rien afficher sur ton bureau** :

- des **captures d'écran automatiques** toutes les 2 s pendant les sessions (révélations,
  minijeu, HUD mobile simulé), rangées dans le rapport pour une relecture visuelle ;
- Studio peut afficher ses fenêtres et prendre le focus **dans la VM** sans te déranger.

Ce qu'elle n'apporte pas : une mesure de performance représentative (GPU virtuel, pas ta
RTX 4080 en direct), ni un vrai téléphone.

## État au 30/10/2026

| Élément | État |
|---|---|
| Scripts hôte et invité (`test-vm.cmd`, `tools/vm-*.ps1`) | ✅ écrits |
| VM « ROBLOX DEV » (`E:\VMS\ROBLOX DEV`), compte `mimictest`, Studio connecté | ✅ installée par l'utilisateur |
| Studio dans VMware (GPU « VMware SVGA 3D ») | ✅ **vérifié** : 4 sessions, 44 tests réussis (géométrie du HUD comprise), rendu visible sur les captures (carte, HUD, minijeu, 2 joueurs) |
| Écran de la VM | ⚠️ 1024×768 au lieu de 1920×1080 : la vue Studio est petite, et le cadre du téléphone simulé est coupé sur les captures |
| Mise à jour automatique de l'agent (noms versionnés) | ✅ testée sur l'hôte ; ⚠️ dans la VM, l'agent en place date d'avant : relancer l'étape 7 **une fois** |

## Ton PC (audit en lecture seule)

Ryzen 7 9700X (8 cœurs / 16 threads), 31 Go de RAM, virtualisation activée dans le firmware,
**aucun hyperviseur actif** (Hyper-V et VBS désactivés), disque E: avec 790 Go libres.
VMware Workstation n'active pas Hyper-V : tes émulateurs Android et anti-triches de jeux ne
sont pas concernés.

## Ressources conseillées pour la VM

| Paramètre | Valeur | Pourquoi |
|---|---|---|
| Processeurs | 4 vCPU | Studio + 2 clients de test, en laissant 12 threads à l'hôte |
| Mémoire | 8 Go | Studio en multijoueur (~3 processus) ; la VM est mise en veille après les tests |
| Disque | 120 Go sur **E:** (`E:\VMs\MimicTests`) | disque séparé du système |
| Affichage | 3D activée, 8 Go de mémoire graphique, moniteur fixe 1920×1080 | rendu DirectX de Studio, géométrie stable |
| Réseau | NAT | Studio a besoin d'Internet (connexion Roblox) |

## Étapes (une seule fois)

Les étapes 1 à 6 et 8 demandent ton action : compte, téléchargements, droits administrateur, mots de passe.

### 1. Installer VMware Workstation Pro (gratuit pour un usage personnel)
1. Crée un compte sur le portail Broadcom (support.broadcom.com), puis télécharge
   **VMware Workstation Pro pour Windows**.
2. Lance l'installeur et accepte l'invite administrateur. Tu peux **décocher** le
   « Enhanced Keyboard Driver » (il demande un redémarrage et ne sert pas ici).
3. Effet sur ton système : deux cartes réseau virtuelles (VMnet1, VMnet8) et des services
   VMware sont ajoutés. Hyper-V n'est pas activé.

### 2. Télécharger Windows 11
Image ISO officielle : https://www.microsoft.com/software-download/windows11
(« Télécharger l'image disque (ISO) Windows 11 pour les appareils x64 »).
Licence : une VM demande sa propre licence. Sans activation, Windows 11 fonctionne avec des
limites (filigrane, personnalisation).

### 3. Créer la VM
*File › New Virtual Machine › Typical* :
- ISO Windows 11, système « Windows 11 x64 » ;
- **chiffrement** demandé pour le TPM virtuel : choisis « Only the files needed to support a TPM
  are encrypted ». Le mot de passe est à ton choix ; coche « Remember the password » ;
- nom `MimicTests`, emplacement `E:\VMs\MimicTests`, disque 120 Go ;
- *Customize Hardware* : Memory 8192 Mo, Processors 4, Display → *Accelerate 3D graphics*,
  Graphics memory 8 Go, *Specify monitor settings* → 1 moniteur, 1920×1080.

### 4. Installer Windows dans la VM
- Crée un **compte local dédié**, par exemple `mimictest`, sans données personnelles.
  Si l'installation exige un compte Microsoft : `Maj+F10`, puis `start ms-cxh:localonly`.
  Sur certaines versions, la commande est `OOBE\BYPASSNRO`.
- Installe les VMware Tools : ils fournissent le pilote 3D et les dossiers partagés.
  Le menu *VM › Install VMware Tools* échoue souvent sur les versions Broadcom
  (« Could not find component on update server »). Dans ce cas, **dans la VM**, ouvre Edge sur
  https://packages.vmware.com/tools/releases/latest/windows/x64/, télécharge
  `VMware-tools-<version>-x64.exe`, lance-le (installation *Typical*) puis redémarre.
- Fixe la résolution de Windows à **1920×1080**.

### 5. Partager le dossier d'échange
Sur l'hôte, lance une fois `test-vm.cmd`. Il crée `build\vm-exchange` puis s'arrête sur
« vmx introuvable », ce qui est normal à ce stade. Ensuite, dans VMware :
*VM › Settings › Options › Shared Folders › Always enabled › Add*.
- Chemin hôte : `…\MIMIC_HUNTERS\build\vm-exchange`
- Nom : `mimic-exchange`, en lecture **et écriture**.
Dans la VM, le dossier apparaît sous `\\vmware-host\Shared Folders\mimic-exchange`.

### 6. Roblox Studio dans la VM
Installe Studio depuis https://create.roblox.com, ouvre-le et **connecte-toi**.
Conseil : utilise un **compte Roblox de test** plutôt que ton compte principal, car la VM
conserve la session.

### 7. Script de préparation (dans la VM, PowerShell administrateur)
```powershell
powershell -ExecutionPolicy Bypass -File "\\vmware-host\Shared Folders\mimic-exchange\setup\vm-guest-setup.ps1"
```
Le script refuse de s'exécuter hors d'une VM VMware. Il installe Git et Rokit, désactive la mise
en veille **de la VM**, et enregistre l'agent au démarrage de session (tâche planifiée
`MimicHuntersAgent`). Il remplace et relance un agent déjà démarré.
Ensuite, l'agent **se met à jour seul** : avant chaque test, `test-vm.cmd` publie la dernière
version sous un nouveau nom (`setup\agent\vm-agent-<horodatage>-<empreinte>.ps1`), et l'agent
la copie puis redémarre. Le nom change à chaque version parce que VMware garde verrouillé, côté
hôte, un fichier que la VM relit régulièrement.
**Vérification Studio** : ouvre Studio dans la VM, lance une place vide et Play.
Si le rendu ou les performances posent problème, arrête-toi ici et signale-le-moi.

### 8. Ouverture de session automatique (dans la VM)
`netplwiz` → décoche « Les utilisateurs doivent entrer un nom… », ou utilise Sysinternals
Autologon. C'est nécessaire : Studio a besoin d'une session ouverte pour afficher sa fenêtre.
Le mot de passe du compte `mimictest` reste stocké **dans la VM** uniquement. Redémarre la VM :
l'agent démarre seul, réduit dans la barre des tâches.

### 9. Premier lancement depuis l'hôte
```bat
test-vm.cmd -Vmx "E:\VMs\MimicTests\MimicTests.vmx"
```
Le chemin est mémorisé (`build\vm-config.json`). Ensuite :
```bat
test-vm.cmd                              :: les 4 sessions, VM mise en veille à la fin
test-vm.cmd -Sessions client,mobile      :: sessions choisies
test-vm.cmd -KeepRunning                 :: laisse la VM allumée (enchaîner plusieurs essais)
```
Rapport : `build\vm-exchange\jobs\<id>\report\report.md`, captures dans `report\screenshots\`,
copie dans `build\test-reports\latest-vm.md`.

## Fonctionnement

```
Hôte                                          VM « MimicTests » (session mimictest ouverte)
test-vm.cmd → tools/vm-tests.ps1               tâche planifiée → C:\MimicTests\agent\vm-agent.ps1
  vmrun start MimicTests.vmx nogui  ─────────▶   (démarre avec la session)
  attend agent-heartbeat.json      ◀─────────    écrit un battement de cœur toutes les 5 s
  dépose jobs/<id>/repo + job.ready ─────────▶   copie dans C:\MimicTests\work\<id>
                                                 rokit install ; test-all.ps1 -Visible -Screenshots
  attend jobs/<id>/done.json       ◀─────────    renvoie report/ (+ screenshots/) et done.json
  vmrun suspend (si démarrée par le script)
```

- **Aucune fenêtre sur ton bureau** : la VM tourne sans interface (`nogui`). Pour la regarder,
  ouvre VMware Workstation et sélectionne-la.
- **Aucun identifiant** côté hôte : `vmrun` ne fait que démarrer et suspendre la VM ; tout passe
  par le dossier partagé.
- Ressources : environ 8 Go de RAM et 4 cœurs pendant les tests. La VM est mise en veille ensuite.

## Dépannage

| Symptôme | Action |
|---|---|
| « Could not find component on update server » (Install VMware Tools) | Télécharger l'installeur dans la VM depuis packages.vmware.com (étape 4) |
| « La VM est chiffrée (TPM virtuel) » / vmrun « A password is required » | `vmrun` ne démarre pas une VM chiffrée sans mot de passe, et le script n'en stocke pas. Démarre la VM dans Workstation, ferme Workstation avec *Run in Background*, puis relance `test-vm.cmd` |
| VM rangée dans un dossier OneDrive | À éviter : OneDrive tente de téléverser des dizaines de Go de disques virtuels pendant qu'ils changent. VM éteinte, déplace son dossier vers un disque non synchronisé (`E:\VMs`), rouvre le `.vmx` et réponds *I Moved It* |
| « vmrun.exe introuvable » | Installer VMware Workstation (étape 1) |
| « L'agent ne répond pas » | Session non ouverte automatiquement (étape 8), dossier partagé désactivé (étape 5), ou script de l'étape 7 lancé depuis un **autre compte** : la tâche ne démarre que pour l'utilisateur qui l'a enregistrée, donc relance l'étape 7 depuis le compte qui s'ouvre automatiquement |
| Tâche jamais prise en charge | Dans la VM : `Get-ScheduledTask MimicHuntersAgent`, puis lancer l'agent à la main pour voir l'erreur |
| Résultat `-1`, `console.txt` vide | Rokit absent du PATH de l'agent : rouvrir la session après l'étape 7 |
| Sessions Studio en délai dépassé | Ouvrir Studio dans la VM : dialogue de mise à jour ou de connexion expirée |
| Captures noires | VM affichée en veille d'écran : relancer l'étape 7 (alimentation) |
