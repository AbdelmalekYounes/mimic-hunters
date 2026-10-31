# MIMIC HUNTERS — Analyse d'équilibrage (V0.3.1, jalon 5)

> Les chiffres ci-dessous viennent de **simulations** (`lune run tools/balance`) et de la
> lecture des réglages (`Config/GameConfig`, `MimicCatalog`, `Rarities`, `Mutations`). Ils ne
> remplacent pas des joueurs réels : le playtest ([PLAYTEST_PLAN.md](PLAYTEST_PLAN.md)) et les
> mesures automatiques doivent les confirmer ou les corriger.

## 1. Museum Hunt — le constat qui a motivé un changement

Des « bots » ont joué 400 vrais défis par stratégie contre le vrai `MuseumCore`, avec le temps de
marche réel (18 studs/s). Stratégies : **hasard** (examiner dans le désordre), **balayage**
(cachette la plus proche, force brute optimale), **indices** (n'examiner que l'objet qui a
bougé), **scanner** (indices + scanner pour débusquer).

### Avant (réglages V0.3)

| Stratégie | Ratés | Durée | Score moyen |
|---|---|---|---|
| hasard | 3,73 | 6,4 s | 381 |
| balayage | 4,02 | 5,4 s | 378 |
| indices | 0,00 | 7,6 s | 434 |
| scanner | 0,00 | 6,8 s | 436 |

Problèmes :

- **Tout défi finissait en 6 à 8 s** sur 75 : les 3 copies se trahissaient toutes dès 1,5 s.
- **Examiner au hasard valait presque la chasse** (−12 % de score seulement) : un raté ne coûtait
  que 15 points et 1 s. On pouvait « cliquer au hasard », ce que le cahier des charges exclut.
- Le scanner ne servait à rien (les indices suffisaient).

### Après (réglages V0.3.1)

Changements (`GameConfig.MuseumHunt`) :

| Réglage | Avant | Après | Pourquoi |
|---|---|---|---|
| Indices | les 3 copies en même temps | **un par un** (`SequentialClues`) | les autres copies se débusquent au scanner : il redevient utile |
| Premier indice | 1,5 à 8 s | **5 à 10 s** (`FirstClueMin`), puis toutes les 6 à 10 s | il faut observer avant d'agir |
| Pénalité d'un raté | −15 points, 1 s | **−40 points, 2,5 s** | examiner au hasard ne paie plus |

| Stratégie | Ratés | Durée | Score moyen |
|---|---|---|---|
| hasard | 3,73 | 11,4 s | 277 |
| balayage | 4,02 | 11,4 s | 266 |
| indices | 0,00 | 25,3 s | 399 |
| scanner | 0,00 | 10,3 s | 429 |

Lecture :

- **Hiérarchie claire** : chasseur au scanner (429) > patient qui suit les indices (399) ≫ hasard
  (≈ 270). Le joueur qui chasse vraiment est récompensé, celui qui clique au hasard le voit.
- **Durée** : 10 à 25 s pour un joueur qui chasse, toujours largement dans les 75 s. Le défi
  reste court (un mini-jeu de visite), mais n'est plus instantané.
- Le résultat (score, record, musées différents) et la durée de 75 s n'ont pas changé.
- Les règles sont expliquées au lancement (« Un seul bouge à la fois : scanne pour débusquer les
  autres… Erreur : −40 points ») et à chaque raté.

Limites : les bots ne ratent jamais un indice et savent exactement où chaque objet se trouve ;
de vrais joueurs seront plus lents. Le jardin n'a que 8 cachettes rapprochées : si le playtest
montre que la chasse reste trop simple, la piste suivante est d'**espacer ou d'ajouter des
cachettes** (géométrie du jardin), pas de rallonger le défi.

Garde-fous : `museum_hunt.spec › équilibrage V0.3.1` (un seul indice à la fois, pénalités).

## 2. Mutations (4 % Chromatic, 1,5 % Spectral — inchangées)

Probabilité d'obtenir au moins une mutation, selon le rythme de captures (**hypothèse**, à
mesurer au playtest : `CapturesParSession`).

| Rythme | 10 min | 20 min | 30 min |
|---|---|---|---|
| 1 capture/min — ≥ 1 rare | 43 % | 68 % | 82 % |
| 1 capture/min — ≥ 1 Spectral | 14 % | 26 % | 36 % |
| 2 captures/min — ≥ 1 rare | 68 % | 90 % | 97 % |
| 2 captures/min — ≥ 1 Spectral | 26 % | 45 % | 60 % |

En moyenne : 18 captures avant la première mutation rare, 67 avant le premier Spectral.

Lecture : sur une session de 20 à 30 minutes, la plupart des joueurs voient **au moins une**
mutation rare (un « moment » marquant), et le Spectral reste vraiment rare (un tiers à la moitié
des joueurs). Les mutations ne sont donc ni banalisées ni introuvables. **Aucun changement
proposé** (conformément à la consigne de ne pas les modifier arbitrairement). À surveiller au
playtest : si le rythme réel est nettement sous 1 capture/min, une session de 10 minutes risque
de n'offrir aucune mutation à plus de la moitié des joueurs ; il faudrait alors accélérer la
boucle de capture (indices, réapparition), pas toucher aux probabilités.

## 3. Codex (6 espèces, pondérations 50/28/15/7 par rareté)

| Espèce | Part des rencontres |
|---|---|
| Chairy, Trashling (Commun) | 28,1 % chacune |
| Posty, Lumino (Peu commun) | 15,7 % chacune |
| Chompy (Rare) | 8,4 % |
| Vendoo (Épique) | 3,9 % |

Captures pour tout découvrir : **moyenne 31, médiane 24, 90 % des joueurs en moins de 60**.
À 1–2 captures/min, la moitié des joueurs complètent le Codex en 12 à 24 minutes : un objectif
atteignable dans une première session longue, puis les mutations et le musée prennent le
relais. Pas de changement proposé.

## 4. Chasse principale (lecture des réglages, à mesurer)

| Point | Réglage | Analyse |
|---|---|---|
| Scanner | recharge 3 s, portée 45, bandes 14 / 28 | spammer le scanner est impossible (recharge serveur) ; il oriente sans désigner l'objet |
| Examiner au hasard | recharge 0,5 s, **1,2 s après un objet ordinaire** | le coût d'un raté reste faible : à surveiller (`CaptureRatee` ne le mesure pas ; noter au playtest le nombre d'objets examinés par erreur) |
| Capture | 2 réussites, 2 ratés permis ; 5 à 12 s pour un joueur moyen (test existant) | accessible ; le Mimic qui s'échappe se recache ailleurs (pas de perte définitive) |
| Attente | 12 Mimics actifs, réapparition 5 s | pas de période morte attendue, même à plusieurs |
| « Volé » par un autre | le joueur qui révèle a **8 s de priorité** ; un seul joueur par Mimic | frustration limitée ; le second reçoit un refus clair (« occupé ») |

## 5. Progression

Objectif toujours visible : compteur d'espèces du HUD, Codex (silhouettes « ??? »), 8 objectifs
avec récompense garantie (titres, couleurs de scanner, socle Étoilé, titre Explorateur), musée à
remplir, record de Museum Hunt. Le guide de première session (jalon 6) relie maintenant ces
éléments dans l'ordre : capture → collection → musée → vitrine → visites. Aucun nouveau système
d'économie n'a été ajouté.
