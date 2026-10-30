# MIMIC HUNTERS — Game Design (V0.1)

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

## 9. Hors périmètre V0.1 (volontairement)

Économie, achats Robux, échanges, musée, mutations, événements, sauvegarde DataStore.
Les interfaces de sauvegarde sont prêtes (voir ARCHITECTURE.md).
