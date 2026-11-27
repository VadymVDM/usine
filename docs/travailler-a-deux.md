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

## Mettre le code dans la place partagee (tester ensemble, publier)

Une seule personne a la fois, et on previent l'autre.

1. Les deux ont envoye leur travail. Faire `git pull`.
2. Ouvrir la place partagee, Rojo > Connect (mode Edit), lire l'apercu des changements, accepter.
3. Rojo > Disconnect juste apres.
4. Publier seulement si les deux sont d'accord (et jamais par un agent sans demande explicite).

## Attention : Team Create pas actif (verifie le 2026-11-27)

- La place partagee n'est **pas** en Team Create : en Edit, `Players` est vide (aucun collaborateur) et
  une fenetre ouverte a neuf ne voit pas les changements non sauvegardes d'une autre fenetre
  (murs `Map.Bounds` a 800 dans la fenetre de Natixe, a 80 dans une fenetre ouverte apres).
- Consequence : chaque Studio a sa propre copie. Un changement de carte n'existe pour l'autre
  qu'apres **Fichier > Sauvegarder sur Roblox**, et **le dernier qui sauvegarde ecrase l'autre**.
- A faire : activer Team Create (bouton "Collaborer" en haut a droite de Studio). En attendant :
  une seule personne modifie la carte a la fois, sauvegarde sur Roblox, previent l'autre, qui
  ferme et rouvre la place.

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
