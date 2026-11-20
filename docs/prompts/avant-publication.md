# Prompts avant la publication (2026-11-21)

Un prompt = un nouveau chat. Ordre conseillé : 1 (commit) → 2 (produits) → 2b (usine à construire,
AVANT le tutoriel) → 3 (tutoriel) → 4 (sécurité) → 5 (checklist de publication, en dernier). Chaque
agent lit d'abord `AGENTS.md` (doc, journal, build).

---

## 1. Commit de l'état actuel (rapide)

```
Projet D:\Usine (tycoon Roblox "Sell a Juice"). Lis AGENTS.md. Beaucoup de fichiers sont modifiés
par plusieurs sessions depuis le dernier commit (280b392). Vérifie que `rojo build default.project.json
-o test-build.rbxl` passe (puis supprime le fichier), regarde `git status`, ne commite PAS api.txt ni
aucun secret, ni test-build.rbxl. Fais UN commit clair en français ("Phase 1b : tour d'étages,
économie revue, Robux, gains hors ligne...") sur une branche `avant-publication`. Ne pousse pas.
Ajoute l'entrée de journal.
```

---

## 2. Créer tous les produits Roblox (rapide)

```
Projet D:\Usine (tycoon Roblox "Sell a Juice"). Lis AGENTS.md et docs/systems/achats-robux.md.
But : créer sur Roblox TOUS les Game Passes et Developer Products du jeu, puis mettre leurs ids
dans la Config. Rien d'autre (pas de changement de prix, pas de nouveau code).

1. Fais la liste complète depuis le code (chaque `passId = 0` / `productId = 0`) :
   - src/shared/Config/Shop.luau : Passes (VIP 149, Cash3x 399, DrinkMaster 249, GreedyCustomers 199,
     SpeedMaster 99, AutoCollect 149, AutoSell 199, SpeedBoost "Waiter Speed x10" 149, Billboard 99,
     Thief 149, RebirthMaster 299) ; Boosts x2 Speed / Money / Luck en 15 min (9) et 30 min (16) ;
     CashPacks (25 / 79 / 199 / 499) ; OfflineDouble (9) ; LimitedOffers (Starter Pack 19, Money Rush
     15, Lucky Hour 29, Customer Rush 15, Mega Cash 99, Triple Boost 35, Rare Rain 19).
   - Config/LuckyCash.luau (29), Config/Rebirth.luau KeepCashProducts (49 / 99 / 199 / 299),
     Config/PlayerUpgrades.luau (3 produits à 9), Config/Donations.luau (5 ... 10000).
   Vérifie qu'il n'en manque aucun (grep "productId\|passId\|ProductId" dans src).
2. Création : si je te donne une clé Open Cloud (permissions game passes + developer products,
   univers 10777527378), crée-les par l'API (skill .claude/skills/roblox-cloud). N'utilise JAMAIS
   api.txt sans que je le dise. Sans clé : donne-moi un tableau prêt à suivre dans le Creator Hub
   (nom anglais, type Pass/Product, prix, description courte en anglais, icône à utiliser depuis
   assets/icons ou D:\Downloads\ICONSPACK), et je te recolle les ids.
3. Mets chaque id au bon endroit dans la Config, `rojo build`, Selene, puis dans un playtest Studio
   clique 3 ou 4 boutons d'achat : la fenêtre Roblox doit s'ouvrir avec le bon prix (pas "coming soon").
4. Mets à jour docs/systems/achats-robux.md (tableau des ids) + journal. Ne publie pas le jeu.
```

---

## 2b. Usine à construire + révélation progressive (avant le tutoriel)

```
Projet D:\Usine (tycoon Roblox "Sell a Juice"). Lis AGENTS.md, docs/README.md, le dernier journal,
docs/game-design.md ("Règle d'or du ressenti"), docs/style.md, docs/systems/ameliorations-employes.md,
chaine-production.md, clients.md, carte-bases.md, tour-etages.md. Skills : roblox-collaboration-mode,
roblox-game-design, roblox-gui, roblox-animation-vfx, roblox-data, roblox-building (FloorTemplate et
tools/build-map vivent dans le .rbxl, pas dans Rojo : modifier par MCP ET reporter dans les scripts
tools/build-map).

But (demande utilisateur, 2026-11-21) : un profil NEUF arrive dans une usine VIDE (murs, sol, zones et
panneaux de zone présents ; aucune machine, aucun pad au sol). Les machines à venir se voient en bleu
clair transparent + contour (règle "acheter = construire"). Le joueur ne voit au sol QUE des pads
verts "FREE", un à la fois, sur son chemin :
 1. "Plant tree"   : la graine, puis l'arbre pousse (1-2 s, particules, son) et 3 pommes tombent
 2. "Build shelf"  : l'étagère + le tapis (un seul pad)
 3. "Build blender": le mixeur 1
 4. "Open shop"    : le comptoir (+ tas d'argent) ; les premiers clients arrivent
Marcher dessus = construire (comme les autres pads, pas de clic), pièce par pièce, rapide : tout
construit en moins de ~15-20 s. Gratuit (0 $) mais vérifié par le serveur, dans l'ordre, sauvegardé.

Révélation progressive (TOUT le reste est caché tant que ce n'est pas utile) :
- plus aucun pad ni panneau au sol au départ à part le pad FREE du moment ;
- "Plant tree" fait apparaître le pad Upgrade Tree ; "Build shelf" le panneau Conveyor + le pad
  Fruit Picker ; "Build blender" le panneau du mixeur 1 + le pad Operator 1 ; "Open shop" les
  panneaux Customers et Juice Table + le pad Waiter + les pads Robux (Auto Sell, Auto Collect...) ;
- embaucher le Fruit Picker fait apparaître son panneau (Picker Speed / Hands) ; acheter le
  mixeur N fait apparaître son panneau ; mixeurs 2-4 visibles en bleu seulement après le mixeur 1.
  Regarde d'abord ce qui existe déjà (LevelLookController : HideWhenLocked, décor LookLevel en
  fondu + étincelles ; GhostVisibilityController) et réutilise-le, ne refais pas.
- CHAQUE apparition (pad, panneau, tuile, machine) a une animation fluide et satisfaisante :
  monte du sol / grossit avec un petit rebond (TweenService, ~0.4-0.6 s), étincelles + son "pop",
  jamais de Neon. Côté client seulement ; le serveur décide de ce qui est débloqué.
- Ne concerne que l'étage 1 d'un profil neuf. Profils existants (déjà des achats), étages 2-10 et
  après un rebirth : usine déjà construite comme aujourd'hui (pas de corvée). Les autres joueurs
  voient l'usine telle qu'elle est (pas de fantômes chez les autres : déjà géré).

Vérifier : profil neuf en playtest Studio (outils Debug pour repartir de zéro, puis REMETTRE le
profil de test), chronométrer (4 pads FREE faits et premier billet avant ~45 s), captures avant /
après chaque étape, un profil existant ne voit rien changer, simulateur téléphone. Plusieurs
sessions utilisent le même Studio : vérifie qu'aucune n'est en playtest avant de lancer / arrêter.
Docs (ameliorations-employes.md, carte-bases.md, game-design.md décision) + journal. Montre-moi les
captures avant de dire fini.
```

---

## 3. Coder le tutoriel du début à la fin

```
Projet D:\Usine (tycoon Roblox "Sell a Juice"). Lis AGENTS.md, docs/README.md, le dernier journal,
docs/game-design.md (sections "Guider le joueur" et "Règle d'or du ressenti"), docs/first-session.md,
docs/systems/chaine-production.md, clients.md, ameliorations-employes.md, tour-etages.md. Skills :
roblox-collaboration-mode puis roblox-game-design (FTUE), roblox-player-psychology, roblox-gui,
roblox-data (sauvegarde de l'étape), roblox-animation-vfx.

But : un tutoriel guidé pour un profil neuf, compréhensible par un enfant de 7 ans qui ne lit pas
l'anglais. Montrer, pas expliquer : AUCUN paragraphe, au plus 2-4 mots par étape en gros (anglais,
blanc avec contour noir), une seule chose à faire à la fois, jamais d'échec possible.

Guidage (décidé) : une file de chevrons lumineux du joueur à la cible (Beam entre une Attachment du
personnage et une sur la cible, texture chevron, FaceCamera, défile vers la cible, un peu transparent,
halo) + une flèche 3D qui rebondit au-dessus de la cible + la cible qui brille (Highlight qui pulse).
Pour un bouton d'interface : le bouton pulse + petite flèche. Pas de barre d'objectif, pas de popup.
Pas de Neon. Visible en vue à la 3e personne et quand le joueur se retourne.

Étapes (déclenchées par l'état du joueur, pas par un minuteur ; texte court entre guillemets) :
 0. Les 4 pads FREE de l'usine à construire (prompt 2b, à faire avant) : "Plant tree", "Build shelf",
    "Build blender", "Open shop" ; la flèche va de l'un à l'autre
 1. Ramasser les fruits au sol en marchant dessus ("Pick up fruits")
 2. Pad Drop Fruits ("Drop fruits")
 3. Mixeur : E ("Blend!")
 4. Pad Take Juices ("Take juices")
 5. Pad Drop Juices au comptoir ("Sell!") → premier client, pluie de billets
 6. Pad Collect Cash ("Collect cash")
 7. Pad Upgrade Tree ("Upgrade tree") → premier achat avant ~40 s
 8. Embaucher le Fruit Picker ("Hire")
 9. Operator du mixeur 1 ("Hire")
10. More Customers sur le panneau Customers
11. Waiter ("Hire") → l'étage tourne seul
12. Vitre rouge de l'étage 2 quand l'argent approche du prix ("New floor!") → fin du tutoriel
Après : le guidage revient une fois à chaque nouveauté (ascenseur à l'étage 2, rebirth à l'étage 10),
puis disparaît. Réutiliser les vrais pads / prompts existants (ne pas créer de faux objets).

Technique : le serveur garde l'étape (sauvegarde : un champ TutorialStep, migration propre,
GameConfig.SchemaVersion) et la fait avancer quand l'action vraie a eu lieu (ramassage, vente, achat) ;
le client dessine. Un joueur qui quitte reprend à la bonne étape. Un profil existant (déjà des
achats) saute le tutoriel. Pendant le tutoriel : pas d'offre limitée ni de popup d'achat (sauf le
Starter Pack ? → demande-moi), HUD réduit à l'argent. Mesure : AnalyticsService funnel (une étape =
un événement, skill roblox-analytics). Textes dans une Config (src/shared/Config/Tutorial.luau).

Vérifier : profil neuf en playtest Studio (outils Debug pour repartir de zéro, puis REMETTRE le
profil de test), captures de chaque étape, chronométrer (but : étape 7 avant 40 s, fin vers 8-12 min),
test du simulateur téléphone (flèches visibles, textes lisibles). Plusieurs sessions utilisent le
même Studio : vérifie qu'aucune n'est en playtest avant de lancer / arrêter. Doc
docs/systems/tutoriel.md + README + journal. Montre-moi des captures avant de dire fini.
```

---

## 4. Relecture de sécurité (rapide)

```
Projet D:\Usine (tycoon Roblox "Sell a Juice"). Lis AGENTS.md, docs/architecture.md, et les skills
roblox-security, roblox-networking, roblox-monetization, roblox-data. Relecture de sécurité AVANT
publication, sans réécrire le jeu :
- chaque RemoteEvent / RemoteFunction (src/shared/Network/Remotes.luau) : type et valeur des
  arguments vérifiés côté serveur, possession de la base / de l'étage, distance, délai (anti-spam) ;
  le client ne décide jamais d'un prix, d'un montant ni d'une récompense ;
- achats Robux : ProcessReceipt (ReceiptService) donne chaque reçu une seule fois, même si le joueur
  part ou si le serveur plante ; passes vérifiés par UserOwnsGamePassAsync ; cadeaux ;
- argent : plafonds (GameConfig.MaxMoney), pas de nombre négatif / NaN / inf accepté ;
- panneau admin (AdminService) et DebugService : impossible à utiliser par un joueur normal en
  production (vérifier UserId / créateur / RunService:IsStudio) ;
- gains hors ligne : impossible de tricher avec l'heure (temps serveur seulement, plafond) ;
- sauvegarde : session lock ProfileStore, rien de critique écrit par le client.
Liste les problèmes du plus grave au moins grave avec fichier:ligne et un scénario de triche.
Corrige seulement les failles réelles (petits correctifs), `rojo build` + Selene, journal.
Demande-moi avant tout gros changement.
```

---

## 5. Checklist de publication (en dernier)

```
Projet D:\Usine (tycoon Roblox "Sell a Juice"). Lis AGENTS.md, docs/roadmap.md, le dernier journal.
Lance le skill roblox-publish-checklist et fais la checklist complète avec preuves (pas de "ça
devrait marcher"). À couvrir au minimum :
- GameConfig.DataStoreName : passer de "PlayerData_v1" (données de test) à un nouveau nom pour le
  lancement ; GameConfig.AdminUserIds correct ;
- tous les productId / passId remplis (prompt 2) ; tutoriel fait (prompt 3) ; sécurité faite (prompt 4) ;
- test téléphone (simulateur Studio : iPhone + tablette, interface, boutons, flèches) ;
- test 2+ joueurs (Test > Clients and Servers) : 6 bases, attribution, vol, classements, dons ;
- performances (skill roblox-performance) : 10 étages, plusieurs joueurs, téléphone ;
- économie : profil neuf jusqu'à l'étage 2 en jeu réel (cible : 10-15 min), rebirth testé ;
- sons, musique, textes en anglais, traduction auto activée, icône / miniatures / description ;
- erreurs dans la console Output en playtest : zéro.
Donne-moi la liste PASS / FAIL avec la preuve de chaque point, corrige les petits FAIL, et dis-moi
ce qui reste à faire par moi (Creator Hub). NE PUBLIE PAS sans mon accord explicite ; première
sortie conseillée : accès restreint (amis) avant le public.
```
