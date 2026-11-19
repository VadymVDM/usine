# Systeme : Carte, bases et attribution

**Statut :** a concevoir
**Derniere mise a jour :** 2026-11-19

## Role

La carte (route, spawn, decor) et les 6 bases. Chaque joueur recoit une base libre a son
arrivee ; elle est videe et liberee a son depart.

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `tools/build-map/*.luau` | Studio (hors Rojo) | Scripts de construction relances par morceaux via MCP |
| `Workspace.Map` | Studio (.rbxl) | Route, spawn, decor, 6 emplacements `BaseSlot1..6` |
| `ServerStorage.BaseTemplate` | Studio (.rbxl) | Modele d'une base (sol, arbre, bacs, presse, comptoir, tableaux, murs zones 2-3) |
| `src/server/Services/BaseService.luau` | serveur | Clone le modele dans chaque emplacement, attribution, nettoyage |
| `src/shared/Config/Map.luau` | partage | Nombre de bases, textes |

## Fonctionnement

- Plan general (style blocky, studs, couleurs vives, `docs/style.md`) :

```
   [Base 1]      [Base 2]      [Base 3]
 ==SPAWN======== ROUTE (clients) ========
   [Base 4]      [Base 5]      [Base 6]
```

- Une base (vue de dessus, la route en bas) : zone 1 a gauche, zones 2 et 3 a droite, fermees.

```
 +-------------------------------------------------+
 | [Tree Speed][Tree Luck]  ARBRE (fruits au sol)   |  ZONE 2 (mur ferme,
 | [mur du fond : tableau Employes]                 |   planches + panneau)
 | BACS (1 par fruit ouvert)   PRESSE -> pile jus   |
 |                             [Juice Limit]        |
 | [Counter Limit][Customers]  COMPTOIR  $ TAS      |  ZONE 3 (mur ferme)
 +=================================================+
                 ROUTE (clients)
```

- Ecart avec le schema de `game-design.md` : il ne montre qu'un mur de boutons. Proposition :
  petits tableaux sur pied a cote de ce qu'ils ameliorent, et le tableau des employes sur le mur
  du fond. (A valider.)
- Murs des zones 2 et 3 : planches en croix + panneau rouge "Coming soon" (proposition), pas
  achetables en phase 1.
- Modele : **1 modele `BaseTemplate` dans ServerStorage, clone 6 fois** par `BaseService` au
  demarrage (les 3 bases du bas tournees de 180 degres pour faire face a la route). Une
  modification du modele s'applique aux 6 bases. Le modele et la carte sont reconstruits depuis
  `tools/build-map/` (le .rbxl n'est pas dans git).
- Attribution : premiere base libre a l'arrivee ; attribut `OwnerUserId` sur la base ; panneau
  "<Name>'s Juice Stand". Depart : tout ce qui est dynamique (fruits, jus, argent du comptoir,
  PNJ) est detruit, panneau remis a "Free Stand".
- 7e joueur (serveur plein) : pas d'erreur ; message "All stands are taken. Please join another
  server." (remote `Notify`) et le joueur peut se promener.
- Le joueur reapparait dans sa base (point d'apparition de la base).

## Remotes

| Nom | Sens | Arguments | Verifications serveur |
|---|---|---|---|
| `Notify` | serveur -> client | texte (anglais) | aucune (sens serveur -> client) |

## Donnees sauvegardees

Aucune (la base n'est pas sauvegardee, seulement les niveaux).

## Configuration

`Config/Map.luau` : `MaxBases = 6`, textes du panneau et du serveur plein.

## Problemes connus / a faire

- Taille du serveur (6) : reglage de l'experience a faire par l'utilisateur.
