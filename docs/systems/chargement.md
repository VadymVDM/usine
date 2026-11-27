# Systeme : Chargement (prechargement invisible)

**Statut :** fonctionne (teste en Studio PC, pas sur telephone)
**Derniere mise a jour :** 2026-11-20

## Role

Rendre l'arrivee fluide **sans ecran de chargement a nous** : le joueur voit l'ecran de Roblox,
puis directement le monde. L'interface (HUD) reste cachee le temps que tout soit pret (icones,
textes, sons, carte proche), puis apparait d'un coup, deja complete. Le "Welcome Back!", lui,
s'ouvre des l'arrivee, sans attendre la fin (il ne precharge que ses propres images).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/first/Preloader.client.luau` | client (ReplicatedFirst) | Cache le HUD, attend les etapes, precharge, remontre le HUD |
| `src/client/Main.client.luau` | client | Appelle `Prewarm()` des controleurs puis pose `ClientReady` |
| `src/client/Controllers/ShopController.luau` | client | `Prewarm()` : met en page le Shop en invisible |
| `src/client/Controllers/WelcomeBackController.luau` | client | `WaitUntilReady()` : attend `ClientReady` + ses images (2 s max), puis ouvre |

## Fonctionnement

1. `Preloader` (ReplicatedFirst, tourne en premier) met `Enabled = false` sur les ScreenGuis de
   `HIDDEN_GUIS` (`HUD`) des qu'ils arrivent dans PlayerGui. Il n'appelle pas
   `RemoveDefaultLoadingScreen()` : l'ecran de Roblox disparait tout seul quand le jeu est charge.
   Un ScreenGui desactive calcule quand meme sa mise en page (verifie en Studio) : les controleurs
   peuvent lire `AbsolutePosition` / `AbsoluteSize` normalement.
2. Etapes avant de montrer le HUD, chacune avec un delai max (le joueur n'est jamais bloque) :
   - jeu charge + personnage present (15 s) ;
   - attribut joueur `ClientReady` (15 s) : pose par `Main.client` apres tous les `Start()`
     termines et les `Prewarm()` faits ;
   - `ContentProvider:PreloadAsync` sur PlayerGui + les icones de `Config/Icons` seulement
     (`HUD_PRELOAD_TIMEOUT` = 3 s max).
3. HUD reactive, attribut joueur `LoadingDone` = true. Le Welcome Back est deja ouvert
   (des `ClientReady`) : a sa fermeture, le HUD revient normalement.
4. **Ensuite, en arriere-plan** (HUD deja visible) : on attend que la carte se stabilise
   (streaming : 0.6 s sans nouvelle piece, 8 s max) puis `PreloadAsync` sans limite sur :
   Workspace, Lighting (ciel), **tout ReplicatedStorage** (fruits voxel `FruitAssets`, PNJ
   `NpcTemplates`, sons `Shared/Assets`), et une instance "porteuse" par id pour : les sons de
   `Config/Sounds`, les animations R15 de `Config/Npcs.AnimationsR15`, les photos d'avatar (60 et 420 px)
   des joueurs deja presents. Jusqu'au 2026-11-20 le HUD attendait aussi cette etape (jusqu'a
   ~20 s de plus : carte 8 s + prechargement 12 s) : c'etait la cause des boutons qui mettaient
   longtemps a apparaitre.
5. `Prewarm()` (optionnel) d'un controleur : appele par `Main` une fois son `Start()` fini, pendant
   que le HUD est cache. Le Shop s'y ouvre en invisible et calcule la taille de ses textes, sinon la
   premiere ouverture montrait ~1 s de textes trop gros.

## Remotes

Aucun. Attributs joueur cote client seulement : `ClientReady`, `LoadingDone`.

## Donnees sauvegardees

Aucune.

## Configuration

Constantes en haut de `Preloader.client.luau` (ScreenGuis caches, delais). Purement client, donc
pas dans `src/shared/Config/`.

## Problemes connus / a faire

- Pendant le prechargement le joueur voit et peut bouger dans le monde sans HUD (~1 s en Studio,
  3 s max pour les images en plus de la construction de l'interface).
- Comme fruits, PNJ et sons se prechargent maintenant apres l'apparition du HUD, un objet peut
  encore "poper" dans les toutes premieres secondes sur une connexion lente.
- Les images du pack UI sans permission (89847456327542 fond du Shop, 103832952076051,
  94808176966042, 104216746370508) echouent toujours au chargement : "User is not authorized".
  Il faut les re-uploader sur le compte ou leur donner acces.
- Pas teste sur telephone ni avec une vraie connexion lente (en Studio les assets sont en cache :
  le retard ne se voit qu'en jeu publie).
- Images du pack UI sans permission : ce sont le fond a motif du Shop / Rebirth (`Pattern`,
  `SubHeader`, 89847456327542) et le X de fermeture (104216746370508). Elles ne s'affichent jamais,
  prechargement ou pas.
- Ce qui est cree **apres** le prechargement (base d'un joueur qui arrive plus tard, etages
  debloques, pieces streamees plus loin, avatars de joueurs qui rejoignent) n'est pas precharge.
