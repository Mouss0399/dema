-- =====================================================================
-- Dema — suivi des commandes de déjeuner
-- Schéma PostgreSQL (compatible Supabase)
-- =====================================================================
-- Principes :
--   · le prix est figé sur la ligne de commande, jamais relu dans l'article
--   · un paiement peut couvrir plusieurs commandes (table d'affectation)
--   · le nom normalisé porte le rapprochement d'identités
--   · un site = un lien = un groupe WhatsApp ; l'attribution est native
-- =====================================================================

-- Supabase range les extensions dans le schéma « extensions » ; ailleurs elles
-- sont dans « public ». On couvre les deux cas (un schéma absent est ignoré).
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- REMISE A ZERO. Rend ce fichier rejouable autant de fois que tu veux
-- pendant la mise au point : il efface tout et reconstruit à neuf.
-- >>> SUPPRIME CE BLOC le jour où la base contient de vraies commandes,
--     sinon le rejouer effacerait la journée de Fatoumata. <<<
-- ---------------------------------------------------------------------
drop view if exists v_doublon, v_manquant, v_canal, v_cuisine cascade;
drop table if exists paiement_commande, paiement, ligne, commande,
                     personne, article, rubrique, moyen_paiement,
                     site, traiteur cascade;
drop function if exists fn_article_jour() cascade;
drop function if exists fn_norm(text) cascade;
-- ---------------------------------------------------------------------

create extension if not exists pgcrypto;   -- gen_random_uuid
create extension if not exists pg_trgm;    -- similarité des noms

-- ---------------------------------------------------------------------
-- 0. Normalisation des noms — la même idée que le moteur de EDU360
-- ---------------------------------------------------------------------
-- Normalisation d'un numéro sénégalais : on ne garde que les chiffres, on
-- retire l'indicatif 221 et les zéros de tête. Déterministe, contrairement au
-- rapprochement de noms — c'est tout l'intérêt de s'en servir comme clé.
create or replace function fn_norm_tel(txt text) returns text
language sql immutable as $$
  select nullif(
    regexp_replace(
      regexp_replace(regexp_replace(coalesce(txt,''), '[^0-9]', '', 'g'),
                     '^(00221|221)', ''),
      '^0+', ''),
    '');
$$;

create or replace function fn_norm(txt text)
returns text language sql immutable strict parallel safe as $$
  select trim(regexp_replace(
    lower(translate(txt,
      'àáâãäåçèéêëìíîïñòóôõöùúûüýÿÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝ',
      'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY')),
    '[^a-z0-9]+', ' ', 'g'));
$$;

-- ---------------------------------------------------------------------
-- 1. Référentiel du traiteur
-- ---------------------------------------------------------------------
create table traiteur (
  id        uuid primary key default gen_random_uuid(),
  nom       text not null,
  tel       text,
  cree_le   timestamptz not null default now()
);

create table site (
  id          uuid primary key default gen_random_uuid(),
  traiteur_id uuid not null references traiteur(id) on delete cascade,
  nom         text not null,                       -- « Yas », « Orange »
  slug        text not null unique,                -- dema.sn/<slug>
  cloture     time not null default '10:30',
  actif       boolean not null default true,
  cree_le     timestamptz not null default now(),
  constraint chk_slug check (slug ~ '^[a-z0-9][a-z0-9-]{1,30}$')
);

create table moyen_paiement (
  id          uuid primary key default gen_random_uuid(),
  traiteur_id uuid not null references traiteur(id) on delete cascade,
  code        text not null,                       -- wave | om | mixx
  nom         text not null,                       -- « Mix by Yas »
  numero      text,
  ordre       smallint not null default 0,
  actif       boolean not null default true,
  unique (traiteur_id, code)
);

-- ---------------------------------------------------------------------
-- 2. Menu : rubriques configurables, articles par jour ou fixes
-- ---------------------------------------------------------------------
create table rubrique (
  id          uuid primary key default gen_random_uuid(),
  traiteur_id uuid not null references traiteur(id) on delete cascade,
  nom         text not null,                       -- « Plats du jour », « Jus »
  mode        text not null default 'unique' check (mode in ('unique','multiple')),
  obligatoire boolean not null default false,
  quantite    boolean not null default false,      -- compteur par article
  par_jour    boolean not null default false,      -- ses articles changent chaque jour
  offert      boolean not null default false,      -- promo du moment : prix forcés à 0
  ordre       smallint not null default 0
);

create table article (
  id          uuid primary key default gen_random_uuid(),
  rubrique_id uuid not null references rubrique(id) on delete cascade,
  nom         text not null,
  prix        integer not null check (prix >= 0),            -- FCFA, entier
  limite      integer check (limite is null or limite >= 0), -- null = illimité
  jour        smallint check (jour between 1 and 7),         -- null si article fixe
  ordre       smallint not null default 0,
  actif       boolean not null default true
);

-- « jour » doit être renseigné si et seulement si la rubrique est par_jour.
create or replace function fn_article_jour() returns trigger
language plpgsql as $$
declare v_par_jour boolean;
begin
  select par_jour into v_par_jour from rubrique where id = new.rubrique_id;
  if v_par_jour and new.jour is null then
    raise exception 'Rubrique « par jour » : l''article doit porter un jour';
  elsif not v_par_jour and new.jour is not null then
    raise exception 'Rubrique fixe : l''article ne doit pas porter de jour';
  end if;
  return new;
end $$;

create trigger trg_article_jour before insert or update on article
for each row execute function fn_article_jour();

-- ---------------------------------------------------------------------
-- 3. Personnes — inscrites par elles-mêmes, une fois, par appareil
-- ---------------------------------------------------------------------
create table personne (
  id              uuid primary key default gen_random_uuid(),
  site_id         uuid not null references site(id) on delete cascade,
  nom             text not null,
  nom_norm        text not null generated always as (fn_norm(nom)) stored,
  tel             text,
  -- Le numéro est la vraie clé d'une personne : il se normalise exactement,
  -- là où un nom ne se rapproche qu'approximativement. « 77 123 45 67 »,
  -- « 771234567 » et « +221771234567 » donnent la même chose.
  tel_norm        text generated always as (fn_norm_tel(tel)) stored,
  appareil        text,                            -- clé stockée sur le téléphone
  fusionnee_vers  uuid references personne(id),    -- doublon résorbé
  cree_le         timestamptz not null default now()
);

-- deux personnes actives ne peuvent pas porter le même nom normalisé sur un site
create unique index uq_personne_nom on personne (site_id, nom_norm)
  where fusionnee_vers is null;
create index idx_personne_trgm on personne using gin (nom_norm gin_trgm_ops);
-- un numéro ne désigne qu'une personne par site
create unique index uq_personne_tel on personne (site_id, tel_norm)
  where tel_norm is not null and fusionnee_vers is null;
create unique index uq_personne_appareil on personne (site_id, appareil)
  where appareil is not null and fusionnee_vers is null;

-- ---------------------------------------------------------------------
-- 4. Commandes
-- ---------------------------------------------------------------------
create table commande (
  id             uuid primary key default gen_random_uuid(),
  site_id        uuid not null references site(id) on delete cascade,
  personne_id    uuid not null references personne(id),
  jour           date not null,
  commandee_par  uuid references personne(id),     -- null = elle-même
  montant        integer not null default 0 check (montant >= 0),
  statut         text not null default 'du' check (statut in ('du','paye','annule')),
  cree_le        timestamptz not null default now(),
  constraint uq_une_commande_par_jour unique (site_id, personne_id, jour)
);
create index idx_commande_jour on commande (site_id, jour);

create table ligne (
  id             uuid primary key default gen_random_uuid(),
  commande_id    uuid not null references commande(id) on delete cascade,
  article_id     uuid not null references article(id),
  qte            smallint not null check (qte > 0),
  prix_unitaire  integer not null check (prix_unitaire >= 0),  -- FIGÉ à la commande
  unique (commande_id, article_id)
);
create index idx_ligne_article on ligne (article_id);

-- ---------------------------------------------------------------------
-- 5. Paiements — un paiement couvre une ou plusieurs commandes
-- ---------------------------------------------------------------------
create table paiement (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references site(id) on delete cascade,
  personne_id uuid not null references personne(id),    -- qui a payé
  moyen_id    uuid references moyen_paiement(id),
  montant     integer not null check (montant > 0),
  preuve_url  text,                                     -- capture, purgée à 60 j
  reference   text,                                     -- référence API (phase 3)
  pointe      boolean not null default false,           -- rapproché du relevé par le traiteur
  par_traiteur boolean not null default false,          -- saisi par le traiteur, pas déclaré par le client
  pointe_le   timestamptz,
  jour        date not null,
  cree_le     timestamptz not null default now()
);
create index idx_paiement_jour on paiement (site_id, jour);

create table paiement_commande (
  paiement_id      uuid not null references paiement(id) on delete cascade,
  commande_id      uuid not null references commande(id) on delete cascade,
  montant_affecte  integer not null check (montant_affecte > 0),
  primary key (paiement_id, commande_id)
);
create index idx_pc_commande on paiement_commande (commande_id);

-- ---------------------------------------------------------------------
-- 6. Montant et statut recalculés, jamais saisis
-- ---------------------------------------------------------------------
-- Le calcul du montant et du statut vit dans dema_api.sql, avec le reste de la
-- logique : il a dû changer après coup, et un fichier qu'on peut rejouer sans
-- rien effacer est le bon endroit pour ça.

-- ---------------------------------------------------------------------
-- 7. Les trois vues qui font l'écran du traiteur
-- ---------------------------------------------------------------------

-- le compte pour la cuisine, par article
create view v_cuisine as
select c.site_id, c.jour, r.id as rubrique_id, r.nom as rubrique,
       a.id as article_id, a.nom as article, a.limite,
       sum(l.qte) as quantite
  from commande c
  join ligne    l on l.commande_id = c.id
  join article  a on a.id = l.article_id
  join rubrique r on r.id = a.rubrique_id
 where c.statut <> 'annule'
 group by c.site_id, c.jour, r.id, r.nom, a.id, a.nom, a.limite;

-- le rapprochement canal par canal
create view v_canal as
select p.site_id, p.jour,
       coalesce(m.nom, 'Non précisé') as canal,
       count(distinct p.id)           as nb_paiements,
       sum(p.montant)                 as encaisse
  from paiement p
  left join moyen_paiement m on m.id = p.moyen_id
 group by p.site_id, p.jour, m.nom;

-- ce qui manque, nommément
create view v_manquant as
select c.site_id, c.jour, c.id as commande_id,
       pe.nom, pe.tel, c.montant,
       c.montant - coalesce(sum(pc.montant_affecte), 0) as reste_du
  from commande c
  join personne pe on pe.id = c.personne_id
  left join paiement_commande pc on pc.commande_id = c.id
 where c.statut = 'du'
 group by c.site_id, c.jour, c.id, pe.nom, pe.tel, c.montant
having c.montant - coalesce(sum(pc.montant_affecte), 0) > 0;

-- doublons probables : même site, noms proches (à arbitrer, jamais fusionner seul)
create view v_doublon as
select a.site_id, a.id as garder, b.id as fusionner,
       a.nom as nom_a, b.nom as nom_b,
       round(similarity(a.nom_norm, b.nom_norm)::numeric, 3) as score
  from personne a
  join personne b
    on b.site_id = a.site_id and b.id > a.id
   and a.fusionnee_vers is null and b.fusionnee_vers is null
   and similarity(a.nom_norm, b.nom_norm) > 0.55
 order by score desc;

-- ---------------------------------------------------------------------
-- 8. Jeu de départ : le vrai menu de la semaine Dema
-- ---------------------------------------------------------------------
do $$
declare t uuid; r_plats uuid; r_dess uuid; r_jus uuid;
begin
  insert into traiteur (nom, tel) values ('Dema Traiteur', '76 882 03 12') returning id into t;

  insert into site (traiteur_id, nom, slug) values (t, 'Yas', 'yas'), (t, 'Orange', 'orange');

  insert into moyen_paiement (traiteur_id, code, nom, numero, ordre) values
    (t, 'wave', 'Wave',          '76 882 03 12', 1),
    (t, 'om',   'Orange Money',  '76 882 03 12', 2),
    (t, 'mixx', 'Mix by Yas',    '76 882 03 12', 3),
    (t, 'especes', 'Espèces',   null,           4);

  -- « unique » : un seul plat par personne et par jour, comme sur le vote
  -- WhatsApp. « quantite » reste vrai : on peut en prendre deux portions du
  -- même plat (pour un invité qu'on ne nomme pas), ce qui n'est pas la même
  -- chose que choisir deux plats différents.
  insert into rubrique (traiteur_id, nom, mode, obligatoire, quantite, par_jour, ordre)
       values (t, 'Plats du jour', 'unique',   true,  true,  true, 1) returning id into r_plats;
  insert into rubrique (traiteur_id, nom, mode, obligatoire, quantite, par_jour, ordre)
       values (t, 'Dessert',       'unique',   false, false, true, 2) returning id into r_dess;
  insert into rubrique (traiteur_id, nom, mode, obligatoire, quantite, par_jour, ordre)
       values (t, 'Jus',           'unique',   false, false, false, 3) returning id into r_jus;

  insert into article (rubrique_id, nom, prix, jour, ordre) values
    (r_plats, 'Thiebou guinar khew', 3000, 1, 1),
    (r_plats, 'Brochette de viandes, gratin de légumes', 3000, 1, 2),
    (r_plats, 'Thiebou diéune djagga', 3000, 2, 1),
    (r_plats, 'Lasagne', 3000, 2, 2),
    (r_plats, 'Mafé', 3000, 3, 1),
    (r_plats, 'Vermicelles poulet', 3000, 3, 2),
    (r_plats, 'Yassa poulet khew', 3000, 4, 1),
    (r_plats, 'Brochette de lottes, riz blanc et haricots sautés', 3000, 4, 2),
    (r_plats, 'Chawarma', 2500, 5, 1),
    (r_plats, 'Crêpes au jambon', 2500, 5, 2);

  insert into article (rubrique_id, nom, prix, jour, ordre) values
    (r_dess, 'Gaufres (Nutella, sucre, confit fraise)', 0,   1, 1),  -- offert, lancement
    (r_dess, 'Salade de fruits',                        700, 2, 1),
    (r_dess, 'Moelleux au chocolat',                    600, 3, 1),
    (r_dess, 'Crêpes (Nutella, sucre, confit fraise)',  700, 4, 1);
    -- vendredi : pas de dessert

  insert into article (rubrique_id, nom, prix, ordre) values
    (r_jus, 'Bissap', 500, 1),
    (r_jus, 'Bouye',  500, 2);
end $$;

-- =====================================================================
-- SÉCURITÉ — à lire avant de mettre en ligne
-- =====================================================================
-- La page est ouverte : pas de connexion, pas de mot de passe. Avec la clé
-- publique Supabase, n'importe qui peut appeler l'API. Donc :
--
--   1. activer RLS sur TOUTES les tables (alter table ... enable row level security)
--      et ne créer AUCUNE policy permissive par défaut ;
--   2. n'exposer que des fonctions `security definer` : fn_menu_du_jour(slug),
--      fn_enregistrer_commande(...), fn_declarer_paiement(...) ;
--   3. l'écran du traiteur passe par un compte authentifié, jamais par la clé
--      publique — c'est le seul endroit qui voit l'argent.
--
-- Sans ces trois points, un curieux lit tous les numéros de téléphone du site.
-- =====================================================================
