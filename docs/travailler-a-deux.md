# Travailler a deux (Git + Rojo + Team Create)

Decide le 2026-11-27. Deux devs : **VadymVDM** et **Natixe**.

## Le principe

- **Le code** (`src/`) vit dans Git : GitHub `VadymVDM/usine`, branche `main`. C'est la reference.
- **Rojo ne relie pas les PC.** Chacun lance son Rojo chez lui (`start-rojo.bat`, port 34850) et le
  connecte a SON Studio. Le code passe d'un PC a l'autre par Git, jamais par Rojo.
- **La carte** (Workspace, ServerStorage, `ReplicatedStorage.FruitAssets`) n'est pas dans Git :
  elle vit dans la place partagee Team Create "Mon usine de jus" (placeId 93027930223227).
- **Chacun code dans sa propre place.** C'est ce que conseille la doc de Rojo (Recommended
  Workflows : "each programmer on a project have their own place to work in"). Deux Rojo connectes
  en meme temps dans la meme place Team Create s'ecrasent le code l'un de l'autre.

## Les deux places

| Place | Sert a | Rojo |
|---|---|---|
| Place partagee (Team Create, dans le cloud) | construire la carte, tester ensemble, publier | pas connecte en continu : seulement pour "mettre le code a jour" (plus bas) |
| Place perso : `places/<pseudo>.rbxl` (fichier sur ton PC) | coder et tester ton code | connecte pendant que tu codes |

Les `.rbxl` sont ignores par Git (`.gitignore`) : ta place perso reste sur ton PC.

**Creer sa place perso (une fois, puis pour recuperer une nouvelle carte)** : faire `git pull`,
ouvrir la place partagee, mettre son code a jour (section plus bas), puis enregistrer une copie en
fichier `places/<pseudo>.rbxl` depuis le menu Fichier de Studio. Ensuite, ouvrir ce fichier.

Dans la place perso, pas d'acces aux DataStores de Roblox (fichier local, pas publie). Pour tester
la sauvegarde des joueurs ou a 2 joueurs, utiliser la place partagee.

## Chaque jour

1. **Recuperer** : `git pull --rebase` (ou GitHub Desktop : Fetch origin, puis Pull origin).
2. Lancer `start-rojo.bat`, ouvrir sa place perso, puis Rojo > Connect `localhost:34850`
   **en mode Edit** (jamais pendant un Play : erreur "Http requests can only be executed by game server").
3. Coder dans `src/` (VS Code ou un agent IA). Tester dans sa place perso.
4. **Envoyer** souvent, par petits morceaux : commit, `git pull --rebase`, puis `git push`.
   Dire a l'autre ce qui a ete envoye.
5. Le travail de l'autre arrive par `git pull`. Si Rojo tourne, il met a jour Studio tout seul.
   **Seulement le code de `src/`** (et il se voit surtout au Play). Ce qui est dans `Workspace` ou
   `ServerStorage` ne passe jamais par Git ni Rojo (voir "La carte" plus bas).
6. Pour voir toute l'usine en mode Edit : onglet Plugins > bouton **Factory Preview**
   (installe par `start-rojo.bat` ; rouvrir la place apres une mise a jour du bouton).
   Doc : `docs/systems/apercu-edit.md`.

## Quand un seul des deux travaille

Avec Team Create, la place partagee garde tout entre deux sessions (sauvegarde automatique dans le
cloud). Celui qui est seul peut donc travailler directement dedans, Rojo connecte.

**En arrivant**
1. `git pull --rebase` **avant** de connecter Rojo. Sinon Rojo remet dans la place une vieille version
   du code et efface ce que l'autre y avait synchronise.
2. `start-rojo.bat`, ouvrir la place partagee, Rojo > Connect (mode Edit), accepter.
3. Si l'autre est connecte (son avatar en haut a droite de Studio) : Rojo > Disconnect et passer
   dans sa place perso pour coder (section "Chaque jour").

**En partant**
1. Code : commit + `git push`.
2. Studio : Fichier > Sauvegarder sur Roblox (force la sauvegarde de la carte), puis Rojo > Disconnect.
3. Prevenir l'autre en une ligne : ce qui a change (code et carte).

## Rojo dit "Could not sync because user 'X' is already syncing"

C'est le verrou de Rojo dans Team Create : a chaque Connect, le plugin Rojo ecrit son joueur dans
`ServerStorage.__Rojo_SessionLock`, et ne le rend qu'au Disconnect. Tant que l'autre est dans la
session avec Rojo connecte (ou s'il a oublie Disconnect), ton Connect est refuse.

- **Le mieux** : demander a l'autre de faire Rojo > Disconnect.
- **S'il n'est pas la** : onglet Plugins > barre "Usine" > bouton **Rojo Unlock**, puis Rojo > Connect.
  - Le bouton vide le verrou s'il appartient a quelqu'un d'autre. S'il est libre ou deja a toi, il le
    dit dans la Sortie et ne touche a rien.
  - **Attention** : ca ne debranche pas le Rojo de l'autre (Rojo ne relit jamais le verrou une fois
    connecte). Tant qu'il ne fait pas Disconnect, ses fichiers peuvent encore ecraser les tiens dans la
    place. Le bouton laisse donc une marque sur le verrou (attribut `UsineUnlock`) : chez l'autre, un
    **bandeau rouge** s'affiche en haut de la vue 3D ("X took over Rojo... Click Rojo > Disconnect"),
    avec un bouton OK. Il faut qu'il ait le plugin UsineTools a jour.
  - Code : `tools/studio-plugin/RojoLock.luau` (installe avec Factory Preview par `start-rojo.bat` ;
    apres une mise a jour, rouvrir la place). Verifie dans le code du plugin Rojo 7.7.1
    (`plugin/src/App/init.lua`).
- Sans le bouton (barre de commande de Studio, mode Edit) :
  `game.ServerStorage.__Rojo_SessionLock.Value = nil` (meme effet, sans prevenir l'autre).

## Mettre le code dans la place partagee (tester ensemble, publier)

Une seule personne a la fois, et on previent l'autre.

1. Les deux ont envoye leur travail. Faire `git pull`.
2. Ouvrir la place partagee, Rojo > Connect (mode Edit), lire l'apercu des changements, accepter.
3. Rojo > Disconnect juste apres.
4. Publier seulement si les deux sont d'accord (et jamais par un agent sans demande explicite).

## Team Create (actif depuis le 2026-11-27, 01:47)

- Avant 01:47 il etait desactive : chaque Studio avait sa propre copie, et les murs `Map.Bounds`
  montes a 800 n'existaient que chez Natixe. Le panneau "Collaborer" listait bien PROVADNIKE_ROBLOX,
  mais ecrivait "La creation d'equipe doit etre activee".
- Pour l'activer (si jamais il faut le refaire) : **Fenetre > Collaboration > Collaborateurs live >
  Activer**. Le bouton "Sauvegarder" du panneau "Collaborer" ne l'active pas.
- Si Studio repond "Le serveur est occupe et ne peut pas traiter ta demande d'importation" a chaque
  sauvegarde alors que status.roblox.com est vert : fermer **toutes** les fenetres Studio et rouvrir
  la place (session Studio bloquee ; c'est ce qui a debloque le 2026-11-27).
- Maintenant : les changements de carte faits dans la place partagee arrivent chez l'autre en direct.
  Rojo connecte dans la place partagee ecrit aussi chez l'autre : Connect, accepter, Disconnect.

## La carte

- La carte se modifie **seulement dans la place partagee**. Ce qui est construit dans une place
  perso est perdu (ce n'est pas dans Git).
- Les scripts de `tools/build-map/` et `tools/build-assets/` (hors Rojo) se lancent dans la place
  partagee.

## Regles Git

- Ne pas travailler en meme temps sur le meme fichier : se dire avant qui touche quel systeme.
- Journal : chacun ajoute ses entrees en bas du fichier du jour, sans toucher a celles de l'autre.
- Si `git pull` annonce un conflit : ne rien forcer, demander a l'agent ou a l'autre.
- Jamais `git push --force` sur `main`.
