-- =====================================================================
-- Dema — la mise en route : le traiteur règle son menu lui-même
-- À passer dans le SQL Editor après dema_traiteur.sql.
-- =====================================================================
-- Sans ces fonctions, changer les plats du lundi demande d'écrire du SQL.
-- Avec elles, Fatoumata le fait depuis son téléphone, et toi tu n'es plus
-- dans la boucle — ce qui est la seule façon que l'outil lui survive.
--
-- Même règle que l'écran de suivi : réservé aux comptes rattachés à un
-- traiteur, et chaque fonction vérifie que l'objet touché lui appartient.
-- Un compte ne peut pas modifier le menu d'un autre traiteur.
-- ---------------------------------------------------------------------
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 0. Garde-fou commun
-- ---------------------------------------------------------------------
create or replace function fn_exige_traiteur()
returns uuid language plpgsql stable security definer
set search_path = public, extensions as $$
declare v_t uuid;
begin
  v_t := fn_mon_traiteur();
  if v_t is null then
    raise exception 'Ce compte n''est rattaché à aucun traiteur.';
  end if;
  return v_t;
end $$;

-- ---------------------------------------------------------------------
-- 1. Tout le réglage en un appel
-- ---------------------------------------------------------------------
create or replace function fn_config()
returns jsonb language plpgsql stable security definer
set search_path = public, extensions as $$
declare v_t uuid;
begin
  v_t := fn_exige_traiteur();

  return jsonb_build_object(
    'traiteur', (select nom from traiteur where id = v_t),

    'sites', (select coalesce(jsonb_agg(jsonb_build_object(
                'id', s.id, 'nom', s.nom, 'slug', s.slug,
                'cloture', to_char(s.cloture,'HH24:MI'), 'actif', s.actif,
                -- une entreprise qui a déjà reçu des commandes ne se supprime pas
                'engage', exists (select 1 from commande c where c.site_id = s.id))
                order by s.nom), '[]'::jsonb)
               from site s where s.traiteur_id = v_t),

    'moyens', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', m.id, 'code', m.code, 'nom', m.nom,
                 'numero', m.numero, 'actif', m.actif, 'ordre', m.ordre)
                 order by m.ordre), '[]'::jsonb)
                from moyen_paiement m where m.traiteur_id = v_t),

    'rubriques', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', r.id, 'nom', r.nom, 'mode', r.mode, 'ordre', r.ordre,
                    'obligatoire', r.obligatoire, 'quantite', r.quantite,
                    'par_jour', r.par_jour, 'offert', r.offert,
                    'articles', (select coalesce(jsonb_agg(jsonb_build_object(
                                   'id', a.id, 'nom', a.nom, 'prix', a.prix,
                                   'jour', a.jour, 'limite', a.limite,
                                   'actif', a.actif, 'ordre', a.ordre,
                                   'engage', exists (select 1 from ligne l where l.article_id = a.id))
                                   order by a.jour nulls first, a.ordre, a.nom), '[]'::jsonb)
                                   from article a where a.rubrique_id = r.id))
                    order by r.ordre), '[]'::jsonb)
                   from rubrique r where r.traiteur_id = v_t));
end $$;

-- ---------------------------------------------------------------------
-- 2. Rubriques
-- ---------------------------------------------------------------------
-- p_id vide = création. Sinon modification, après vérification d'appartenance.
create or replace function fn_rubrique_maj(
  p_id uuid, p_nom text, p_mode text, p_obligatoire boolean,
  p_quantite boolean, p_par_jour boolean, p_offert boolean, p_ordre int)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_t uuid; v_id uuid;
begin
  v_t := fn_exige_traiteur();
  if nullif(trim(coalesce(p_nom,'')),'') is null then
    raise exception 'Donne un nom à la rubrique.';
  end if;
  if p_mode not in ('unique','multiple') then
    raise exception 'Le mode doit être « unique » ou « multiple ».';
  end if;

  if p_id is null then
    insert into rubrique (traiteur_id, nom, mode, obligatoire, quantite, par_jour, offert, ordre)
    values (v_t, trim(p_nom), p_mode, p_obligatoire, p_quantite, p_par_jour, p_offert,
            coalesce(p_ordre, (select coalesce(max(ordre),0)+1 from rubrique where traiteur_id = v_t)))
    returning id into v_id;
  else
    update rubrique set nom = trim(p_nom), mode = p_mode, obligatoire = p_obligatoire,
           quantite = p_quantite, par_jour = p_par_jour, offert = p_offert,
           ordre = coalesce(p_ordre, ordre)
     where id = p_id and traiteur_id = v_t
    returning id into v_id;
    if v_id is null then raise exception 'Rubrique introuvable.'; end if;
  end if;
  return v_id;
end $$;

create or replace function fn_rubrique_suppr(p_id uuid)
returns text language plpgsql security definer
set search_path = public, extensions as $$
declare v_t uuid; v_n int;
begin
  v_t := fn_exige_traiteur();
  if not exists (select 1 from rubrique where id = p_id and traiteur_id = v_t) then
    raise exception 'Rubrique introuvable.';
  end if;
  select count(*) into v_n from ligne l join article a on a.id = l.article_id
   where a.rubrique_id = p_id;
  if v_n > 0 then
    raise exception 'Cette rubrique a déjà servi (% commandes). Désactive ses plats plutôt que de l''effacer.', v_n;
  end if;
  delete from article where rubrique_id = p_id;
  delete from rubrique where id = p_id;
  return 'supprimée';
end $$;

-- ---------------------------------------------------------------------
-- 3. Articles
-- ---------------------------------------------------------------------
create or replace function fn_article_maj(
  p_id uuid, p_rubrique uuid, p_nom text, p_prix int,
  p_jour int, p_limite int, p_ordre int, p_actif boolean)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_t uuid; v_id uuid; v_par_jour boolean;
begin
  v_t := fn_exige_traiteur();
  if nullif(trim(coalesce(p_nom,'')),'') is null then
    raise exception 'Donne un nom au plat.';
  end if;
  if p_prix is null or p_prix < 0 then
    raise exception 'Le prix doit être un nombre positif.';
  end if;
  if p_limite is not null and p_limite < 1 then
    raise exception 'La limite doit valoir au moins 1, ou rester vide.';
  end if;

  select par_jour into v_par_jour from rubrique
   where id = coalesce(p_rubrique, (select rubrique_id from article where id = p_id))
     and traiteur_id = v_t;
  if v_par_jour is null then raise exception 'Rubrique introuvable.'; end if;
  -- la contrainte existe déjà en base ; on la dit en clair ici
  if v_par_jour and p_jour is null then
    raise exception 'Cette rubrique change chaque jour : indique le jour.';
  end if;
  if not v_par_jour and p_jour is not null then
    raise exception 'Cette rubrique est la même tous les jours : ne mets pas de jour.';
  end if;

  if p_id is null then
    insert into article (rubrique_id, nom, prix, jour, limite, ordre, actif)
    values (p_rubrique, trim(p_nom), p_prix, p_jour, p_limite,
            coalesce(p_ordre, (select coalesce(max(ordre),0)+1 from article
                                where rubrique_id = p_rubrique
                                  and coalesce(jour,-1) = coalesce(p_jour,-1))),
            coalesce(p_actif, true))
    returning id into v_id;
  else
    -- Le prix n'est jamais relu sur les commandes déjà passées : elles gardent
    -- celui du moment où elles ont été faites (prix_unitaire sur la ligne).
    update article set nom = trim(p_nom), prix = p_prix, jour = p_jour,
           limite = p_limite, ordre = coalesce(p_ordre, ordre),
           actif = coalesce(p_actif, actif),
           rubrique_id = coalesce(p_rubrique, rubrique_id)
     where id = p_id
       and rubrique_id in (select id from rubrique where traiteur_id = v_t)
    returning id into v_id;
    if v_id is null then raise exception 'Plat introuvable.'; end if;
  end if;
  return v_id;
end $$;

-- Supprimer un plat déjà commandé casserait l'historique : on le désactive.
-- Il disparaît du menu, les commandes passées restent lisibles.
create or replace function fn_article_suppr(p_id uuid)
returns text language plpgsql security definer
set search_path = public, extensions as $$
declare v_t uuid; v_n int;
begin
  v_t := fn_exige_traiteur();
  if not exists (select 1 from article a join rubrique r on r.id = a.rubrique_id
                  where a.id = p_id and r.traiteur_id = v_t) then
    raise exception 'Plat introuvable.';
  end if;
  select count(*) into v_n from ligne where article_id = p_id;
  if v_n > 0 then
    update article set actif = false where id = p_id;
    return 'retiré du menu (il a déjà été commandé, l''historique est gardé)';
  end if;
  delete from article where id = p_id;
  return 'supprimé';
end $$;

-- ---------------------------------------------------------------------
-- 4. Entreprises servies
-- ---------------------------------------------------------------------
create or replace function fn_site_maj(
  p_id uuid, p_nom text, p_slug text, p_cloture text, p_actif boolean)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_t uuid; v_id uuid; v_slug text; v_h time;
begin
  v_t := fn_exige_traiteur();
  if nullif(trim(coalesce(p_nom,'')),'') is null then
    raise exception 'Donne un nom à l''entreprise.';
  end if;

  -- le slug devient l'adresse du lien : on le nettoie au lieu de refuser
  v_slug := lower(trim(coalesce(p_slug, p_nom)));
  v_slug := translate(v_slug, 'àâäéèêëîïôöùûüç', 'aaaeeeeiioouuuc');
  v_slug := regexp_replace(v_slug, '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug);
  if length(v_slug) < 2 then
    raise exception 'Le nom est trop court pour en faire une adresse.';
  end if;

  begin
    v_h := coalesce(nullif(p_cloture,''), '10:30')::time;
  exception when others then
    raise exception 'L''heure de clôture doit s''écrire comme 10:30.';
  end;

  if exists (select 1 from site where slug = v_slug and (p_id is null or id <> p_id)) then
    raise exception 'L''adresse « % » est déjà prise. Change le nom.', v_slug;
  end if;

  if p_id is null then
    insert into site (traiteur_id, nom, slug, cloture, actif)
    values (v_t, trim(p_nom), v_slug, v_h, coalesce(p_actif, true))
    returning id into v_id;
  else
    update site set nom = trim(p_nom), slug = v_slug, cloture = v_h,
           actif = coalesce(p_actif, actif)
     where id = p_id and traiteur_id = v_t
    returning id into v_id;
    if v_id is null then raise exception 'Entreprise introuvable.'; end if;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 5. Moyens de paiement
-- ---------------------------------------------------------------------
create or replace function fn_moyen_maj(
  p_id uuid, p_code text, p_nom text, p_numero text, p_actif boolean, p_ordre int)
returns uuid language plpgsql security definer
set search_path = public, extensions as $$
declare v_t uuid; v_id uuid; v_code text;
begin
  v_t := fn_exige_traiteur();
  if nullif(trim(coalesce(p_nom,'')),'') is null then
    raise exception 'Donne un nom au moyen de paiement.';
  end if;
  -- minuscules et accents d'abord, filtrage ensuite : l'inverse mangeait les
  -- majuscules (« Free Money » devenait « reeoney »).
  v_code := lower(coalesce(nullif(trim(p_code),''), p_nom));
  v_code := translate(v_code, 'àâäéèêëîïôöùûüç', 'aaaeeeeiioouuuc');
  v_code := regexp_replace(v_code, '[^a-z0-9]+', '', 'g');
  if length(v_code) < 2 then raise exception 'Nom trop court.'; end if;

  if p_id is null then
    insert into moyen_paiement (traiteur_id, code, nom, numero, actif, ordre)
    values (v_t, v_code, trim(p_nom), nullif(trim(coalesce(p_numero,'')),''),
            coalesce(p_actif, true),
            coalesce(p_ordre, (select coalesce(max(ordre),0)+1 from moyen_paiement where traiteur_id = v_t)))
    returning id into v_id;
  else
    update moyen_paiement set code = v_code, nom = trim(p_nom),
           numero = nullif(trim(coalesce(p_numero,'')),''),
           actif = coalesce(p_actif, actif), ordre = coalesce(p_ordre, ordre)
     where id = p_id and traiteur_id = v_t
    returning id into v_id;
    if v_id is null then raise exception 'Moyen de paiement introuvable.'; end if;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 6. Fermeture
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'fn_exige_traiteur()',
    'fn_config()',
    'fn_rubrique_maj(uuid,text,text,boolean,boolean,boolean,boolean,integer)',
    'fn_rubrique_suppr(uuid)',
    'fn_article_maj(uuid,uuid,text,integer,integer,integer,integer,boolean)',
    'fn_article_suppr(uuid)',
    'fn_site_maj(uuid,text,text,text,boolean)',
    'fn_moyen_maj(uuid,text,text,text,boolean,integer)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    if exists (select 1 from pg_roles where rolname = 'authenticated')
       and f <> 'fn_exige_traiteur()' then
      execute format('grant execute on function %s to authenticated', f);
    end if;
  end loop;
end $$;

-- Vérification : rien ne doit être exécutable par « anon ».
-- select p.proname, p.proacl from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public' and p.proname like 'fn_%' order by 1;
