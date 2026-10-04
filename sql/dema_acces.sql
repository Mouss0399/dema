-- =====================================================================
-- Dema — pourquoi l'écran du traiteur ne montre rien
-- =====================================================================
-- UNE SEULE requête : l'éditeur SQL de Supabase n'affiche que le dernier
-- résultat, donc tout est réuni ici. N'écrit rien.
--
-- Lis la colonne « verdict » de haut en bas. La première ligne en majuscules
-- est la cause.
-- ---------------------------------------------------------------------
with
compte_etat as (
  select u.email,
         c.user_id is not null                                       as a_une_ligne,
         t.id is not null                                            as rattache,
         coalesce(t.nom,'—')                                         as traiteur,
         (select count(*) from site s where s.traiteur_id = t.id)    as entreprises
    from auth.users u
    left join compte   c on c.user_id = u.id
    left join traiteur t on t.id = c.traiteur_id
),
fonctions as (
  select count(*) filter (
           where p.proacl is not null
             and array_to_string(p.proacl,' ') like '%authenticated=X%') as ouvertes,
         count(*)                                                        as total
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public'
     and p.proname in ('fn_tableau','fn_config','fn_clients','fn_commander_pour')
),
declencheurs as (
  select count(*) as n from pg_trigger
   where not tgisinternal and tgname in ('trg_maj_montant','trg_maj_statut')
)
select * from (
  -- 1. un verdict par compte : c'est ici que se trouve la cause, en général
  select 1 as ordre, 'compte · ' || e.email as controle,
         e.traiteur || ' · ' || e.entreprises || ' entreprise(s)' as valeur,
         case
           when not e.a_une_ligne then 'AUCUNE LIGNE dans compte → exécute le INSERT en bas du fichier'
           when not e.rattache    then 'COMPTE DÉTACHÉ → repasse dema_reparation.sql'
           when e.entreprises = 0 then 'TRAITEUR SANS ENTREPRISE → recrée-les dans la mise en route'
           else 'cet accès devrait fonctionner'
         end as verdict
    from compte_etat e

  -- 2. le reste de la chaîne
  union all select 2, 'traiteurs en base', (select count(*)::text from traiteur),
    case when (select count(*) from traiteur) = 0
         then 'AUCUN TRAITEUR → repasse dema_schema.sql (il efface tout)'
         else 'ok' end
  union all select 3, 'entreprises en base', (select count(*)::text from site),
    case when (select count(*) from site) = 0
         then 'AUCUNE ENTREPRISE → les liens ?s=… ne répondront pas' else 'ok' end
  union all select 4, 'plats actifs', (select count(*)::text from article where actif),
    case when (select count(*) from article where actif) = 0
         then 'MENU VIDE → la page de commande sera vide' else 'ok' end
  union all select 5, 'fonctions traiteur ouvertes',
    (select ouvertes || ' sur ' || total from fonctions),
    case when (select ouvertes from fonctions) < 4
         then 'FONCTIONS FERMÉES → repasse dema_traiteur.sql' else 'ok' end
  union all select 6, 'déclencheurs de calcul',
    (select n || ' sur 2' from declencheurs),
    case when (select n from declencheurs) < 2
         then 'DÉCLENCHEURS MANQUANTS → repasse dema_api.sql' else 'ok' end
) x order by ordre, controle;

-- ---------------------------------------------------------------------
-- Si le verdict dit « AUCUNE LIGNE dans compte » :
-- remplace l'adresse, décommente, et exécute ces lignes SEULES.
-- ---------------------------------------------------------------------
-- insert into compte (user_id, traiteur_id, nom)
-- select u.id, t.id, 'Moussa'
--   from auth.users u, traiteur t
--  where u.email = 'TON-ADRESSE@exemple.com'
--    and t.id = (select id from traiteur order by cree_le limit 1)
-- on conflict (user_id) do update set traiteur_id = excluded.traiteur_id;
