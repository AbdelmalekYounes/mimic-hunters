# MIMIC HUNTERS — Plan de playtest privé (V0.3.1)

> Ce document sert à **organiser et noter** un test avec 3 à 5 vrais joueurs. Il ne contient
> aucune réponse de testeur : tout ce qui suit est à remplir pendant et après la séance.

## 1. Objectifs

Savoir si les joueurs, **sans explication extérieure** :

1. comprennent le jeu (scanner, examiner, capturer) ;
2. prennent du plaisir à capturer ;
3. ont envie de collectionner les mutations ;
4. comprennent l'utilité des musées ;
5. visitent spontanément le musée d'un autre joueur ;
6. ont envie de revenir jouer.

## 2. Pré-requis

| Élément | État attendu |
|---|---|
| Expérience de test privée | publiée par toi, voir [PRIVATE_TEST_PUBLISH.md](PRIVATE_TEST_PUBLISH.md) |
| Testeurs | 3 à 5 comptes que **tu** invites (amis ou comptes de test à toi) ; personne ne joue avec ton compte principal |
| Appareils | au moins 1 PC et 1 téléphone (et une tablette si possible) : c'est la première mesure sur vrais appareils |
| Mesures automatiques | actives en jeu publié (AnalyticsService) : entonnoir d'intégration et événements personnalisés, voir § 6 |
| Observateur | toi (ou un ami) avec ce document, sans aider les joueurs |
| Consentement | les testeurs savent qu'on les observe et que des statistiques anonymes de jeu sont relevées |

## 3. Déroulé (20 minutes)

| Minute | Phase | Consigne donnée | Ce que l'observateur note |
|---|---|---|---|
| 0–1 | Accueil | « Rejoignez le jeu et jouez comme vous voulez. Pensez à voix haute. » Aucune autre explication. | appareil de chacun |
| 1–6 | Découverte | aucune | temps avant 1re capture ; hésitations ; tutoriel compris ? |
| 6–12 | Collection | aucune | ouverture du Codex ; réaction à une mutation (si elle arrive) ; utilisation de MA BASE |
| 12–17 | Musées | aucune (si personne n'a trouvé les musées à la minute 14 : « Il y a un quartier des musées » et le noter) | expositions ; visites spontanées ; Museum Hunt lancée ? comprise ? |
| 17–20 | Questions | questionnaire § 5 | réponses |

Ne jamais montrer un bouton ou une touche. Si un joueur est bloqué plus de 2 minutes, noter
« bloqué » et l'endroit, puis donner l'indice minimal.

## 4. Grille d'observation (une par joueur)

Joueur : ________ · Appareil : ☐ PC ☐ téléphone ☐ tablette · Déjà joué à un jeu Roblox de
collection : ☐ oui ☐ non

| Moment | Observé ? | Temps (mm:ss) | Remarques |
|---|---|---|---|
| Premier scan | ☐ | | |
| Premier objet examiné | ☐ | | |
| Première capture réussie | ☐ | | |
| Capture ratée (combien) | | | |
| Ouverture de la collection | ☐ | | |
| Mutation obtenue (laquelle) | ☐ | | réaction : |
| Bouton MA BASE utilisé | ☐ | | |
| Premier Mimic exposé | ☐ | | |
| Visite d'un autre musée | ☐ spontanée ☐ après indice | | |
| Museum Hunt lancée | ☐ | | |
| Museum Hunt réussie (score) | ☐ | | |
| Bloqué > 2 min (où) | | | |
| Frustration visible (quand, pourquoi) | | | |
| Rire, exclamation, envie de montrer | | | |
| Bug constaté | | | |

## 5. Questionnaire de fin (2 minutes, oral ou écrit)

Échelle de 1 (pas du tout) à 5 (tout à fait).

| # | Question | 1–5 | Commentaire |
|---|---|---|---|
| Q1 | J'ai compris quoi faire sans qu'on m'explique. | | |
| Q2 | Capturer un Mimic était amusant. | | |
| Q3 | J'ai envie d'obtenir des mutations (Chromatic, Spectral). | | |
| Q4 | Je comprends à quoi sert mon musée. | | |
| Q5 | J'ai eu envie d'aller voir le musée des autres. | | |
| Q6 | La Museum Hunt était une vraie petite chasse (pas du hasard). | | |
| Q7 | J'aimerais rejouer. | | |
| Q8 | Ce qui m'a le plus plu : ______ | | |
| Q9 | Ce qui m'a le plus gêné : ______ | | |
| Q10 | Sur téléphone : boutons faciles à toucher, rien de caché ? | | |

## 6. Mesures automatiques (en jeu publié)

Relevées par `Core/SessionMetrics` et envoyées par `Services/AnalyticsServer` à
AnalyticsService (Creator Hub → Analytics). Aucune donnée personnelle, aucun texte libre.

| Mesure | Événement |
|---|---|
| Entonnoir d'intégration | Arrivée → Premier scan → Première capture → Codex ouvert → Base visitée → Premier Mimic exposé → Autre musée visité → Museum Hunt réussie |
| Temps avant 1re capture / Codex / base / exposition / visite | `TempsPremiereCapture`, `TempsPremierCodex`, `TempsPremiereBase`, `TempsPremiereExposition`, `TempsPremiereVisite` (secondes) |
| Captures réussies / ratées | `CaptureReussie`, `CaptureRatee` |
| Mutations obtenues | `MutationChromatic`, `MutationSpectral` |
| Museum Hunts | `MuseumHuntLancee`, `MuseumHuntTerminee` |
| Session | `DureeSession` (secondes), `CapturesParSession` |

Avec 3 à 5 joueurs, ces chiffres sont **indicatifs** : ils complètent l'observation, ils ne la
remplacent pas. Les tableaux de bord de Roblox peuvent mettre du temps à s'afficher.

## 7. Validation multijoueur réelle (pendant la séance)

Ces points ont été automatisés dans Studio avec 2 clients locaux (17 contrôles) ; la séance les
confirme sur de vrais serveurs, avec la vraie latence :

| # | À vérifier | OK ? |
|---|---|---|
| R1 | chaque joueur a sa propre parcelle | ☐ |
| R2 | A visite B et B visite A | ☐ |
| R3 | un Mimic Chromatic ou Spectral exposé a le même aspect chez tous | ☐ |
| R4 | A change une vitrine pendant que B regarde : B voit le changement | ☐ |
| R5 | deux joueurs sur le même Mimic : un seul le capture, l'autre a un message clair | ☐ |
| R6 | deux visiteurs lancent la Museum Hunt du même musée : un seul défi, message « occupé » | ☐ |
| R7 | le propriétaire quitte pendant un défi : le visiteur est prévenu, rien n'est perdu | ☐ |
| R8 | un joueur revient le lendemain : collection, vitrines et styles intacts | ☐ |

## 8. Hiérarchiser les corrections

Après la séance, reporter chaque problème dans ce tableau :

| Problème | Joueurs concernés | Gravité (bloquant / gênant / mineur) | Fréquence | Priorité (P1/P2/P3) | Décision |
|---|---|---|---|---|---|
| | | | | | |

Règle proposée : **P1** = bloquant pour au moins un joueur, ou perte de données ; **P2** = gênant
pour au moins la moitié des joueurs ; **P3** = le reste. On corrige toutes les P1 avant un
nouveau test, les P2 avant toute publication publique.
