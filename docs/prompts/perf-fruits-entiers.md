# Prompt : cacher les fruits entiers loin de la caméra (2026-11-27)

Un prompt = un nouveau chat. Suite du travail de performance mobile du 2026-11-27
(`docs/perf-mobile.md`). Décision d'Adam : « on va les cacher, mais seulement d'un peu plus loin,
comme ça on est sûr que plus personne ne peut les voir ».

---

```
Projet D:\Usine (tycoon Roblox "Mon usine de boissons"). Lis AGENTS.md, puis docs/perf-mobile.md
EN ENTIER (mesures, corrections déjà faites, section "Relancer le test") et le dernier fichier de
docs/journal/. Charge les skills roblox-collaboration-mode, roblox-performance, roblox-studio-mcp
et roblox-luau-patterns avant de coder.

BUT
Alléger une tour au maximum sur téléphone modeste en rendant invisibles, côté client, les FRUITS
ENTIERS quand ils sont loin de la caméra. Adam veut une distance assez grande pour que personne ne
puisse voir un fruit disparaître ou apparaître. Si à cette distance le gain est nul, on ne le
fait pas : tu le dis, chiffres à l'appui, et tu t'arrêtes.

CE QU'ON SAIT DÉJÀ (mesuré le 2026-11-27, Studio PC)
- Une tour au maximum a ~980 unions : ~580 mini fruits de gobelet (déjà cachés à plus de 60 studs)
  et ~400 fruits entiers. Un fruit entier = un Model créé par FruitModels.CreateFruit
  (src/shared/FruitModels.luau), dont la pièce "Body" est une union de 3 300 à 4 500 triangles.
  Hauteur d'un fruit : FruitModels.FruitSize = 1.9 stud.
- En qualité téléphone (niveau 3), les unions d'UNE tour vue de derrière font encore 770 000
  triangles (PerfClient.Breakdown), et les mini fruits n'y comptent pour rien : ce sont les fruits
  entiers. Repère Roblox : ~800 000 triangles et ~600 appels de dessin pour toute la scène.
- Piège déjà rencontré : cacher les mini fruits n'a RIEN donné en qualité 3 (Roblox ne les
  dessinait déjà plus de loin), seulement en qualité 21. Donc on mesure AVANT de coder.
- Les 400 fruits de la tour de test sont ceux de l'aperçu (dossier PreviewFruits, "Tree full!" sur
  10 étages). Vérifie dans le vrai jeu combien de fruits au sol un étage peut avoir au maximum
  (Config + TreeService) : le gain réel peut être plus petit que sur l'aperçu. Dis-le.

MODÈLE À COPIER
src/client/Controllers/WorldDetailController.luau fait déjà la même chose pour 3 choses : effets de
rareté, PNJ (tag Npcs.FarHideTag) et mini fruits (tag FruitModels.MiniFruitTag). Même recette :
- un tag CollectionService posé à la création (ici dans FruitModels.CreateFruit) ;
- le contrôleur suit les objets tagués QUI SONT DANS LE WORKSPACE (pas les fruits des fenêtres
  d'interface : Index, inventaire, menus, qui passent aussi par CreateFruit) ;
- toutes les 0.3 s, distance caméra -> objet ; au-delà : Transparency = 1 en local sur les pièces
  (valeur d'avant gardée, remise en s'approchant, seulement si personne d'autre n'y a touché) ;
  marge pour ne pas clignoter ; nombre de masquages limité par passage ;
- un objet sorti par le streaming ou détruit est d'abord remis visible ;
- réglages dans src/shared/Config/Gameplay.luau, jamais en dur ;
- Transparency, PAS LocalTransparencyModifier (d'autres contrôleurs l'animent).
Pour les PNJ, la hauteur compte 2.5 fois plus que la distance au sol (NpcVerticalWeight) : un
objet 2 étages plus haut est derrière des plafonds. Regarde si la même idée sert ici : elle permet
de garder une grande distance au sol (rien ne disparaît sous les yeux du joueur) tout en cachant
les étages qu'il ne peut pas voir.

ÉTAPES
1. MESURE D'ABORD, sans toucher au code. Play, puis
   PerfServer.Setup({ 2, 3, 5, 6 }) et PerfClient.Game() DEUX fois (garder la 2e mesure). Ensuite
   une mesure A/B dans le même Play, par execute_luau côté client : pour plusieurs distances
   (par exemple 120, 180, 250, 350 studs, avec et sans le poids de la hauteur), mets
   Transparency = 1 sur les pièces des fruits entiers plus loin que la distance, relève triangles
   et appels de dessin (Stats.SceneTriangleCount / SceneDrawcallCount) en qualité 21, 3 et 1 sur
   les vues du script (route, tour de derrière, vue aérienne, devant le rez-de-chaussée, dans un
   étage), puis remets tout. Fais un tableau distance -> gain.
2. CHOISIS LA DISTANCE. Règle d'Adam : personne ne doit pouvoir voir un fruit disparaître. Un fruit
   de 1.9 stud fait environ 10 pixels de haut à 150 studs et 5 pixels à 300 studs sur un écran de
   1080 pixels de haut : pars de là, et vérifie à l'œil avec 2 captures (mode Edit sur l'aperçu,
   ou Play si la fenêtre Studio est au premier plan) à la distance choisie. Prends la plus grande
   distance qui garde l'essentiel du gain en qualité 3. Si aucune distance "invisible" ne donne de
   gain en qualité 3 : STOP, rapport à Adam, pas de code.
3. CODE la correction (tag dans CreateFruit, section dans WorldDetailController, réglages dans
   Gameplay). Attention à ce qui touche déjà les fruits :
   - effets de rareté (Attachment "RarityFx" dans Body, déjà coupés à 60 studs) : ne pas les casser ;
   - ramassage (touche E, TreeService, ProductionService), fruits qui tombent de l'arbre, fruits
     portés par le joueur et les employés (NpcRig), plateaux (TrayController), mixeurs
     (BlenderFxController), Fx/Reveal : un fruit caché doit revenir intact, et un fruit proche ne
     doit JAMAIS être caché ;
   - cherche qui d'autre écrit Transparency sur les pièces d'un fruit avant de choisir le moyen.
4. VÉRIFIE avec le script (tools/perf) : PerfClient.Game() deux fois, Breakdown(), et un contrôle
   par execute_luau : fruits proches tous visibles, fruits loin tous cachés, 0 erreur de script
   (LogService filtré). Vérifie aussi dans le vrai jeu (pas seulement l'aperçu) : ramasser un
   fruit, le porter, le poser, s'éloigner et revenir.
5. FIN : PerfClient.Finish(), Stop, PerfServer.EditCheck() en mode Edit. Mets à jour
   docs/perf-mobile.md (tableau avant / après, distance choisie et pourquoi, valeurs de référence
   de "Relancer le test"), docs/systems/fruits.md, le journal du jour. rojo build, puis commit sur
   main (pas de push).

RÈGLES
- Ne touche pas à la sauvegarde du profil de test, ne publie rien, ne lance et ne ferme aucune
  fenêtre Studio. L'aperçu Workspace._Preview est celui d'Adam : n'y touche pas.
- Vérifs MCP compactes : un execute_luau qui renvoie un résumé court, peu de captures.
- Un appel execute_luau qui se termine remet le type de caméra du début de l'appel : tiens la
  caméra par BindToRenderStep pendant une mesure (voir holdCamera dans tools/perf/perf-client.luau)
  et remets Custom à la fin.
- Sois honnête dans le rapport : ce sont des charges mesurées sur PC, pas des FPS de téléphone.
  Dis ce qui est vérifié en Play et ce qui ne l'est pas.
- Réponds à Adam en français, court, avec le tableau avant / après et la distance retenue.
```
