# La démonstration

`lekkbi.com/suivi.html?demo` ouvre l'écran du traiteur sur une journée
d'exemple, sans mot de passe. `lekkbi.com/?s=demo` ouvre l'écran des
employés sur le même menu.

**Rien de tout cela ne touche la base.** Les deux pages servent les fichiers
de ce dossier au lieu d'appeler le serveur : aucune requête ne part, aucun
compte n'est demandé, et aucune écriture n'est possible. Un visiteur ne peut
donc ni voir les données d'un vrai traiteur, ni en créer.

Les fichiers ne sont téléchargés **que** dans ce mode. Quelqu'un qui ouvre
son écran normalement ne paie pas un octet pour la démonstration.

## Ce qu'un visiteur peut faire

Côté traiteur : tout parcourir — à préparer, encaissé, impayés, clients,
filtrer par entreprise. Côté employé : voir le menu, choisir un plat,
valider, et voir la confirmation avec le bon total.

Tout le reste — pointer un paiement, encaisser, modifier une fiche — répond
« Démonstration — rien n'est enregistré ici. » plutôt que d'échouer en
silence.

## Refaire les fichiers

`fabrication.sql` sème la journée (39 commandes, 132 000 F dus, 89 000 F
rentrés) **sur une copie locale de la base**, jamais en production. Il efface
les tables avant de semer, donc il ne se joue que sur une base jetable.

Puis, pour chaque fichier, le résultat de la fonction correspondante,
minifié :

| Fichier | Appel |
|---|---|
| `tableau.json` | `fn_tableau()` |
| `tableau-teranga.json` | `fn_tableau(null,'teranga')` |
| `tableau-diallo.json` | `fn_tableau(null,'diallo')` |
| `clients.json` | `fn_clients(null,null)` |
| `clients-teranga.json` | `fn_clients('teranga',null)` |
| `clients-diallo.json` | `fn_clients('diallo',null)` |
| `config.json` | `fn_config()` |
| `menu.json` | `fn_menu('teranga','demo-visiteur')` |

Les données sortent des vraies fonctions, pas d'une fixture écrite à la
main : le jour où une fonction change de forme, la démonstration le montre
au lieu de diverger en silence.

La date est remplacée par celle du jour à l'affichage — une démonstration
datée d'il y a trois semaines se lit comme un produit abandonné.

## Ce qui est fictif

« Le Bon Plat », « Teranga Digital », « Cabinet Diallo » et les quarante noms
n'existent pas. Ce ne sont les données de personne.
