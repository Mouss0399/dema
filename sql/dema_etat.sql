-- =====================================================================
-- Dema — où en est ma base ?
-- =====================================================================
-- À coller dans le SQL Editor. N'écrit rien, ne change rien : il regarde
-- (L'éditeur de Supabase n'affiche que le DERNIER résultat : c'est le
--  tableau de synthèse en bas qui compte. Pour voir le détail ligne par
--  ligne, sélectionne la première requête seule avant de lancer.)
-- ce qui existe et te dit ce qu'il reste à passer.
--
-- Chaque ligne « MANQUE » nomme le fichier à rejouer. Les fichiers
-- dema_api.sql, dema_traiteur.sql et dema_admin.sql remplacent leurs
-- fonctions sans toucher aux données : les rejouer ne coûte rien.
-- ---------------------------------------------------------------------
with v as (
  select
    exists (select 1 from information_schema.columns
             where table_name='personne' and column_name='tel_norm')        as num_identite,
    exists (select 1 from information_schema.columns
             where table_name='paiement' and column_name='pointe')          as pointage_colonne,
    exists (select 1 from pg_proc where proname='fn_pointer')                as pointage_fonction,
    exists (select 1 from pg_proc where proname='fn_clients')                as liste_clients,
    exists (select 1 from pg_proc where proname='fn_fusionner')              as fusion,
    exists (select 1 from pg_proc where proname='fn_annuler')                as annulation,
    exists (select 1 from pg_proc where proname='fn_commander_pour')         as saisie_traiteur,
    exists (select 1 from pg_proc where proname='fn_recalc')                 as reste_du,
    exists (select 1 from pg_proc where proname='fn_norm_tel')               as normalisation_num,
    exists (select 1 from pg_proc where proname='fn_menu'
              and prosrc like '%''traiteur'', (select nom from traiteur%')   as nom_traiteur,
    exists (select 1 from pg_proc where proname='fn_tableau'
              and prosrc like '%''qui'', aa.qui%')                           as feuille_distribution,
    exists (select 1 from pg_proc where proname='fn_site_maj'
              and prosrc like '%v_base%')                                    as adresse_auto,
    exists (select 1 from pg_proc where proname='fn_menu'
              and prosrc like '%''pris''%')                                  as plat_deja_pris
)
select * from (
  select 1 as n, 'Numéro comme identité'        as quoi, num_identite        as ok, 'dema_api.sql'      as fichier from v
  union all select 2,  'Normalisation des numéros',      normalisation_num,      'dema_api.sql'      from v
  union all select 3,  'Reste dû / commande complétée',  reste_du,               'dema_api.sql'      from v
  union all select 4,  'Annuler sa commande',            annulation,             'dema_api.sql'      from v
  union all select 5,  'Plat déjà pris non proposé',     plat_deja_pris,         'dema_api.sql'      from v
  union all select 6,  'Nom du traiteur sur la page',    nom_traiteur,           'dema_api.sql'      from v
  union all select 7,  'Pointage — colonne',             pointage_colonne,       'dema_traiteur.sql' from v
  union all select 8,  'Pointage — fonction',            pointage_fonction,      'dema_traiteur.sql' from v
  union all select 9,  'Liste des clients',              liste_clients,          'dema_traiteur.sql' from v
  union all select 10, 'Fusion de deux fiches',          fusion,                 'dema_traiteur.sql' from v
  union all select 11, 'Saisie par le traiteur',         saisie_traiteur,        'dema_traiteur.sql' from v
  union all select 12, 'Feuille de distribution',        feuille_distribution,   'dema_traiteur.sql' from v
  union all select 13, 'Adresse qui se complète',        adresse_auto,           'dema_admin.sql'    from v
) t
order by ok, n;

-- ---------------------------------------------------------------------
-- Résumé : les fichiers qu'il te reste à passer
-- ---------------------------------------------------------------------
with v as (
  select
    exists (select 1 from information_schema.columns
             where table_name='personne' and column_name='tel_norm')        as a1,
    exists (select 1 from pg_proc where proname='fn_recalc')                 as a2,
    exists (select 1 from pg_proc where proname='fn_annuler')                as a3,
    exists (select 1 from pg_proc where proname='fn_menu'
              and prosrc like '%''traiteur'', (select nom from traiteur%')   as a4,
    exists (select 1 from pg_proc where proname='fn_menu'
              and prosrc like '%''pris''%')                                  as a5,
    exists (select 1 from information_schema.columns
             where table_name='paiement' and column_name='pointe')          as b1,
    exists (select 1 from pg_proc where proname='fn_clients')                as b2,
    exists (select 1 from pg_proc where proname='fn_commander_pour')         as b3,
    exists (select 1 from pg_proc where proname='fn_tableau'
              and prosrc like '%''qui'', aa.qui%')                           as b4,
    exists (select 1 from pg_proc where proname='fn_site_maj'
              and prosrc like '%v_base%')                                    as c1
)
select case when a1 and a2 and a3 and a4 and a5 then 'à jour' else 'À REPASSER' end as dema_api_sql,
       case when b1 and b2 and b3 and b4        then 'à jour' else 'À REPASSER' end as dema_traiteur_sql,
       case when c1                              then 'à jour' else 'À REPASSER' end as dema_admin_sql
  from v;
