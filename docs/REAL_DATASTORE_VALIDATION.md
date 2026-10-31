# MIMIC HUNTERS — Validation sur un vrai DataStore (V0.3.2)

Date : 31/10/2026. Expérience : **MIMIC HUNTERS — Private Test** (privée), univers
`10773995454`, lieu `91525576925499`, compte `youyou31110` (ID 941826283), vérifié dans Studio
avant toute publication (`StudioService:GetUserId()` → 941826283 youyou31110).

Légende : ✅ **réel** = exécuté par le vrai `ProfileService` contre le vrai DataStore Roblox de
l'expérience de test · 🧪 **simulé** = Lune ou stockage mémoire · ⛔ non exécuté.

## 1. Comment le test a été fait

- Place `datastore-check.project.json` (jeu + contrôle) publiée sur l'expérience privée, accès
  de Studio aux services API activé **pour cette expérience seulement**.
- Exécution dans Roblox Studio (dans la VM, piloté sans la souris ni le clavier de l'hôte), mode
  « Exécuter » : le serveur de Studio appelle les **vrais** DataStores de l'expérience.
- DataStore **dédié** `MimicHunters_DataStoreCheck_v031`, clés `check_<exécution>_<n>` avec
  `n` négatif (impossible pour un joueur), aucune suppression. Aucun profil de joueur touché.
- « Deux serveurs » = deux instances de `ProfileService` avec des `jobId` différents dans le
  même serveur : même DataStore, mêmes verrous, mais pas deux machines Roblox distinctes.

## 2. Exécutions

| Exécution | Résultat | Remarque |
|---|---|---|
| `c8231a47` | 8/9 | scénario 5–9 en échec : **défaut du test**, pas des données (comparaison de deux chaînes `HttpService:JSONEncode`, dont Roblox ne garantit pas l'ordre des clés). Comparaison remplacée par un contrôle champ par champ qui nomme la première différence. |
| `f489bdc3` | **9/9** | même place, test corrigé : 5–9 « exemplaires, vitrines, styles, cosmétiques, objectifs identiques » |
| `0109ef9a` | **11/11** | + libération des verrous et écriture déjà appliquée (P7) — captures [01](screenshots/v032/01_vrai_datastore_11sur11_debut.jpg), [02](screenshots/v032/02_vrai_datastore_11sur11_fin.jpg) |

## 3. Scénarios

| Scénario demandé | Réel | Simulé | Détail (exécution 0109ef9a) |
|---|---|---|---|
| Création d'un profil | ✅ | 🧪 | 1 : profil vide, verrou posé, statut Ready |
| Écriture et lecture via UpdateAsync | ✅ | 🧪 | tous les scénarios (le service n'utilise que `UpdateAsync`) |
| Sauvegarde et rechargement | ✅ | 🧪 | 2–4 : sauvegarde, libération, rechargement par un autre service |
| Plusieurs exemplaires | ✅ | 🧪 | 5–9 : 3 exemplaires de la même espèce |
| Mutations | ✅ | 🧪 | 5–9 : Standard, Chromatic, Spectral identiques |
| Favoris | ✅ | 🧪 | 5–9 |
| Six vitrines | ✅ | 🧪 | 5–9 : table des 6 vitrines (3 remplies, 3 vides) identique |
| Personnalisations | ✅ | 🧪 | 5–9 : style de mur |
| Objectifs (et cosmétiques) | ✅ | 🧪 | 5–9 |
| Migration des anciens profils | ✅ | 🧪 | 10 : profil V0.2 stocké → v3, 3 exemplaires |
| Verrous de session | ✅ | 🧪 | 1, 13 |
| Concurrence entre deux services | ✅ | 🧪 | 13 : le second est bloqué (Locked) |
| Réponse à une écriture appliquée | ✅ | 🧪 | P7 : « Saved puis Saved », pas de verrou perdu |
| Refus de remplacer un profil corrompu | ✅ | 🧪 | P4 : « Corrupt », l'enregistrement reste intact |
| Reprise d'un verrou expiré | ✅ | 🧪 | 14 : verrou de 400 s repris |
| Libération des verrous | ✅ | 🧪 | « Libération » : verrou retiré, données intactes |
| Verrou perdu | ✅ | 🧪 | 15 : plus aucune écriture, serveur prévenu |
| Fermeture (BindToClose) | ⚠️ partiel | 🧪 | 16 : 3 sessions libérées en 0,5 s par `closeAll` ; vrai arrêt d'un serveur publié non provoqué |
| Erreur temporaire / panne prolongée | ⛔ | 🧪 | non provocables sur un vrai DataStore |
| Deux vrais serveurs Roblox | ⛔ | 🧪 | exige deux serveurs publiés (protocole : PLAYTEST_PLAN.md) |

## 4. Le vrai jeu sur le vrai DataStore (session Studio, pas un serveur publié)

Place jouable (sans le contrôle) publiée sur l'expérience privée, puis session « Test » de
Studio : le journal du serveur indique `profils : DataStore MimicHunters_Profiles_v2_STUDIO`
(vrai DataStore de l'expérience, magasin réservé à Studio ; un serveur publié utilise
`MimicHunters_Profiles_v2`, de la même expérience privée).

| Étape | Résultat |
|---|---|
| Session 1 : 3 exemplaires accordés par le serveur, un favori, 3 vitrines, mur « night » | `S941826283-1/chairy/Standard/111`, `-2/chairy/Chromatic/222` (favori), `-3/posty/Spectral/333` ; vitrines 1–3 ; [capture](screenshots/v032/03_jeu_vrai_datastore_avant.jpg) |
| Fin de session (départ du joueur + fermeture du serveur) | sauvegarde par le vrai `ProfileService` |
| Session 2 (nouveau serveur Studio) | profil `Ready`, **les 3 exemplaires identiques** (espèce, mutation, graine, favori), mêmes vitrines, même mur, `totalCaptures 3`, `nextSerial 4` ; [capture](screenshots/v032/04_jeu_vrai_datastore_apres_nouvelle_session.jpg) |

Les exemplaires ont été accordés par un script de test du serveur (pas capturés à la main) :
c'est le chemin de sauvegarde et de rechargement qui est vérifié ici, pas le gameplay.

## 5. Limites

- Tout a été exécuté depuis **Roblox Studio** (serveur local de Studio) avec le vrai DataStore ;
  **aucun serveur publié** n'a été rejoint : la VM n'est pas connectée à Roblox dans son
  navigateur, et je n'entre aucun mot de passe.
- Deux « serveurs » = deux services dans le même processus ; pas deux machines.
- Quotas et latence : ceux d'une exécution Studio (budget d'écriture de Studio).
- Pannes réelles du DataStore : jamais provoquées (non contrôlables).
