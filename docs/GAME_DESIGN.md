# MIMIC HUNTERS — Game Design (V0.3)

## 1. Promesse

Le monde a l'air normal, mais certains objets sont vivants. Le plaisir vient d'abord de
**remarquer** quelque chose d'étrange, de **vérifier** son intuition, puis de **réussir**
un geste de capture court et nerveux. La collection récompense ce plaisir ; elle ne le
remplace pas.

Boucle : **Chercher → Détecter → Capturer → Découvrir → Collectionner.**

Ce que le jeu n'est pas : un simulateur de clics, un tapis roulant, un jeu d'attente.

## 2. Boucle minute par minute

1. **Explorer** l'une des trois zones (Village Central, Parc Étrange, Zone Commerciale).
2. **Observer** : les Mimics proches trahissent leur présence par des indices discrets.
3. **Scanner** (`E`) : une onde part du joueur. Le serveur répond par une intensité
   (*Très fort / Moyen / Faible / Aucun*), jamais par une position. Les Mimics à moins de
   18 studs **sursautent** : c'est l'indice le plus fort, réservé à celui qui scanne.
4. **Examiner** (`F`, clic ou toucher) un objet à moins de 14 studs :
   - objet ordinaire → « Ce n'est qu'une poubelle ordinaire » et 1,2 s de délai ;
   - Mimic → il **jaillit** de son objet (révélation exagérée) et t'est réservé 8 s.
5. **Capturer** : bouton *Capturer*, puis le minijeu (5 à 12 s).
6. **Découvrir** : carte « Nouvelle espèce ! » avec le Mimic en 3D, sa rareté, son compteur.
7. **Collectionner** : le Codex (`C`) montre les espèces découvertes et des silhouettes pour les autres.

## 3. Les six Mimics de départ

| Id stable | Nom | Se cache en | Rareté | Tempérament | Indices | Révélation | Fuite | Difficulté (vitesse / zone) |
|---|---|---|---|---|---|---|---|---|
| `chairy` | Chairy | chaise | Commun | Timide | se tortille, yeux | saut + vrille | sautille | 0,75 / 26 % |
| `trashling` | Trashling | poubelle | Commun | Gourmand | couvercle qui claque, bruit | couvercle qui saute | sautille | 0,85 / 24 % |
| `posty` | Posty | boîte aux lettres | Peu commun | Bavard | drapeau qui se lève, yeux | drapeau + vrille | file | 0,95 / 22 % |
| `lumino` | Lumino | lampadaire | Peu commun | Curieux | clignote, yeux | éclair lumineux | sautille | 1,00 / 20 % |
| `chompy` | Chompy | coffre | Rare | Grincheux | couvercle, bruit, vibration | « chomp » ×3 | file | 1,15 / 18 % |
| `vendoo` | Vendoo | distributeur | Épique | Mystérieux | glitch de l'écran, bourdonnement | glitch | téléportation | 1,30 / 16 % |

Apparence révélée : l'objet se recolore à la couleur de l'espèce et gagne de **grands yeux**
(ronds, dépareillés, cyclope, colériques ou écran), une bouche (sourire, dents, lettre-langue,
rangée de crocs, onde néon) et un détail signature (nœud, arête, antenne…).
Tout est en Parts : aucun rig, aucun asset externe.

### Raretés provisoires

| Rareté | Poids d'apparition | Couleur |
|---|---|---|
| Commun | 50 | vert |
| Peu commun | 28 | bleu |
| Rare | 15 | violet |
| Épique | 7 | orange |

Le poids choisit l'espèce lors de chaque apparition, parmi les espèces dont un objet est libre.

## 4. Camouflage et indices

- 40 objets partagés + 1 chaise de tutoriel. 12 Mimics cachés en même temps (30 %),
  au moins 3 par zone.
- **Un Mimic caché est identique à un objet normal** : même constructeur, même variante
  de couleur (choisie par l'emplacement, jamais par la présence d'un Mimic).
- Les indices arrivent toutes les 6 à 15 s selon l'espèce. Ils ne sont envoyés qu'aux
  joueurs à moins de 60 studs : un Mimic au loin reste silencieux.
- Types : *Wiggle* (se tortille), *Vibrate*, *Eyes* (des yeux s'ouvrent, clignent, se
  referment), *Rattle* (couvercle), *Flag* (drapeau), *Flicker* (lumière), *Glitch*
  (couleurs de l'écran), *Sound* (bruit 3D + tremblement).
- Le scanner aide sans tout révéler : portée 45 studs, intensité seulement, recharge 3 s.

## 5. Le minijeu de capture

- Une jauge horizontale, une **zone verte**, un **curseur** qui fait des allers-retours.
- **Impulsion** (`Espace`, clic, bouton, A) quand le curseur est dans la zone.
- **2 impulsions réussies** stabilisent le Mimic. Après chaque réussite, le curseur accélère
  (+25 %) et la zone rétrécit (−20 %).
- **2 ratés** : le Mimic s'échappe (sautille, file ou se téléporte) et se recache ailleurs,
  dans un objet du même type. Pas d'autre pénalité : on peut rechasser tout de suite.
- Délai total : 14 s. Le curseur repart d'une extrémité, loin de la zone, à chaque étape :
  pas de réussite « gratuite ».
- Durée observée en test automatisé pour un joueur moyen (1 raté, 2 réussites) : < 12 s.

## 6. Première expérience (objectifs)

| Objectif | Mécanisme |
|---|---|
| < 30 s : remarquer un objet étrange | Une chaise de tutoriel **personnelle** à 10 studs du point d'apparition, face au joueur, envoie un indice toutes les 2,5 à 3,5 s. |
| < 90 s : première capture | Bandeau d'une phrase par étape (Scanner → Examiner → Capturer). Un « ? » apparaît au-dessus de la chaise. Minijeu du tutoriel lent, zone large (34 %), **ratés illimités**. |
| < 5 min : plusieurs espèces | 12 Mimics actifs dès le départ, au moins 3 par zone, 4 espèces ou plus présentes simultanément (vérifié par test). |
| < 10 min : comprendre le système | Codex avec silhouettes et « Se cache en… » pour orienter la recherche. |

La capture du tutoriel est **garantie** : si le joueur échoue (délai), le Mimic se recache
dans la même chaise et le tutoriel revient à l'étape « Examiner ». Le tutoriel se termine
aussi si le joueur capture d'abord un Mimic partagé.

Pas de dialogue, pas de menu bloquant, pas d'attente artificielle.

## 7. Multijoueur

- Les Mimics partagés sont des entités du monde. **Le premier à examiner** un Mimic le
  révèle et se le voit réservé (8 s pour lancer la capture, puis toute la durée du minijeu).
- Les autres joueurs voient la révélation, le nom du chasseur et la capture en direct ;
  un examen de leur part répond « X est déjà sur ce Mimic ».
- Une capture retire le Mimic ; un nouveau apparaît 5 s plus tard ailleurs. L'emplacement
  libéré reste bloqué 10 s.
- Un joueur ne garde qu'une révélation à la fois : il ne peut pas « réserver » la carte.
- Le Mimic du tutoriel est **personnel** : invisible pour les autres, il ne bloque personne.
- Un joueur qui quitte en pleine capture libère son Mimic, qui s'enfuit.

## 8. Direction artistique

Ambiance *cute-creepy* : fin d'après-midi violacée, brume légère, lampadaires et fenêtres
allumés, parc aux arbres violets et turquoise, champignons lumineux, arche de pierre aux runes
néon, cristaux flottants. Couleurs franches, formes simples, grands yeux. Pas de violence,
pas d'horreur : les Mimics sont malicieux, pas menaçants.

## 9. Collection persistante (V0.2)

Chaque capture donne un **exemplaire** permanent, à soi : identifiant unique, espèce, rareté,
mutation éventuelle, petite variation d'apparence (teinte, taille ±7 %), date, favori. On peut en
posséder plusieurs de la même espèce : deux Chairy ne sont jamais tout à fait identiques.

Panneau **Collection** (bouton CODEX ou touche C) :
- **Codex** : les 6 espèces, découvertes ou en silhouette avec un indice (« Se cache en chaise »),
  exemplaires possédés, pastilles des 3 apparences trouvées, probabilités des mutations ;
- **Inventaire** : tous les exemplaires, par pages ; filtres rareté / espèce / mutation / favoris ;
  tri récents ou rareté ; fiche avec aperçu 3D animé, date, numéro, taille, favori ;
- **Objectifs** : progression et récompenses, réglages ;
- compteur permanent : espèces 2/6, apparences 2/18, nombre de Mimics.

## 10. Mutations (cosmétiques)

| Mutation | Probabilité par capture | Apparence |
|---|---|---|
| Standard | 94,5 % | couleurs de l'espèce, variation personnelle |
| Chromatic | 4 % | palette irisée qui glisse lentement, léger éclat lumineux |
| Spectral | 1,5 % | translucide, yeux lumineux, trois petites lueurs en orbite |

Tirage côté serveur à la capture réussie ; le Mimic du tutoriel est toujours Standard. Aucun
effet sur le gameplay. Révélation : éclair et anneau aux couleurs de la mutation, le Mimic prend
son apparence, puis la capture continue (≈ 0,8 s de plus) ; carte de capture dédiée avec la
probabilité ; annonce aux autres joueurs du serveur. Avec ~1 capture par minute, une Chromatic
arrive en moyenne vers la 25e capture, une Spectral vers la 67e.

## 11. Progression du collectionneur

| Objectif | Récompense garantie |
|---|---|
| Première capture | titre « Apprenti chasseur » |
| Trois espèces | couleur de scanner Menthe |
| Dix captures | couleur de scanner Corail |
| Première Chromatic | couleur de scanner Prisme |
| Première Spectral | titre « Murmure spectral » |
| Collection complète (6 espèces) | titre « Maître des Mimics » |

Le titre s'affiche au-dessus du personnage (visible par tous) ; la couleur change l'onde du
scanner. Pas de monnaie, pas de rebirth, pas d'arbre d'amélioration.

## 12. Ressenti (V0.2)

Scanner : un bip par barre de signal, de plus en plus aigu. Capture : écrasement puis étirement,
particules et anneau dosés selon la rareté. Pastille « ! » sur CODEX quand il y a du nouveau.
Réglages Sons et Effets réduits, sauvegardés.

## 13. Hors périmètre V0.2 (rappel)

Économie et monnaies, achats Robux, échanges, musée, base personnelle, PvP, mutations avancées,
événements. Le modèle de données les prépare (voir DATA_SCHEMA.md) sans les commencer.

## 14. Musées personnels (V0.3)

Boucle : **Chercher → Capturer → Collectionner → Exposer → Visiter → Découvrir.**

Chaque joueur reçoit une parcelle dans le **Quartier des collectionneurs**, au nord du Village
(~7 s à pied, ou bouton MA BASE). Son musée : une salle cute-creepy aux liserés néon, son nom
sur l'enseigne, 6 vitrines, un panneau de statistiques, un emplacement « bientôt : nouvelle
salle » et, devant, le jardin de la Museum Hunt.

- **Exposer** (onglet Musée) : choisir une vitrine, puis un de ses exemplaires (les plus rares
  d'abord). Le Mimic apparaît en 3D avec sa taille, ses couleurs et sa mutation exactes : une
  Chromatic reste irisée, une Spectral translucide avec ses lueurs. Il respire, cligne des yeux,
  bouge de temps en temps et se tourne vers les visiteurs qui s'approchent.
- **Examiner** (invite près d'une vitrine) : nom, rareté, mutation et sa probabilité, taille,
  numéro de l'exemplaire, collectionneur, aperçu 3D.
- **Personnaliser** : murs, lumière, socles, thème (3 options gratuites chacun) ; socles
  « Étoilé » offerts par l'objectif « Première vitrine ».
- **Visiter** (onglet Visites) : liste des musées présents (espèces, Mimics exposés,
  mutations exposées), bouton Visiter. Un visiteur regarde et examine, ne modifie jamais rien.

Pourquoi cela donne envie de collectionner : une mutation rare devient quelque chose qu'on
**montre** (vitrine colorée, fiche avec sa probabilité, statistiques publiques dans la liste).

## 15. Museum Hunt (V0.3)

Chez un autre joueur, le panneau du jardin lance une chasse de **75 s** : 8 objets ordinaires,
dont 3 cachent des **copies** de Mimics exposés par le propriétaire (même apparence, mutation
comprise). Indices discrets, scanner (E) et examen (F) habituels.

| Score | Valeur |
|---|---|
| Copie trouvée | +100 |
| Objet ordinaire examiné | −15 |
| Tout trouvé | +2 par seconde restante |

Résultat : score, record personnel, nombre de musées différents explorés ; objectif
« Explorateur de musées » (3 musées) → titre garanti. Le propriétaire est prévenu quand
quelqu'un relève son défi, puis de son résultat. Il ne perd jamais rien : les copies
disparaissent une fois trouvées, ses vrais exemplaires restent dans leurs vitrines.

Interaction sociale : la visite apporte un défi (pas seulement de l'observation), et un musée
bien garni de Mimics rares rend la chasse plus belle pour ses visiteurs.

## 16. Hors périmètre V0.3 (volontairement)

Échanges, vol de Mimics, achats Robux, économie, rebirths, combats, décoration libre, monde
ouvert, nouvelles espèces. Les styles payants « à résultat connu » sont seulement envisagés.