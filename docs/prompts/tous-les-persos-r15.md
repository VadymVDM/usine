# Prompt : passer tous les PNJ en R15 (2026-11-27)

Un prompt = un nouveau chat. Le Fruit Picker est deja en R15 (commit 372cc52) : il sert de modele.

---

```
Projet D:\Usine (tycoon Roblox). Lis AGENTS.md en entier et suis-le (skills Roblox, doc, journal,
build). Lis docs/systems/ameliorations-employes.md (section "Fruit Picker en R15") et
docs/systems/clients.md, puis le dernier fichier de docs/journal/.

But : passer TOUS les PNJ en R15, comme les joueurs et comme le Fruit Picker (deja fait) :
  1. Blender Operator (Operator1..4)
  2. Waiter
  3. Clients (CustomerController, rigs ReplicatedStorage.NpcTemplates.Customer<n>)
Resultat attendu : meme marche / course / attente que les joueurs, et AUCUN geste perdu ni casse.

Ce qui existe deja (a reutiliser, ne pas reinventer) :
- src/shared/Config/Npcs.luau : `Employees.<role>.r15`, `AnimationsR15` (Idle / Walk / Run).
- src/server/Lib/NpcRig.luau : `buildRig(..., r15)`, tablier sur UpperTorso, `startR15Walk`
  (melange marche + course comme le script Animate), `npc.r15`.
- src/client/Controllers/CarryPoseController.luau : bras R15 (CFrame.Angles(+x) = bras vers
  l'avant), et le modele de geste "attributs <Nom>Start / <Nom>Time + pose dessinee par le client"
  (Pick, Dump). C'est la bonne methode : pas de tween serveur image par image.

Ce qui est encore ecrit pour R6 (a porter) :
- NpcRig.Press (operateur appuie sur le bouton) et NpcRig.Deposit (operateur pose les jus sur la
  table, NpcRig.HandsPoint) : tweens du C0 des epaules R6 "Right Shoulder" / "Left Shoulder"
  (shoulderRest). A refaire en R15, idealement en geste client (attributs PressStart/PressTime,
  DepositStart/DepositTime) dans CarryPoseController. Garder les memes durees
  (NpcRig.PressReachSeconds, DepositTurnSeconds, CupPopStagger) : BlenderFxController et
  WorkerService.onPour en dependent (gobelets qui sautent des mains, PopDelay).
- Waiter : plateau de jus sur la tete (attribut HandJuices, HandStackController / HandStack.WorldSlot).
  Verifier que le plateau et les gobelets suivent bien la tete R15.
- CustomerController : `Npcs.Animations` (R6) + `Npcs.WalkAnimSpeed` pour la vitesse, et
  `FindFirstChild("Torso")`. Passer aux animations R15 avec le meme melange marche / course que
  NpcRig.startR15Walk (clients a Npcs.CustomerWalkSpeed = 10). Les rigs clients sont crees par
  NpcRig.Prepare (boucle CustomerOutfits) : leur passer r15. Les cheveux (accessoires) doivent
  rester bien places.
- Cherche tout le reste : grep "Torso", "Right Arm", "Right Shoulder", "Npcs.Animations",
  "WalkAnimSpeed", "HumanoidRigType.R6" dans src/. IntroController gere deja R6 et R15 : n'y touche
  que si c'est casse.
- Quand plus rien n'est R6 : retirer le code et la config R6 devenus inutiles (Npcs.Animations,
  WalkAnimSpeed, le drapeau r15 par role) seulement si plus rien ne les utilise.

Methode :
- Echantillon d'abord : fais l'operateur en premier, montre-moi une capture du geste Press et du
  geste Deposit en Play, et attends mon OK avant le Waiter et les clients.
- Tests en Play Studio via MCP : passe par game.ServerStorage.Debug.Call (voir DebugService ; un
  require depuis la barre de commande cree une copie separee des modules). Ex. :
  Call:Invoke("Tree", "Drop", <NomJoueur>, 8), Call:Invoke("Production", "Do", <NomJoueur>, "Blend1").
  Pour voir un geste : place le perso du joueur pres du PNJ et fais une video_capture, puis
  extrais des images avec ffmpeg (deja installe).
- Apres les captures : remettre workspace.CurrentCamera.CameraType = Fixed en mode Edit.
- Ne change rien au rythme du jeu (vitesses, delais, revenus).

Fin : doc du systeme a jour (ameliorations-employes.md, clients.md), entree de journal,
`rojo build default.project.json -o test-build.rbxl` OK puis supprime le fichier, commit sur main
sans push. Dis-moi clairement ce qui est verifie en Play et ce qui ne l'est pas.
```
