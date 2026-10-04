-- =====================================================================
-- Dema — réparation après un passage de dema_schema.sql
-- =====================================================================
-- Rejouer dema_schema.sql remet la base à neuf : il efface les données, mais
-- aussi deux choses moins visibles.
--
--   1. Les tables sont recréées, donc leurs DÉCLENCHEURS disparaissent.
--      trg_maj_montant et trg_maj_statut vivent dans dema_api.sql. Sans eux,
--      le montant d'une commande reste à 0 : on commande, et on ne doit rien.
--
--   2. La table « traiteur » est recréée avec un nouvel identifiant, alors
--      que la table « compte » survit. Le compte de connexion pointe donc
--      dans le vide, et l'écran du traiteur ne montre plus rien.
--
-- Ce qui n'a PAS bougé : le verrouillage des droits. Les tables neuves sont
-- nées sans accès pour la clé publique, parce que le retrait portait aussi
-- sur les droits par défaut. Rien n'a été exposé.
--
-- MARCHE À SUIVRE, dans l'ordre :
--   1. dema_api.sql        ← indispensable, il remet les déclencheurs
--   2. dema_traiteur.sql
--   3. dema_admin.sql
--   4. ce fichier
--   5. dema_etat.sql       ← pour contrôler
-- ---------------------------------------------------------------------
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1. Rattacher les comptes orphelins au traiteur
-- ---------------------------------------------------------------------
-- On ne touche qu'aux comptes dont le traiteur n'existe plus, et on les
-- rattache au plus ancien — celui que le schéma vient de semer.
update compte c
   set traiteur_id = (select id from traiteur order by cree_le, nom limit 1)
 where not exists (select 1 from traiteur t where t.id = c.traiteur_id);

-- ---------------------------------------------------------------------
-- 2. Contrôle
-- ---------------------------------------------------------------------
select c.nom as compte,
       t.nom as traiteur,
       case when t.id is null then 'ORPHELIN' else 'rattaché' end as etat
  from compte c left join traiteur t on t.id = c.traiteur_id;

-- Les deux déclencheurs de calcul doivent être là. S'ils manquent,
-- c'est que dema_api.sql n'a pas été rejoué : reprends à l'étape 1.
select tgname as declencheur,
       case when tgname in ('trg_maj_montant','trg_maj_statut')
            then 'calcul des montants' else 'autre' end as role
  from pg_trigger where not tgisinternal order by tgname;

-- Une commande d'essai doit afficher un montant non nul.
-- (Elle n'est pas enregistrée : tout est annulé à la fin.)
begin;
  insert into personne (site_id, nom, tel)
    select id, 'Essai Réparation', '770000001' from site order by slug limit 1;
  insert into commande (site_id, personne_id, jour)
    select p.site_id, p.id, fn_aujourdhui() from personne p where p.nom = 'Essai Réparation';
  insert into ligne (commande_id, article_id, qte, prix_unitaire)
    select c.id, a.id, 1, a.prix
      from commande c, article a
     where c.personne_id = (select id from personne where nom = 'Essai Réparation')
       and a.actif order by a.ordre limit 1;
  select case when montant > 0 then 'les montants se calculent : ' || montant || ' F'
              else 'MONTANT À ZÉRO — rejoue dema_api.sql' end as verification
    from commande c join personne p on p.id = c.personne_id
   where p.nom = 'Essai Réparation';
rollback;
