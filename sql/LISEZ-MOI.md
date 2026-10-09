# Dans quel ordre passer ces fichiers

Dans le SQL Editor de Supabase, une fois chacun, dans cet ordre :

1. `dema_schema.sql` — les tables et le menu de départ.
   ⚠️ Il efface tout à chaque passage. Une fois la base en service, supprime
   le bloc de remise à zéro en haut du fichier, ou ne le rejoue plus.
2. `dema_api.sql` — les six fonctions de la page de commande.
3. `dema_storage.sql` — le casier des captures de paiement.
4. `dema_traiteur.sql` — l'accès traiteur et l'écran de suivi.
5. `dema_admin.sql` — la mise en route (menu, rubriques, entreprises).

Quand je te livre une correction, seul le fichier concerné est à rejouer.
`dema_api.sql`, `dema_traiteur.sql` et `dema_admin.sql` remplacent leurs
fonctions sans toucher aux données.

⚠️ `dema_schema.sql` ne se rejoue **jamais** sur une base en service : il
efface tout. Quand une colonne nouvelle est nécessaire, elle est ajoutée en
haut de `dema_traiteur.sql` par un `alter table ... add column if not exists`,
sans effet si elle existe déjà. Les modifications de `dema_schema.sql` ne
servent qu'aux installations neuves.

## Encaissement par le traiteur

À rejouer : `dema_traiteur.sql` (la colonne `paiement.par_traiteur`, le moyen
« Espèces », et `fn_encaisser`), puis `dema_admin.sql` (une rubrique et ses
plats ne peuvent plus se contredire sur le jour).

## Rattacher un compte traiteur

Authentication → Users → Add user, avec l'adresse et un mot de passe. Puis :

```sql
insert into compte (user_id, traiteur_id, nom)
select u.id, t.id, 'Fatoumata'
  from auth.users u, traiteur t
 where u.email = 'adresse@exemple.sn' and t.nom = 'Dema Traiteur'
on conflict (user_id) do nothing;
```
