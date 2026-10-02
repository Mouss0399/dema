# Dema — commandes de déjeuner

Trois pages, un seul projet Supabase.

| Page | Fichier | Pour qui |
|---|---|---|
| Commander | `index.html` | Les employés, une adresse par entreprise : `…/?s=yas` |
| Ma journée | `suivi.html` | Le traiteur — à préparer, encaissé, impayés |
| Mise en route | `reglages.html` | Le traiteur — menu, rubriques, entreprises, paiements |

Les deux pages du traiteur demandent un compte. La page de commande n'en
demande pas : c'est le lien qui dit de quelle entreprise vient la commande,
comme le sondage WhatsApp était déjà propre à chaque groupe.

## La clé qui est dans le code

Les trois pages contiennent la clé **publique** du projet. C'est voulu : elle
est faite pour être lue. Ce qui protège les données, c'est que rien n'est
accessible directement — tout passe par des fonctions qui vérifient qui
appelle. Les noms, les numéros et l'argent ne sortent que pour un compte
rattaché au traiteur.

La clé `service_role` n'a rien à faire ici, ni dans ce dépôt, ni ailleurs.

## Mettre à jour

Remplacer le fichier, relancer `./pousser-dema.sh <ton-compte-github>`.
