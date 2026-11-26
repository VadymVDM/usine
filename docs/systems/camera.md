# Systeme : Camera (objets transparents devant le joueur)

**Statut :** fonctionne (playtest Studio PC le 2026-11-20 : arbre, mixeur, arbre de la carte, mur ;
telephone pas teste ; reglage 0.8 pas revu en jeu)
**Derniere mise a jour :** 2026-11-23

## Role

Demande du 2026-11-20 : "la camera peut passer a travers l'arbre" et "quand la camera est derriere
un objet, l'objet devient transparent". Quand un **objet** (arbre, machine, comptoir, arbre de la
carte) est entre la camera et le joueur, il devient transparent en fondu et la camera passe au
travers au lieu de sauter devant. Les **murs, sols, plafonds et escaliers** ne changent pas : la camera
s'arrete devant comme avant (sinon on verrait sous le sol ou a travers le plafond de l'etage).
Tout est cote client, pour ce joueur seulement : rien n'est envoye au serveur.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/client/Controllers/CameraFadeController.luau` | client | Detection des objets entre la camera et le joueur, fondu, remise a l'etat d'origine |
| `src/shared/Config/CameraFade.luau` | partage | Reglages (transparence, durees, epaisseur des lignes) et dossiers qui contiennent des objets |
| `src/client/Controllers/SpawnCameraController.luau` | client | Camera tournee vers l'usine a l'apparition (connexion, retour, mort) |
| `src/shared/Config/SpawnCamera.luau` | partage | Reglages de la camera a l'apparition |
| `src/server/Services/TreeService.luau` | serveur | `prepareBody` : l'arbre pose n'a plus de collision (voir `fruits.md`) |

## Fonctionnement

- **Objet** = un `Model` range dans un dossier de la config : `Tree`, `Production`, `Counter`,
  `Machines` de chaque etage (`Bases.BaseN.Floors.FloorK`), et `Workspace.Map.Decor.Trees`. On
  descend dans les sous-dossiers (ex. `Production.Blenders.Blender1`) ; une piece seule n'est pas un
  objet (bordure, herbe, caisses). Un objet plus plat que 1.5 stud est ignore (tapis, dalles).
- **Pas efface** : `Building` (murs, sols, poutres), `Stairs`, `Boards`, `Looks`, `Donations`
  (panneaux couverts de texte SurfaceGui, qui ne peut pas devenir transparent), la route, les
  collines, l'annexe, les PNJ et les fruits au sol.
- **Chaque image**, juste apres la camera de Roblox (`BindToRenderStep`, priorite Camera + 1) :
  deux lignes epaisses, tete -> camera (prolongee de 2 studs derriere la camera) et bassin ->
  camera. Test geometrique sur les boites des pieces (marche aussi pour les pieces `CanQuery = false`
  comme le feuillage). Un objet touche s'efface **en entier** (80 % transparent, 0.15 s) ; il
  redevient opaque 0.25 s apres ne plus etre touche (0.35 s de fondu).
- **Pourquoi la camera passe au travers** : la camera de Roblox (Poppercam, dans
  `StarterPlayer.PlayerModule`, plus modifiable par le jeu) ne s'arrete pas devant une piece sans
  collision ni devant une piece transparente a plus de 25 %. L'arbre n'a plus de collision. Une
  machine fait d'abord avancer la camera ; elle est alors juste derriere la camera, dans la marge de
  2 studs : elle s'efface tout de suite au-dessus de 25 % et la camera repart a sa distance.
- **Vue a la 1re personne** (camera a moins de 1.5 stud de la tete) ou camera `Scriptable`
  (cinematique) : rien n'est efface.
- **Partage de `LocalTransparencyModifier`** avec d'autres scripts (machines fantomes
  `GhostVisibilityController`, decor par niveau `LevelLookController`, jus du mixeur
  `BlenderFxController`) : une piece deja cachee (>= 0.99) n'est jamais touchee ; si un autre script
  change la valeur pendant le fondu, on ne touche plus cette piece. Les `Decal` / `Texture` suivent
  le fondu. Les `SurfaceGui` de l'objet sont coupees pendant le fondu et rallumees apres (meme
  regle : rallumee par un autre script = plus a nous).
- Boites des objets recalculees au plus toutes les 0.5 s (ajout / retrait de pieces, machines qui
  se construisent, arbre qui grandit). StreamingEnabled : les dossiers peuvent arriver tard
  (`FloorWatch`, `WaitForChild`).

## Camera a l'apparition (2026-11-23)

Demande : "quand on join ou rejoin le serv, la cam doit etre vers l'usine et pas vers l'exterieur".
Le moteur fait apparaitre le personnage sur la SpawnLocation (camera placee derriere lui la), puis
le serveur (`BaseService` + `FloorService.spawnCFrame`) le pose dans sa base face a l'interieur de
l'usine ; la camera de Roblox gardait son ancien angle et regardait dehors.
`SpawnCameraController` : a chaque apparition, aligne la camera derriere le personnage (dans le sens
ou il regarde), puis guette pendant `WatchSeconds` (15 s) un saut de position de plus de
`TeleportDistance` (15 studs) et realigne a ce moment. Camera `Scriptable` (cinematique) : rien
(la cinematique replace la camera elle-meme a la fin). Les ascenseurs / teleports d'etage apres ces
15 s ne sont pas touches.

## Remotes

Aucun.

## Donnees sauvegardees

Aucune.

## Configuration

`src/shared/Config/CameraFade.luau` : `Transparency` (0.8 ; 0.7 essaye : voile vert quand la camera
est dans le feuillage), `FadeOutSeconds`, `FadeInSeconds`, `HoldSeconds`, `HeadRadius`, `BodyRadius`,
`PopMargin`, `MinHeight`, `FloorFolders`, `MapFolders`. Ajouter un dossier d'objets = l'ajouter a
`FloorFolders` (dossier direct d'un etage) ou `MapFolders` (chemin depuis `Workspace.Map`).

## Tests (Studio, playtest)

- Arbre niveau 10 entre la camera et le joueur : les 31 pieces a 0.70 (reglage d'alors), camera a 20
  studs (zoom force avec `CameraMin/MaxZoomDistance = 20`).
- Mixeur 1 : camera derriere le mixeur, reste a 20 studs (avant : elle sautait devant) ; pieces
  visibles a 0.70, son panneau (SurfaceGui) coupe ; les 10 pieces deja cachees (decor par niveau)
  restent a 1. Camera tournee ailleurs : tout revient a 0, panneau rallume.
- Mur de l'usine : la camera s'arrete devant (12.7 studs au lieu de 20), le mur reste opaque.
- Arbre rond de la carte : tronc + feuilles a 0.70, camera a 20 studs.
- `require` du module depuis la barre de commande = copie separee : `CameraFadeController.Stats()`
  n'y voit rien ; lire `LocalTransparencyModifier` des pieces a la place.

## Problemes connus / a faire

- Camera a l'apparition : testee en playtest Studio PC (connexion, etage 10) ; pas testee sur mort / respawn, telephone, en ligne.

- Pas teste sur telephone (cout par image : quelques centaines de tests de boites, normalement leger).
- Une machine qui fait avancer la camera peut la faire "sauter" une seule image avant de s'effacer.
- Camera sous le tapis roulant (derriere les mixeurs) : on voit le dessous du tapis (il n'est pas
  entre la camera et le joueur, donc pas efface). Acceptable pour l'instant.
- L'arbre est en train d'etre refait par une autre session (arbre genere par code) : il doit rester
  un seul `Model` `Body` sous `Floor.Tree`, sans collision.
