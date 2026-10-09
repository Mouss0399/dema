-- =====================================================================
-- Dema — l'écran du traiteur : accès et données
-- À passer dans le SQL Editor après dema_api.sql.
-- =====================================================================
-- Cet écran est le seul qui voit les noms, les numéros et l'argent. Il ne
-- passe donc PAS par la clé publique : il faut un compte, et ce compte doit
-- être rattaché à un traiteur. Un inconnu qui créerait un compte Supabase
-- n'obtiendrait rien — être « connecté » ne suffit pas, il faut être inscrit
-- dans la table « compte » ci-dessous.
-- ---------------------------------------------------------------------
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- Mise à niveau d'une base déjà en service : le pointage des règlements.
-- Sans effet si les colonnes existent déjà, donc rejouable sans risque.
-- (Sur une installation neuve, dema_schema.sql les crée directement.)
-- ---------------------------------------------------------------------
alter table paiement add column if not exists pointe    boolean not null default false;
alter table paiement add column if not exists pointe_le timestamptz;

-- ---------------------------------------------------------------------
-- 1. Qui a le droit de voir quoi
-- ---------------------------------------------------------------------
-- user_id est l'identifiant du compte Supabase (auth.users.id). Pas de clé
-- étrangère vers auth.users : cette table appartient à Supabase et on évite
-- de s'y accrocher, pour que ce fichier reste rejouable et testable ailleurs.
create table if not exists compte (
  user_id     uuid primary key,
  traiteur_id uuid not null references traiteur(id) on delete cascade,
  nom         text not null,
  cree_le     timestamptz not null default now()
);
alter table compte enable row level security;   -- aucune politique : personne n'y touche
                                                -- sauf les fonctions ci-dessous (definer)

-- ---------------------------------------------------------------------
-- 2. Le traiteur du compte connecté
-- ---------------------------------------------------------------------
create or replace function fn_mon_traiteur()
returns uuid language sql stable security definer
set search_path = public, extensions as $$
  select traiteur_id from compte where user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- 3. Tout l'écran en un seul appel
-- ---------------------------------------------------------------------
-- Un seul aller-retour : sur un téléphone en 3G, six requêtes coûtent six
-- attentes. p_jour vide = aujourd'hui. p_site vide = toutes ses entreprises.
create or replace function fn_tableau(p_jour date default null, p_site text default null)
returns jsonb language plpgsql stable security definer
set search_path = public, extensions as $$
declare
  v_t uuid; v_jour date; v_sites uuid[]; v_tous uuid[];
  v_entreprises jsonb; v_cuisine jsonb; v_canaux jsonb;
  v_manquants jsonb; v_paiements jsonb; v_doublons jsonb; v_jours jsonb;
  v_arrivees jsonb;
  v_du int; v_enc int; v_cmd int;
begin
  v_t := fn_mon_traiteur();
  if v_t is null then
    raise exception 'Ce compte n''est rattaché à aucun traiteur.';
  end if;

  v_jour := coalesce(p_jour, (now() at time zone 'Africa/Dakar')::date);

  -- v_tous : toutes ses entreprises, pour la liste de choix — sinon, en
  -- filtrant sur l'une d'elles, elle n'aurait plus de bouton pour revenir.
  -- v_sites : celles que l'écran montre maintenant.
  select array_agg(id) into v_tous  from site where traiteur_id = v_t;
  select array_agg(id) into v_sites from site
   where traiteur_id = v_t and (p_site is null or slug = p_site);
  if v_tous is null then
    raise exception 'Aucune entreprise n''est rattachée à ce traiteur.';
  end if;
  if v_sites is null then
    raise exception 'Aucune entreprise ne correspond.';
  end if;

  -- Chaque morceau est calculé à part. C'est plus long à lire mais quand une
  -- erreur tombe, elle dit lequel — une requête de cent lignes ne le dit pas.
  -- Partout le même principe : on agrège d'abord, on habille en JSON ensuite.

  -- les jours où il s'est passé quelque chose, pour revenir en arrière
  select coalesce(jsonb_agg(j order by j desc), '[]'::jsonb) into v_jours
    from (select distinct c.jour as j from commande c
           where c.site_id = any(v_sites) and c.statut <> 'annule'
             and c.jour > v_jour - 30) q;

  -- une ligne par entreprise
  select coalesce(jsonb_agg(jsonb_build_object(
           'slug', q.slug, 'nom', q.nom, 'cloture', q.cloture,
           'commandes', q.commandes, 'du', q.du, 'encaisse', q.encaisse,
           'reste', q.du - q.encaisse) order by q.nom), '[]'::jsonb)
    into v_entreprises
    from (select s.slug, s.nom, to_char(s.cloture,'HH24:MI') as cloture,
                 (select count(*)::int from commande c
                   where c.site_id = s.id and c.jour = v_jour and c.statut <> 'annule') as commandes,
                 (select coalesce(sum(c.montant),0)::int from commande c
                   where c.site_id = s.id and c.jour = v_jour and c.statut <> 'annule') as du,
                 (select coalesce(sum(p.montant),0)::int from paiement p
                   where p.site_id = s.id and p.jour = v_jour) as encaisse
            from site s where s.id = any(v_tous)) q;

  -- ce qu'il faut préparer : la raison d'être de l'écran
  select coalesce(jsonb_agg(jsonb_build_object(
           'site', e.site, 'rubriques', e.rubriques) order by e.site), '[]'::jsonb)
    into v_cuisine
    from (
      select s.nom as site,
             (select coalesce(jsonb_agg(jsonb_build_object(
                       'nom', rr.rubrique, 'articles', rr.articles)
                       order by rr.ordre), '[]'::jsonb)
                from (
                  select r.nom as rubrique, r.ordre,
                         (select coalesce(jsonb_agg(jsonb_build_object(
                                   'nom', aa.nom, 'quantite', aa.quantite,
                                   'limite', aa.limite, 'qui', aa.qui)
                                   order by aa.quantite desc, aa.nom), '[]'::jsonb)
                            from (select a.nom, a.limite, sum(l.qte)::int as quantite,
                                         -- qui a pris ce plat : c'est la feuille de
                                         -- distribution. Le sondage WhatsApp montrait
                                         -- déjà les noms sous chaque option ; sans eux,
                                         -- elle ne sait pas à qui donner quoi à midi.
                                         jsonb_agg(jsonb_build_object(
                                           'nom', pe.nom, 'qte', l.qte,
                                           'paye', c.statut = 'paye')
                                           order by pe.nom) as qui
                                    from ligne l
                                    join commande c on c.id = l.commande_id
                                    join article a on a.id = l.article_id
                                    join personne pe on pe.id = c.personne_id
                                   where a.rubrique_id = r.id and c.site_id = s.id
                                     and c.jour = v_jour and c.statut <> 'annule'
                                   group by a.id, a.nom, a.limite) aa) as articles
                    from rubrique r
                   where r.traiteur_id = v_t
                     and exists (select 1 from ligne l
                                   join commande c on c.id = l.commande_id
                                   join article a on a.id = l.article_id
                                  where a.rubrique_id = r.id and c.site_id = s.id
                                    and c.jour = v_jour and c.statut <> 'annule')
                ) rr) as rubriques
        from site s
       where s.id = any(v_sites)
         and exists (select 1 from commande c
                      where c.site_id = s.id and c.jour = v_jour and c.statut <> 'annule')
    ) e;

  -- l'argent canal par canal : ce qu'elle rapproche de son relevé Wave
  select coalesce(jsonb_agg(jsonb_build_object(
           'canal', q.canal, 'nb', q.nb, 'encaisse', q.encaisse)
           order by q.encaisse desc), '[]'::jsonb)
    into v_canaux
    from (select coalesce(m.nom,'Non précisé') as canal,
                 count(distinct p.id)::int as nb,
                 sum(p.montant)::int as encaisse
            from paiement p
            left join moyen_paiement m on m.id = p.moyen_id
           where p.site_id = any(v_sites) and p.jour = v_jour
           group by m.nom) q;

  -- qui n'a pas payé, nommément, avec son numéro pour la relance
  select coalesce(jsonb_agg(jsonb_build_object(
           'site', q.site, 'nom', q.nom, 'tel', q.tel,
           'reste', q.reste, 'detail', q.detail) order by q.site, q.nom), '[]'::jsonb)
    into v_manquants
    from (select s.nom as site, pe.nom, pe.tel,
                 (c.montant - coalesce(sum(pc.montant_affecte),0))::int as reste,
                 (select string_agg(a.nom || case when l.qte>1 then ' × '||l.qte else '' end, ' + ')
                    from ligne l join article a on a.id=l.article_id
                   where l.commande_id = c.id) as detail
            from commande c
            join site s on s.id = c.site_id
            join personne pe on pe.id = c.personne_id
            left join paiement_commande pc on pc.commande_id = c.id
           where c.site_id = any(v_sites) and c.jour = v_jour and c.statut = 'du'
           group by s.nom, pe.nom, pe.tel, c.id, c.montant
          having c.montant - coalesce(sum(pc.montant_affecte),0) > 0) q;

  -- les règlements déclarés, et pour qui : ce qui remplace les captures
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', q.id,
           'site', q.site, 'qui', q.qui, 'moyen', q.moyen, 'montant', q.montant,
           'heure', q.heure, 'preuve', q.preuve, 'pointe', q.pointe, 'pour', q.pour)
           order by q.cree_le desc), '[]'::jsonb)
    into v_paiements
    from (select s.nom as site, pe.nom as qui, coalesce(m.nom,'Non précisé') as moyen,
                 p.id, p.montant, p.cree_le, p.preuve_url as preuve, p.pointe,
                 to_char(p.cree_le at time zone 'Africa/Dakar','HH24:MI') as heure,
                 (select coalesce(jsonb_agg(pe2.nom order by pe2.nom), '[]'::jsonb)
                    from paiement_commande pc
                    join commande c2 on c2.id = pc.commande_id
                    join personne pe2 on pe2.id = c2.personne_id
                   where pc.paiement_id = p.id and pe2.id <> pe.id) as pour
            from paiement p
            join site s on s.id = p.site_id
            join personne pe on pe.id = p.personne_id
            left join moyen_paiement m on m.id = p.moyen_id
           where p.site_id = any(v_sites) and p.jour = v_jour) q;

  -- noms proches : deux lignes pour la même personne, à arbitrer à la main
  select coalesce(jsonb_agg(jsonb_build_object(
           'site', q.site, 'a', q.a, 'b', q.b) order by q.a), '[]'::jsonb)
    into v_doublons
    from (select s.nom as site, p1.nom as a, p2.nom as b
            from personne p1
            join personne p2 on p2.site_id = p1.site_id and p2.id > p1.id
                            and p2.fusionnee_vers is null
            join site s on s.id = p1.site_id
           where p1.site_id = any(v_sites) and p1.fusionnee_vers is null
             and similarity(p1.nom_norm, p2.nom_norm) > 0.55) q;

  -- l'ordre d'arrivee : a quelle heure chacun a commande. C'est ce qu'elle
  -- demandait pour arbitrer ce qui tombe juste avant la cloture, et pour
  -- retrouver qui a commande en dernier quand il manque une part.
  -- cree_le est l'heure de la premiere commande du jour : une modification
  -- met a jour la meme ligne, elle ne la recree pas.
  select coalesce(jsonb_agg(jsonb_build_object(
           'site', q.site, 'nom', q.nom, 'heure', q.heure, 'detail', q.detail,
           'montant', q.montant, 'reste', q.reste, 'par', q.par)
           order by q.cree_le), '[]'::jsonb)
    into v_arrivees
    from (select s.nom as site, pe.nom, c.cree_le, c.montant::int as montant,
                 to_char(c.cree_le at time zone 'Africa/Dakar','HH24:MI') as heure,
                 (c.montant - coalesce((select sum(pc.montant_affecte)
                                          from paiement_commande pc
                                         where pc.commande_id = c.id), 0))::int as reste,
                 (select pe2.nom from personne pe2 where pe2.id = c.commandee_par) as par,
                 (select string_agg(a.nom || case when l.qte>1 then ' × '||l.qte else '' end, ' + ')
                    from ligne l join article a on a.id = l.article_id
                   where l.commande_id = c.id) as detail
            from commande c
            join site s on s.id = c.site_id
            join personne pe on pe.id = c.personne_id
           where c.site_id = any(v_sites) and c.jour = v_jour
             and c.statut <> 'annule') q;

  -- le total de ce qui est affiché (une entreprise, ou toutes)
  select count(*)::int, coalesce(sum(montant),0)::int into v_cmd, v_du
    from commande where site_id = any(v_sites) and jour = v_jour and statut <> 'annule';
  select coalesce(sum(montant),0)::int into v_enc
    from paiement where site_id = any(v_sites) and jour = v_jour;

  return jsonb_build_object(
    'traiteur',  (select nom from traiteur where id = v_t),
    'filtre',    p_site,
    'total',     jsonb_build_object('commandes', v_cmd, 'du', v_du,
                                    'encaisse', v_enc, 'reste', v_du - v_enc),
    'jour',      v_jour,
    'jours',     v_jours,
    'sites',     v_entreprises,
    'cuisine',   v_cuisine,
    'canaux',    v_canaux,
    'manquants', v_manquants,
    'paiements', v_paiements,
    'arrivees',  v_arrivees,
    'doublons',  v_doublons);
end $$;

-- ---------------------------------------------------------------------
-- 3 bis. Pointer un règlement
-- ---------------------------------------------------------------------
-- Le geste réel du traiteur : ouvrir Wave, descendre sa liste, cocher ce qui
-- correspond. Ce qui reste non coché à la fin est exactement ce qu'il faut
-- éclaircir. Sans cette trace, elle regarde une capture et, le lendemain, ne
-- sait plus lesquelles elle avait déjà vérifiées.
create or replace function fn_pointer(p_paiement uuid, p_pointe boolean)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare v_t uuid; v_ok boolean;
begin
  v_t := fn_mon_traiteur();
  if v_t is null then
    raise exception 'Ce compte n''est rattaché à aucun traiteur.';
  end if;

  update paiement p
     set pointe = coalesce(p_pointe, true),
         pointe_le = case when coalesce(p_pointe, true) then now() else null end
   where p.id = p_paiement
     and p.site_id in (select id from site where traiteur_id = v_t)
  returning true into v_ok;

  if v_ok is null then raise exception 'Règlement introuvable.'; end if;
  return jsonb_build_object('id', p_paiement, 'pointe', coalesce(p_pointe, true));
end $$;

-- ---------------------------------------------------------------------
-- 3 ter. Le traiteur saisit une commande
-- ---------------------------------------------------------------------
-- Quelqu'un l'appelle ou lui écrit en privé : « mets-moi un thiep ». Sans ce
-- bouton elle devrait ouvrir le lien employé et se faire passer pour lui, ce
-- qui attacherait SON téléphone au nom de cette personne.
--
-- Deux différences avec la commande d'un employé, assumées :
--   · elle peut passer outre l'heure de clôture — c'est son métier, pas une
--     règle technique : si elle accepte un retardataire, c'est sa décision ;
--   · elle peut servir n'importe quel jour déjà ouvert, pas seulement celui-ci.
-- Les limites de portions, elles, tiennent : elle ne peut pas vendre un plat
-- qu'elle n'a pas.
create or replace function fn_commander_pour(
  p_site text, p_nom text, p_lignes jsonb, p_jour date default null)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_t uuid; v_s site; v_jour date; v_dow smallint;
  v_p uuid; v_cid uuid; v_statut text; v_lig jsonb; v_art article;
  v_pris int; v_total int; v_r record; v_offert boolean; v_quantite boolean; v_qte int;
begin
  v_t := fn_exige_traiteur();

  select * into v_s from site where slug = p_site and traiteur_id = v_t;
  if not found then raise exception 'Entreprise introuvable.'; end if;

  v_jour := coalesce(p_jour, (now() at time zone 'Africa/Dakar')::date);
  v_dow  := extract(isodow from v_jour);

  if nullif(trim(coalesce(p_nom,'')),'') is null then
    raise exception 'Écris le nom de la personne.';
  end if;
  if coalesce(jsonb_array_length(p_lignes),0) = 0 then
    raise exception 'Choisis au moins un plat.';
  end if;

  -- la personne : retrouvée par son nom, créée si elle est nouvelle. Pas
  -- d'appareil : elle pourra s'inscrire plus tard et récupérer sa ligne.
  select id into v_p from personne
   where site_id = v_s.id and nom_norm = fn_norm(p_nom) and fusionnee_vers is null;
  if v_p is null then
    insert into personne (site_id, nom) values (v_s.id, trim(p_nom)) returning id into v_p;
  end if;

  v_cid := null; v_statut := null;
  select id, statut into v_cid, v_statut from commande
   where site_id = v_s.id and personne_id = v_p and jour = v_jour for update;
  if v_cid is not null then
    if v_statut = 'annule' then
      delete from ligne where commande_id = v_cid;
      update commande set statut = 'du' where id = v_cid;
    end if;
  else
    insert into commande (site_id, personne_id, jour)
    values (v_s.id, v_p, v_jour) returning id into v_cid;
  end if;

  for v_lig in select * from jsonb_array_elements(p_lignes) loop
    select * into v_art from article
     where id = (v_lig->>'article')::uuid and actif for update;
    if not found then raise exception 'Plat inconnu ou retiré du menu.'; end if;
    if not exists (select 1 from rubrique r
                    where r.id = v_art.rubrique_id and r.traiteur_id = v_t) then
      raise exception 'Ce plat n''est pas à toi.';
    end if;
    if v_art.jour is not null and v_art.jour <> v_dow then
      raise exception '% n''est pas au menu ce jour-là.', v_art.nom;
    end if;

    if v_art.limite is not null then
      select coalesce(sum(l.qte),0) into v_pris
        from ligne l join commande c on c.id = l.commande_id
       where l.article_id = v_art.id and c.jour = v_jour
         and c.site_id = v_s.id and c.statut <> 'annule';
      if v_pris + (v_lig->>'qte')::int > v_art.limite then
        raise exception '% : il n''en reste que %', v_art.nom, greatest(0, v_art.limite - v_pris);
      end if;
    end if;

    select offert, quantite into v_offert, v_quantite
      from rubrique where id = v_art.rubrique_id;

    insert into ligne (commande_id, article_id, qte, prix_unitaire)
    values (v_cid, v_art.id, (v_lig->>'qte')::int,
            case when v_offert then 0 else v_art.prix end)
    on conflict (commande_id, article_id) do update
      set qte = ligne.qte + excluded.qte
    returning qte into v_qte;

    if not v_quantite and v_qte > 1 then
      raise exception '% : une seule portion par personne', v_art.nom;
    end if;
  end loop;

  for v_r in
    select r.nom as nom from ligne l
      join article a on a.id = l.article_id
      join rubrique r on r.id = a.rubrique_id
     where l.commande_id = v_cid and r.mode = 'unique'
     group by r.id, r.nom having count(distinct l.article_id) > 1
  loop
    raise exception 'Un seul choix dans « % » : cette personne en a déjà un.', v_r.nom;
  end loop;

  select montant into v_total from commande where id = v_cid;
  return jsonb_build_object('commande', v_cid, 'nom', (select nom from personne where id = v_p),
                            'montant', v_total, 'jour', v_jour);
end $$;

-- Annuler côté traiteur : elle, contrairement à l'employé, peut annuler une
-- commande déjà réglée — c'est elle qui rendra l'argent, hors de l'outil.
-- Le versement reste enregistré : il est parti pour de vrai.
create or replace function fn_annuler_pour(p_commande uuid)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare v_t uuid; v_n int;
begin
  v_t := fn_exige_traiteur();
  update commande set statut = 'annule'
   where id = p_commande
     and site_id in (select id from site where traiteur_id = v_t)
     and statut <> 'annule';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Commande introuvable ou déjà annulée.'; end if;
  delete from ligne where commande_id = p_commande;
  return jsonb_build_object('commande', p_commande, 'annulee', true);
end $$;

-- ---------------------------------------------------------------------
-- 3 quater. Les clients
-- ---------------------------------------------------------------------
-- C'est ici que la dette cesse de fuir. L'écran du jour ne montre que les
-- impayés du jour affiché : un repas non réglé lundi disparaît de la vue dès
-- mardi, et l'outil aide alors à oublier — pire que pas d'outil du tout.
-- Cette liste porte le dû cumulé, toutes dates confondues.
create or replace function fn_clients(p_site text default null, p_q text default null)
returns jsonb language plpgsql stable security definer
set search_path = public, extensions as $$
declare v_t uuid; v_sites uuid[]; v_q text; v_gens jsonb; v_doublons jsonb;
begin
  v_t := fn_exige_traiteur();

  select array_agg(id) into v_sites from site
   where traiteur_id = v_t and (p_site is null or slug = p_site);
  if v_sites is null then raise exception 'Aucune entreprise ne correspond.'; end if;

  v_q := nullif(trim(coalesce(p_q,'')), '');

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', q.id, 'nom', q.nom, 'tel', q.tel, 'site', q.site,
           'inscrit', q.inscrit, 'du', q.du, 'repas', q.repas,
           'depense', q.depense, 'dernier', q.dernier)
           order by q.du desc, q.dernier desc nulls last, q.nom), '[]'::jsonb)
    into v_gens
    from (
      select pe.id, pe.nom, pe.tel, s.nom as site,
             (pe.appareil is not null) as inscrit,
             coalesce((select sum(c.montant - coalesce((select sum(pc.montant_affecte)
                         from paiement_commande pc where pc.commande_id = c.id), 0))
                         from commande c
                        where c.personne_id = pe.id and c.statut = 'du'), 0)::int as du,
             coalesce((select count(*) from commande c
                        where c.personne_id = pe.id and c.statut <> 'annule'
                          and c.jour > (now() at time zone 'Africa/Dakar')::date - 30), 0)::int as repas,
             coalesce((select sum(c.montant) from commande c
                        where c.personne_id = pe.id and c.statut <> 'annule'
                          and c.jour > (now() at time zone 'Africa/Dakar')::date - 30), 0)::int as depense,
             (select max(c.jour) from commande c
               where c.personne_id = pe.id and c.statut <> 'annule') as dernier
        from personne pe
        join site s on s.id = pe.site_id
       where pe.site_id = any(v_sites) and pe.fusionnee_vers is null
         and (v_q is null
              or pe.nom_norm like '%' || fn_norm(v_q) || '%'
              or coalesce(pe.tel_norm,'') like '%' || coalesce(fn_norm_tel(v_q), fn_norm(v_q)) || '%')
    ) q;

  -- noms proches : à arbitrer à la main, jamais fusionnés tout seuls
  select coalesce(jsonb_agg(jsonb_build_object(
           'site', d.site, 'a', d.a, 'a_id', d.a_id, 'b', d.b, 'b_id', d.b_id)
           order by d.a), '[]'::jsonb)
    into v_doublons
    from (select s.nom as site, p1.nom as a, p1.id as a_id, p2.nom as b, p2.id as b_id
            from personne p1
            join personne p2 on p2.site_id = p1.site_id and p2.id > p1.id
                            and p2.fusionnee_vers is null
            join site s on s.id = p1.site_id
           where p1.site_id = any(v_sites) and p1.fusionnee_vers is null
             and similarity(p1.nom_norm, p2.nom_norm) > 0.55) d;

  return jsonb_build_object('clients', v_gens, 'doublons', v_doublons);
end $$;

-- ---------------------------------------------------------------------
-- Corriger une fiche
-- ---------------------------------------------------------------------
create or replace function fn_client_maj(p_personne uuid, p_nom text, p_tel text)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare v_t uuid; v_p personne;
begin
  v_t := fn_exige_traiteur();
  select * into v_p from personne
   where id = p_personne and site_id in (select id from site where traiteur_id = v_t);
  if not found then raise exception 'Personne introuvable.'; end if;
  if length(trim(coalesce(p_nom,''))) < 2 then raise exception 'Le nom est trop court.'; end if;

  update personne set nom = trim(p_nom), tel = nullif(trim(coalesce(p_tel,'')),'')
   where id = p_personne;
  return jsonb_build_object('id', p_personne, 'nom', trim(p_nom));
exception
  when unique_violation then
    raise exception 'Ce nom ou ce numéro est déjà utilisé par quelqu''un d''autre sur ce site.';
end $$;

-- ---------------------------------------------------------------------
-- Fusionner deux fiches
-- ---------------------------------------------------------------------
-- Détecter un doublon sans pouvoir le réparer n'est que de l'agacement.
-- Le cas délicat : les deux fiches ont une commande le MÊME jour. On ne peut
-- pas simplement rattacher, la contrainte « une commande par personne et par
-- jour » s'y oppose — on verse donc les plats dans la commande conservée.
create or replace function fn_fusionner(p_garde uuid, p_absorbe uuid)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare
  v_t uuid; v_g personne; v_a personne; v_c record; v_cible uuid; v_n int := 0;
begin
  v_t := fn_exige_traiteur();
  if p_garde = p_absorbe then raise exception 'Ce sont les mêmes fiches.'; end if;

  select * into v_g from personne
   where id = p_garde and site_id in (select id from site where traiteur_id = v_t);
  if not found then raise exception 'Fiche à conserver introuvable.'; end if;
  select * into v_a from personne
   where id = p_absorbe and site_id in (select id from site where traiteur_id = v_t);
  if not found then raise exception 'Fiche à absorber introuvable.'; end if;
  if v_g.site_id <> v_a.site_id then
    raise exception 'Ces deux fiches ne sont pas dans la même entreprise.';
  end if;
  if v_a.fusionnee_vers is not null then raise exception 'Cette fiche est déjà fusionnée.'; end if;

  for v_c in select * from commande where personne_id = v_a.id loop
    select id into v_cible from commande
     where personne_id = v_g.id and jour = v_c.jour and site_id = v_c.site_id;
    if v_cible is null then
      update commande set personne_id = v_g.id where id = v_c.id;
    else
      -- même jour des deux côtés : on verse les plats dans celle qu'on garde
      insert into ligne (commande_id, article_id, qte, prix_unitaire)
        select v_cible, l.article_id, l.qte, l.prix_unitaire
          from ligne l where l.commande_id = v_c.id
      on conflict (commande_id, article_id) do update
        set qte = ligne.qte + excluded.qte;
      update paiement_commande set commande_id = v_cible where commande_id = v_c.id;
      delete from ligne where commande_id = v_c.id;
      delete from commande where id = v_c.id;
      perform fn_recalc(v_cible);
    end if;
    v_n := v_n + 1;
  end loop;

  update commande set commandee_par = v_g.id where commandee_par = v_a.id;
  update paiement set personne_id = v_g.id where personne_id = v_a.id;

  -- la fiche conservée hérite de ce qui lui manque
  update personne set
    appareil = coalesce(v_g.appareil, v_a.appareil),
    tel      = coalesce(nullif(trim(coalesce(v_g.tel,'')),''), v_a.tel)
   where id = v_g.id;

  update personne set fusionnee_vers = v_g.id, appareil = null
   where id = v_a.id;

  return jsonb_build_object('garde', v_g.id, 'nom', v_g.nom, 'commandes', v_n);
end $$;

-- ---------------------------------------------------------------------
-- 4. Fermeture : ces fonctions ne sont PAS publiques
-- ---------------------------------------------------------------------
-- PostgreSQL donne l'exécution à tout le monde par défaut. On retire, puis on
-- ne rend qu'aux comptes connectés — et la fonction vérifie elle-même que le
-- compte est rattaché à un traiteur.
do $$
begin
  execute 'revoke execute on function fn_mon_traiteur()         from public';
  execute 'revoke execute on function fn_tableau(date,text)     from public';
  execute 'revoke execute on function fn_pointer(uuid,boolean)  from public';
  execute 'revoke execute on function fn_commander_pour(text,text,jsonb,date) from public';
  execute 'revoke execute on function fn_annuler_pour(uuid)                   from public';
  execute 'revoke execute on function fn_clients(text,text)                   from public';
  execute 'revoke execute on function fn_client_maj(uuid,text,text)           from public';
  execute 'revoke execute on function fn_fusionner(uuid,uuid)                 from public';
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function fn_tableau(date,text) to authenticated';
    execute 'grant execute on function fn_pointer(uuid,boolean) to authenticated';
    execute 'grant execute on function fn_commander_pour(text,text,jsonb,date) to authenticated';
    execute 'grant execute on function fn_annuler_pour(uuid)                   to authenticated';
    execute 'grant execute on function fn_clients(text,text)                   to authenticated';
    execute 'grant execute on function fn_client_maj(uuid,text,text)           to authenticated';
    execute 'grant execute on function fn_fusionner(uuid,uuid)                 to authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on compte from anon';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Rattacher le compte de Fatoumata
-- ---------------------------------------------------------------------
-- Dans le tableau de bord Supabase : Authentication → Users → Add user,
-- avec son adresse et un mot de passe provisoire. Puis, ici, en remplaçant
-- l'adresse :
--
-- insert into compte (user_id, traiteur_id, nom)
-- select u.id, t.id, 'Fatoumata'
--   from auth.users u, traiteur t
--  where u.email = 'adresse-de-fatoumata@exemple.sn'
--    and t.nom   = 'Dema Traiteur'
-- on conflict (user_id) do nothing;
--
-- Vérification :
-- select c.nom, t.nom as traiteur from compte c join traiteur t on t.id = c.traiteur_id;
