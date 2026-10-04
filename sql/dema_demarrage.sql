-- =====================================================================
-- Dema — remise à zéro avant la mise en service
-- =====================================================================
-- À passer UNE FOIS, la veille du premier vrai jour.
--
-- Ta base contient aujourd'hui les gens et les commandes de tes essais :
-- « Awa Doublon », « Final Test », des paiements inventés. Le premier matin,
-- Fatoumata ouvrirait son écran avec ce mélange sous les yeux, et ses chiffres
-- seraient faux dès la première minute.
--
-- Ce fichier efface les MOUVEMENTS et garde la CONFIGURATION :
--   effacé  : personnes, commandes, lignes, paiements
--   gardé   : traiteur, entreprises, rubriques, plats, moyens de paiement,
--             et le compte de connexion du traiteur
--
-- Il ne touche à aucune fonction. Après son passage, la base est propre et
-- le menu est intact.
-- ---------------------------------------------------------------------
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1. Ce qu'on s'apprête à effacer — à lire AVANT
-- ---------------------------------------------------------------------
select 'À effacer' as quoi,
       (select count(*) from personne)          as personnes,
       (select count(*) from commande)          as commandes,
       (select count(*) from ligne)             as lignes,
       (select count(*) from paiement)          as paiements
union all
select 'À garder',
       (select count(*) from site),
       (select count(*) from rubrique),
       (select count(*) from article),
       (select count(*) from moyen_paiement);

-- ---------------------------------------------------------------------
-- 2. L'effacement, dans l'ordre des dépendances
-- ---------------------------------------------------------------------
begin;

delete from paiement_commande;
delete from paiement;
delete from ligne;
delete from commande;
delete from personne;

commit;

-- ---------------------------------------------------------------------
-- 3. Contrôle d'après — doit afficher 0 partout à gauche
-- ---------------------------------------------------------------------
select (select count(*) from personne)  as personnes,
       (select count(*) from commande)  as commandes,
       (select count(*) from paiement)  as paiements,
       (select count(*) from site)      as entreprises,
       (select count(*) from article)   as plats,
       (select count(*) from compte)    as comptes_traiteur;

-- =====================================================================
-- CONTRÔLE DE CONFIGURATION — à lire ligne par ligne
-- =====================================================================
-- Les trois requêtes qui suivent n'effacent rien. Elles montrent ce que
-- verront Fatoumata et les employés lundi matin. Relis-les avec elle.

-- a) Les entreprises et leur heure de clôture.
--    Le « lien » est celui à coller dans chaque groupe WhatsApp.
select s.nom as entreprise,
       '…/?s=' || s.slug      as lien,
       to_char(s.cloture,'HH24:MI') as cloture,
       s.actif
  from site s order by s.nom;

-- b) LES NUMÉROS D'ENCAISSEMENT. Le point le plus risqué du système :
--    c'est ce numéro qui s'affiche à l'employé au moment de payer. S'il est
--    faux, l'argent part chez quelqu'un d'autre. À vérifier avec elle, à voix
--    haute, chiffre par chiffre.
select m.nom as moyen, m.numero, m.actif
  from moyen_paiement m order by m.ordre;

-- c) Le menu de la semaine, tel qu'il sortira chaque jour.
select case a.jour when 1 then 'lundi' when 2 then 'mardi' when 3 then 'mercredi'
                   when 4 then 'jeudi' when 5 then 'vendredi' when 6 then 'samedi'
                   when 7 then 'dimanche' else 'tous les jours' end as jour,
       r.nom as rubrique, a.nom as plat, a.prix, a.limite, a.actif
  from article a join rubrique r on r.id = a.rubrique_id
 where a.actif
 order by coalesce(a.jour, 0), r.ordre, a.ordre;

-- d) Qui peut ouvrir l'écran du traiteur.
select c.nom, u.email
  from compte c join auth.users u on u.id = c.user_id;
