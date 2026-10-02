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
                                   'nom', aa.nom, 'quantite', aa.quantite, 'limite', aa.limite)
                                   order by aa.quantite desc, aa.nom), '[]'::jsonb)
                            from (select a.nom, a.limite, sum(l.qte)::int as quantite
                                    from ligne l
                                    join commande c on c.id = l.commande_id
                                    join article a on a.id = l.article_id
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
           'site', q.site, 'qui', q.qui, 'moyen', q.moyen, 'montant', q.montant,
           'heure', q.heure, 'preuve', q.preuve, 'pour', q.pour)
           order by q.cree_le desc), '[]'::jsonb)
    into v_paiements
    from (select s.nom as site, pe.nom as qui, coalesce(m.nom,'Non précisé') as moyen,
                 p.montant, p.cree_le, p.preuve_url as preuve,
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
    'doublons',  v_doublons);
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
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'grant execute on function fn_tableau(date,text) to authenticated';
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
