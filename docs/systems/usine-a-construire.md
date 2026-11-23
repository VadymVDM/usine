# Systeme : Usine a construire (profil neuf) et revelation progressive

**Statut :** fonctionne (playtest Studio PC a 1 joueur le 2026-11-21 ; telephone et 2 joueurs pas testes)
**Derniere mise a jour :** 2026-11-22

## Role

Un profil NEUF arrive dans une usine vide (etage 1 : murs, sol, allees, panneaux de zone). Il ne voit
au sol qu'une etape a la fois, sur son chemin : **Plant tree** -> **Build shelf** ->
**Build blender** -> **Open shop**. Etapes 2-4 : un pad vert **FREE**, marcher dessus construit la
partie de l'usine, gratuitement. Etape 1 "Plant tree" (depuis le 2026-11-22 soir) : **pas de pad**,
on appuie sur **E au milieu de la pelouse**, la ou poussera l'arbre (`Tree.TreeRoot`), pour planter
l'arbre niveau 1 tenu en main depuis la cinematique (`cinematique.md`). Chaque etape n'apparait que quand c'est son tour dans le
tutoriel (`Setup.PadGates`, voir `tutoriel.md`).
Tout le reste (pads, panneaux, mixeurs) n'apparait que quand il devient utile, avec une animation
"pop". Guidage : `tutoriel.md` (objectif, ligne de chevrons, fleche).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/shared/Config/Setup.luau` | partage | Les 4 etapes (id, texte, position du pad), ce que chaque etape construit (`Build`), fait apparaitre (`Reveal`), etape de chaque amelioration (`UpgradeStep`), mixeur 1 a construire (`UpgradeBuild`), rythme |
| `src/server/Services/SetupService.luau` | serveur | Seul a ecrire `Data.Setup`. Pads FREE (contact 10 / s), etats fantome / cache / normal, attribut d'etage `Lv_Setup`, `Allows(etage, k)`, `OnStepDone` |
| `src/server/Lib/Ghost.luau` | serveur | Groupe de pieces en fantome bleu (`Ghost`), cache (`Hidden`) ou normal ; attributs `SetupGhost` / `SetupHidden` sur la racine |
| `src/client/Controllers/SetupController.luau` | client | Animations dans SA base : construction piece par piece (`BuildStamp`), pop (`RevealStamp`, machine `Hidden` -> visible, pad vert qui reapparait), arbre qui pousse (`Tree.PlantStamp`), etincelles du pad fait (`DoneStamp`), contour bleu des fantomes |
| `src/client/Fx/Reveal.luau` | client | `Pop` (grossit depuis le sol avec rebond, ~0.5 s) et `Build` (pieces qui tombent) |
| `tools/build-map/02l-floor-setup.luau` | Studio | Cree `FloorTemplate.Setup` (4 pads FREE, sans Neon) |
| `tools/build-map/02g-base-boards.luau` | Studio | Panneaux Conveyor, Juice Table, Customers, Fruit Picker en `HideWhenLocked` |

Branchements dans les autres services (une ligne chacun, `SetupService.Allows`) : TreeService (arbre
fantome, pas de chute, pommes au pad), ProductionService (Drop Fruits >= 2, mixeur 1 et Take Juices
>= 3, lattes du tapis), CustomerService (comptoir, pads et clients >= 4), PassPadService (pads Robux
>= 4), UpgradeService (pads / panneaux / machines). Client : GhostVisibilityController (fantomes et pads
FREE caches chez les autres), MachineFxController (pas d'etiquette ni de contour sur une machine
`Hidden`), LevelLookController (pop des panneaux et des pads de decor).

## Fonctionnement

| Etape (pad) | Construit (invisible avant) | Fait apparaitre |
|---|---|---|
| 1. Plant tree (touche E sur `Tree.TreeRoot`, centre de la pelouse x 87, z 116 ; pad cache) | arbre (pousse 1.4 s, puis 5 pommes tombent) ; l'arbre niveau 1 quitte les mains | pad Upgrade Tree |
| 2. Build shelf (x 57, z 112) | etagere, caisses, plancher, tapis | pad Drop Fruits, panneau Conveyor, pad Fruit Picker |
| 3. Build blender (x 8.5, z 86.5) | mixeur 1, table a jus | pad Take Juices, panneau du mixeur 1, pad Operator 1, mixeur 2 en bleu |
| 4. Open shop (x 52, z 30, sur l'allee) | comptoir, tas d'argent, MONEY / HOUR | pads Drop Juices, Collect Cash, Instant Sell, Auto Collect, Billboard, panneaux Customers et Juice Table, pad Waiter ; les clients arrivent |

- **Pas de fantome bleu avant un pad FREE** (demandes du 2026-11-21 : "le transparent c'est que
  pour les prochaines machines", puis "on decouvre seulement quand on se met sur le pad") : l'arbre,
  l'etagere, le mixeur 1, la table et le comptoir sont invisibles jusqu'a leur pad, puis se
  construisent piece par piece. Le bleu reste pour les machines a acheter (mixeur 2...) ; une
  machine verrouillee (mixeur 3 avant le 2...) est cachee, seule la prochaine est bleue (vaut aussi
  pour les profils existants).
- Panneau Fruit Picker : apparait a l'embauche du Fruit Picker (tuiles `Locked`), pour tous les profils.
- Le pad suivant apparait `Setup.NextPadDelay` (1.3 s) apres la construction.
- Serveur : pad visible + proprietaire + etage 1 + bonne etape + position (PlayerCheck.IsOver) +
  delai 0.5 s. Etape sauvegardee tout de suite.
- Apparition a son tour (`Setup.PadGates`, 2026-11-22) : Build shelf quand le joueur porte 5 fruits
  (ou plateau plein), Build blender quand il a pose ses fruits, Open shop quand il a des jus en main ;
  lu sur les attributs joueur `InvFruits` / `InvMax` / `HandJuices`, reverifie a chaque changement ;
  une fois apparu, le pad reste.
- Touche E (`Setup.Steps[k].prompt`) : ProximityPrompt "Tree / Plant tree" verifie par le serveur
  (proprietaire, etage 1, bonne etape, attribut `Active` du prompt, distance `PromptDistance` + 4,
  delai 0.5 s). Avec `spot` (etape 1 : `Tree.TreeRoot`) le prompt est pose sur cette piece et le
  modele de pad `Setup.PlantTree` reste toujours cache (pas de pop ni d'etincelles de pad). Le
  tutoriel vise cette piece quand le prompt est actif.
- Attribut joueur `HoldingSapling` = (`Setup == 0`) : arbre niveau 1 dans les mains
  (`SaplingController`, bras tendus par `CarryPoseController`).
- Profils existants (migration), plus d'un etage, rebirth, etages 2-10, bases libres : etape 4.
- Animations : client seulement, pas pendant les 2.5 s apres l'arrivee d'un etage, jamais de Neon.

## Remotes

Aucune (contact teste par le serveur 10 fois / s).

## Donnees sauvegardees

`Setup` (entier 0..4). TEMPLATE = 0 (profil neuf). SchemaVersion 6 : migration 5 -> 6 met 4 aux
anciens profils. Sanitize : valeur abimee -> 4 ; plus d'un etage ou rebirth -> 4.

## Configuration

`Config/Setup.luau` : positions, textes ("Plant tree"... "FREE"), `PadGates`, `prompt` + `spot` (touche E de l'etape 1), `PromptDistance`, `PlantText`,
`NextPadDelay`, `TreeGrowSeconds`, `FirstApples` (5 depuis le 2026-11-22), `AppleStagger`.

## Tests (Studio)

```
game.ServerStorage.Debug.Call:Invoke("Setup", "Get" | "Set", "<Nom>", n)       -- etape (Set ecrit la sauvegarde)
game.ServerStorage.Debug.Call:Invoke("Data", "Backup", "<Nom>")                 -- copie du profil (DataStore DebugBackups)
game.ServerStorage.Debug.Call:Invoke("Data", "ResetOnLeave", "<Nom>")           -- profil neuf au prochain lancement
game.ServerStorage.Debug.Call:Invoke("Data", "RestoreBackup", "<Nom>")          -- remet la copie au depart
```

Chrono du 2026-11-21 (Studio PC, marche 20, passes du createur coupes, deplacements par script) :
pad 1 a 9 s, pad 2 a ~17 s, pad 3 a ~28 s, pad 4 a ~42 s, premier billet a ~44 s.

## Problemes connus / a faire

- Telephone et 2 joueurs pas testes (un autre joueur ne doit voir ni fantomes ni pads FREE).
- La vitre d'achat de l'etage 2 (haut de l'escalier) reste visible des le debut.
- Le Lucky Cash peut apparaitre (2 min) meme si la boutique n'est pas encore ouverte.
- Le pad "Build blender" est pres du mur (x 8.5) : le joueur est pousse hors du mixeur quand il se
  construit (normal) ; a revoir si ca gene.
