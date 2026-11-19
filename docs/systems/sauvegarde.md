# Systeme : Sauvegarde des joueurs

**Statut :** a concevoir
**Derniere mise a jour :** 2026-11-19

## Role

Charge la sauvegarde du joueur a son arrivee, la garde en memoire pendant la partie et l'ecrit
dans le DataStore (sauvegarde automatique, depart du joueur, fermeture du serveur). Un seul
serveur a la fois peut modifier la sauvegarde d'un joueur (verrou de session).

## Fichiers

| Fichier | Cote | Role |
|---|---|---|
| `src/server/Services/DataService.luau` | serveur | Chargement, verrou, migrations, depart, BindToClose |
| `src/server/Vendor/ProfileStore.luau` | serveur | Librairie ProfileStore (si validee) + `NOTICE.md` (source, version, licence) |
| `src/shared/Config/GameConfig.luau` | partage | `DataStoreName`, `SchemaVersion` |

## Fonctionnement

- Choix propose : **ProfileStore** (MadStudioRoblox). Raison : verrou de session, sauvegarde
  automatique, BindToClose et `UpdateAsync` deja faits et eprouves ; ecrire tout ca a la main est
  la premiere source de pertes de donnees. Sans accord : DataStore a la main (UpdateAsync,
  3 tentatives, verrou maison), plus long et plus risque.
- Arrivee : `StartSessionAsync("player_<UserId>")` avec delai maximum 30 s. Echec -> le joueur est
  renvoye avec un message propre ("Your data could not be loaded. Please rejoin."). Jamais de
  profil vide a la place d'un profil qui n'a pas pu etre lu.
- Puis `Reconcile()` (ajoute les champs absents) et migration selon `SchemaVersion`.
- Premiere visite = profil neuf (premier chargement). Sert a poser 3 pommes au sol.
- Depart : `EndSession()`. Fermeture du serveur : ProfileStore termine les sessions ouvertes.
- DataStore indisponible (Studio sans "Enable Studio Access to API Services") : ProfileStore
  passe en mode hors ligne, un avertissement clair est ecrit dans la console, le jeu reste
  jouable, rien n'est ecrit. Chaque session compte alors comme une premiere visite.
- Une seule porte : les autres services lisent/modifient les donnees par `DataService`, et
  chaque champ a un seul proprietaire (Money -> MoneyService, Upgrades -> UpgradeService,
  DiscoveredFruits -> TreeService).

## Remotes

Aucun.

## Donnees sauvegardees (SchemaVersion 1)

| Champ | Type | Defaut | Proprietaire |
|---|---|---|---|
| `SchemaVersion` | number | 1 | DataService |
| `Money` | number (entier >= 0) | 0 (`GameConfig.StartingMoney`) | MoneyService |
| `Rebirths` | number | 0 | (phase 4) |
| `Upgrades` | { [UpgradeId]: niveau } | voir `Config/Upgrades.luau` (TreeSpeed 1, TreeLuck 1, JuiceLimit 1, CounterLimit 1, CustomerSpeed 1, CustomerCount 1, Collector 0, Presser 0, Server 0) | UpgradeService |
| `DiscoveredFruits` | { [FruitId]: true } | { Apple = true } | TreeService |
| `LastLogout` | number (os.time) | 0 | DataService |
| `IntroSeen` | boolean | false | (phase 2) |

`TreeSpeed` et `TreeLuck` sont dans `Upgrades` (meme mecanisme d'achat que les autres).

Pas sauvegardes : fruits au sol, fruits portes, jus, argent pas encore ramasse.

Plus tard (pas en phase 1) : zones achetees, machines a cocktails et recettes (phase 4), boosts en
cours avec le temps restant, passes recus en cadeau (phase 3).

Migration : chaque nouveau champ a une valeur par defaut dans le modele ; une fonction par
passage de version (`1 -> 2`...) si un champ change de forme.

## Configuration

- `GameConfig.DataStoreName = "PlayerData_v1"` : les tests en Studio (avec l'acces API) ecrivent
  dans le vrai DataStore de l'experience. Changer le nom (ex. `PlayerData_v2`) avant le lancement
  pour repartir a zero.

## Problemes connus / a faire

- Acces API desactive dans Studio "usine" (constate le 2026-11-19) : la sauvegarde ne peut pas
  etre testee tant que l'utilisateur ne l'active pas (Game Settings > Security).
