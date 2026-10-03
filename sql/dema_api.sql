-- =====================================================================
-- Dema — surface d'API publique
-- =====================================================================
-- La page est ouverte : pas de connexion, pas de mot de passe. Donc aucune
-- table n'est exposée. Tout passe par ces fonctions `security definer`,
-- qui sont le seul endroit où l'on écrit.
--
-- Règle de base : ce que le navigateur envoie n'est jamais cru.
--   · le prix vient de la base, jamais du client
--   · la limite est vérifiée AU MOMENT DE L'ÉCRITURE, sous verrou
--   · l'heure de clôture est vérifiée côté serveur
--   · l'appareil ne peut agir que pour lui-même
-- =====================================================================

-- ---------------------------------------------------------------------
-- Le numéro comme identité
-- ---------------------------------------------------------------------
-- Un nom ne se rapproche qu'approximativement : « Awa Ndiaye » et
-- « Awa Ndiay » ne se rejoignent que par un calcul de similarité, qui rate
-- des doublons et en invente. Un numéro, lui, se normalise exactement.
-- Il devient donc la clé ; le nom reste l'étiquette, parce que c'est un nom
-- qu'il faut lire pour distribuer les repas, pas un numéro.
create or replace function fn_norm_tel(txt text) returns text
language sql immutable as $$
  select nullif(
    regexp_replace(
      regexp_replace(regexp_replace(coalesce(txt,''), '[^0-9]', '', 'g'),
                     '^(00221|221)', ''),
      '^0+', ''),
    '');
$$;

-- Mise à niveau d'une base déjà en service. Sans effet si déjà fait.
alter table personne add column if not exists tel_norm text
  generated always as (fn_norm_tel(tel)) stored;

do $$
begin
  create unique index if not exists uq_personne_tel on personne (site_id, tel_norm)
    where tel_norm is not null and fusionnee_vers is null;
exception when unique_violation then
  raise exception 'Deux personnes partagent déjà un numéro sur un même site. '
    'Corrige-les avant de rejouer : select site_id, tel_norm, count(*) '
    'from personne where tel_norm is not null and fusionnee_vers is null '
    'group by 1,2 having count(*) > 1;';
end $$;

-- ---------------------------------------------------------------------
-- Verrouillage : rien n'est lisible ni écrivable en direct
-- ---------------------------------------------------------------------
do $$
declare t text; r text;
begin
  -- 1. RLS sur les tables
  foreach t in array array['traiteur','site','moyen_paiement','rubrique','article',
                           'personne','commande','ligne','paiement','paiement_commande']
  loop
    execute format('alter table %I enable row level security', t);
  end loop;

  -- 2. Les VUES n'ont pas de RLS. Sans ce retrait, v_manquant exposerait
  --    les noms, les numéros de téléphone et les montants dus à qui possède
  --    la clé publique — c'est-à-dire à n'importe quel visiteur de la page.
  --
  -- 3. Et révoquer « from public » ne suffit pas : Supabase accorde les droits
  --    DIRECTEMENT aux rôles anon et authenticated, via les default privileges.
  --    Il faut donc les viser nommément, tables et vues comprises.
  for r in select rolname from pg_roles where rolname in ('anon','authenticated') loop
    execute format('revoke all on all tables in schema public from %I', r);
    execute format('revoke all on all sequences in schema public from %I', r);
    execute format('alter default privileges in schema public revoke all on tables from %I', r);
    execute format('alter default privileges in schema public revoke all on sequences from %I', r);
  end loop;
  revoke all on all tables in schema public from public;
end $$;

-- ---------------------------------------------------------------------
-- Utilitaires internes
-- ---------------------------------------------------------------------
create or replace function fn_site(p_slug text)
returns site language sql stable security definer set search_path = public, extensions as $$
  select * from site where slug = p_slug and actif;
$$;

-- jour ISO (1 = lundi) dans le fuseau de Dakar
create or replace function fn_aujourdhui()
returns date language sql stable as $$
  select (now() at time zone 'Africa/Dakar')::date;
$$;

-- ---------------------------------------------------------------------
-- 0 bis. Montant et statut d'une commande : recalculés, jamais saisis
-- ---------------------------------------------------------------------
-- Les deux vont ensemble. Le statut dépend du montant, donc TOUT changement
-- de lignes doit le refaire — pas seulement un paiement. Sans cela, ajouter
-- un jus à une commande déjà réglée laissait le statut à « payé » : le
-- complément dû n'apparaissait nulle part, ni pour l'employé ni pour le
-- traiteur. C'est la raison pour laquelle l'ajout était interdit ; c'est
-- l'interdiction qui était le mauvais remède.
create or replace function fn_recalc(p_cmd uuid) returns void
language plpgsql as $$
begin
  update commande c
     set montant = coalesce((select sum(l.qte * l.prix_unitaire)
                               from ligne l where l.commande_id = p_cmd), 0)
   where c.id = p_cmd;

  update commande c
     set statut = case
       when c.statut = 'annule' then 'annule'
       when coalesce((select sum(pc.montant_affecte) from paiement_commande pc
                       where pc.commande_id = p_cmd), 0) >= c.montant then 'paye'
       else 'du' end
   where c.id = p_cmd;
end $$;

create or replace function fn_maj_montant() returns trigger
language plpgsql as $$
begin
  perform fn_recalc(coalesce(new.commande_id, old.commande_id));
  return null;
end $$;

create or replace function fn_maj_statut() returns trigger
language plpgsql as $$
begin
  perform fn_recalc(coalesce(new.commande_id, old.commande_id));
  return null;
end $$;

drop trigger if exists trg_maj_montant on ligne;
create trigger trg_maj_montant after insert or update or delete on ligne
for each row execute function fn_maj_montant();

drop trigger if exists trg_maj_statut on paiement_commande;
create trigger trg_maj_statut after insert or update or delete on paiement_commande
for each row execute function fn_maj_statut();

-- ---------------------------------------------------------------------
-- 1. Le menu du jour, avec le reste disponible et le compte social
-- ---------------------------------------------------------------------
-- la signature a changé (ajout de p_appareil) : on retire l'ancienne,
-- sinon PostgreSQL garderait les deux et l'appel deviendrait ambigu.
drop function if exists fn_menu(text);
create or replace function fn_menu(p_slug text, p_appareil text default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_site site; v_jour date; v_dow smallint; v_res jsonb; v_deja jsonb;
begin
  v_site := fn_site(p_slug);
  if v_site.id is null then raise exception 'Site inconnu'; end if;
  v_jour := fn_aujourdhui();
  v_dow  := extract(isodow from v_jour);

  select jsonb_build_object(
    'site',    v_site.nom,
    'jour',    v_jour,
    'cloture', to_char(v_site.cloture,'HH24:MI'),
    'ouvert',  (now() at time zone 'Africa/Dakar')::time < v_site.cloture,
    'commandes_du_jour',
       (select count(*) from commande c
         where c.site_id = v_site.id and c.jour = v_jour and c.statut <> 'annule'),
    'moyens',
       (select coalesce(jsonb_agg(jsonb_build_object(
                 'code', mp.code, 'nom', mp.nom, 'numero', mp.numero) order by mp.ordre), '[]'::jsonb)
          from moyen_paiement mp
         where mp.traiteur_id = v_site.traiteur_id and mp.actif),
    'rubriques', coalesce(jsonb_agg(x order by x->>'ordre'), '[]'::jsonb))
    into v_res
  from (
    select jsonb_build_object(
      'id', r.id, 'nom', r.nom, 'mode', r.mode, 'ordre', r.ordre,
      'obligatoire', r.obligatoire, 'quantite', r.quantite, 'offert', r.offert,
      'articles', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', a.id, 'nom', a.nom,
          'prix', case when r.offert then 0 else a.prix end,
          'limite', a.limite,
          'pris', coalesce(q.pris, 0),
          'reste', case when a.limite is null then null
                        else greatest(0, a.limite - coalesce(q.pris,0)) end,
          'qui', coalesce(q.qui, '[]'::jsonb)
        ) order by a.ordre), '[]'::jsonb)
        from article a
        left join lateral (
          select sum(l.qte)::int as pris,
                 jsonb_agg(split_part(pe.nom,' ',1) order by pe.nom) as qui
            from ligne l
            join commande c on c.id = l.commande_id
            join personne pe on pe.id = c.personne_id
           where l.article_id = a.id and c.jour = v_jour
             and c.site_id = v_site.id and c.statut <> 'annule'
        ) q on true
        where a.rubrique_id = r.id and a.actif
          and (a.jour is null or a.jour = v_dow)
      )) as x
    from rubrique r
    where r.traiteur_id = v_site.traiteur_id
  ) s
  where jsonb_array_length(x->'articles') > 0;

  -- Ce que cet appareil a déjà commandé aujourd'hui : pour lui et pour les
  -- autres. Permet à la page de rappeler sa commande au lieu d'en ouvrir une
  -- seconde, qui serait refusée par la contrainte d'unicité.
  if p_appareil is not null then
    select coalesce(jsonb_agg(d order by (d->>'moi')::boolean desc, d->>'nom'), '[]'::jsonb)
      into v_deja
    from (
      select jsonb_build_object(
        'id',      c.id,
        'nom',     pe.nom,
        'moi',     (c.personne_id = mo.id),
        'montant', c.montant,
        'reste',   (c.montant - coalesce((select sum(pc.montant_affecte)
                      from paiement_commande pc where pc.commande_id = c.id), 0))::int,
        'statut',  c.statut,
        -- le détail par rubrique, pour que la page sache ce qui est déjà pris :
        -- sans ça, elle laissait choisir un second plat du jour que le serveur
        -- refusait ensuite — le refus était juste, l'avoir laissé proposer non
        'pris',    (select coalesce(jsonb_object_agg(x.rub, x.nom), '{}'::jsonb)
                      from (select a.rubrique_id::text as rub,
                                   string_agg(a.nom, ', ' order by a.nom) as nom
                              from ligne l join article a on a.id = l.article_id
                             where l.commande_id = c.id
                             group by a.rubrique_id) x),
        'detail',  (select string_agg(a.nom || case when l.qte>1 then ' × '||l.qte else '' end, ' + ')
                      from ligne l join article a on a.id = l.article_id
                     where l.commande_id = c.id)) as d
        from commande c
        join personne pe on pe.id = c.personne_id
        join personne mo on mo.site_id = v_site.id and mo.appareil = p_appareil
                        and mo.fusionnee_vers is null
       where c.site_id = v_site.id and c.jour = v_jour and c.statut <> 'annule'
         and (c.personne_id = mo.id or c.commandee_par = mo.id)
    ) t;
  end if;
  -- « inscrit » : le serveur reconnaît-il cet appareil ? Le téléphone peut se
  -- souvenir d'un nom que la base a perdu (remise à zéro, personne fusionnée).
  -- Sans ce drapeau, la page sautait l'inscription et toutes les actions
  -- échouaient sur « Appareil non inscrit ».
  v_res := v_res || jsonb_build_object(
    'deja',    coalesce(v_deja, '[]'::jsonb),
    'inscrit', (p_appareil is not null and exists (
                  select 1 from personne
                   where site_id = v_site.id and appareil = p_appareil
                     and fusionnee_vers is null)));

  return v_res;
end $$;

-- ---------------------------------------------------------------------
-- 2. Inscription — une fois par appareil
-- ---------------------------------------------------------------------
create or replace function fn_suggestions(p_slug text, p_nom text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_site site;
begin
  v_site := fn_site(p_slug);
  if v_site.id is null then raise exception 'Site inconnu'; end if;
  -- deux chemins : la frappe en cours (préfixe) et la faute d'orthographe
  -- (trigrammes). « Awa » ne fait que 0,36 de similarité avec « Awa Ndiaye » :
  -- le préfixe est indispensable, le score seul ne suffit pas.
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'nom', nom, 'pris', appareil is not null) order by s desc), '[]'::jsonb)
          from (select nom, appareil,
                       greatest(similarity(nom_norm, fn_norm(p_nom)),
                                case when nom_norm like fn_norm(p_nom) || '%'
                                     then 0.9 else 0 end) s
                  from personne
                 where site_id = v_site.id and fusionnee_vers is null
                   and (nom_norm like fn_norm(p_nom) || '%'
                        or similarity(nom_norm, fn_norm(p_nom)) > 0.45)
                 order by s desc limit 4) t);
end $$;

create or replace function fn_inscrire(
  p_slug text, p_nom text, p_tel text, p_appareil text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_site site; v_p personne; v_tel text;
begin
  v_site := fn_site(p_slug);
  if v_site.id is null then raise exception 'Site inconnu'; end if;
  if length(trim(coalesce(p_nom,''))) < 2 then raise exception 'Écris ton nom'; end if;
  if coalesce(p_appareil,'') = '' then raise exception 'Appareil manquant'; end if;

  v_tel := fn_norm_tel(p_tel);
  if v_tel is null then
    raise exception 'Ton numéro est nécessaire : c''est lui qui te retrouve si tu changes de navigateur.';
  end if;
  if length(v_tel) < 9 then
    raise exception 'Ce numéro est trop court. Écris-le comme 77 123 45 67.';
  end if;

  -- 1. déjà connu sur cet appareil : rien à faire
  select * into v_p from personne
   where site_id = v_site.id and appareil = p_appareil and fusionnee_vers is null;
  if found and fn_norm_tel(v_p.tel) = v_tel then
    return jsonb_build_object('id', v_p.id, 'nom', v_p.nom, 'nouveau', false, 'repris', false);
  end if;

  -- 2. ce numéro est déjà inscrit : c'est la même personne sur un autre
  --    navigateur. On rattache ce navigateur à sa fiche — c'est exactement le
  --    cas « j'ai ouvert depuis WhatsApp hier et depuis Chrome aujourd'hui ».
  select * into v_p from personne
   where site_id = v_site.id and tel_norm = v_tel and fusionnee_vers is null;
  if found then
    update personne set appareil = p_appareil where id = v_p.id;
    return jsonb_build_object('id', v_p.id, 'nom', v_p.nom, 'nouveau', false,
                              'repris', v_p.appareil is distinct from p_appareil);
  end if;

  -- 3. ce nom existe sans numéro : fiche créée par un collègue qui a commandé
  --    pour cette personne. Elle la récupère en s'inscrivant.
  select * into v_p from personne
   where site_id = v_site.id and nom_norm = fn_norm(p_nom) and fusionnee_vers is null;
  if found then
    if v_p.tel_norm is not null then
      raise exception 'Ce nom est déjà pris par quelqu''un d''autre sur ce site. Ajoute ton nom de famille.';
    end if;
    update personne set appareil = p_appareil, tel = trim(p_tel)
     where id = v_p.id returning * into v_p;
    return jsonb_build_object('id', v_p.id, 'nom', v_p.nom, 'nouveau', false, 'repris', true);
  end if;

  insert into personne (site_id, nom, tel, appareil)
  values (v_site.id, trim(p_nom), trim(p_tel), p_appareil)
  returning * into v_p;
  return jsonb_build_object('id', v_p.id, 'nom', v_p.nom, 'nouveau', true, 'repris', false);
end $$;

-- ---------------------------------------------------------------------
-- 3. Commander — pour soi et pour d'autres, en une transaction
-- ---------------------------------------------------------------------
-- p_commandes : [{"pour": null | "Prénom Nom",
--                 "lignes": [{"article": "<uuid>", "qte": 1}, ...]}, ...]
create or replace function fn_commander(
  p_slug text, p_appareil text, p_commandes jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_site site; v_jour date; v_dow smallint;
  v_moi personne; v_cmd jsonb; v_lig jsonb;
  v_benef uuid; v_nom text; v_cid uuid; v_statut text; v_art article; v_r record;
  v_offert boolean; v_quantite boolean; v_qte int;
  v_pris int; v_total int := 0; v_ids uuid[] := '{}';
begin
  v_site := fn_site(p_slug);
  if v_site.id is null then raise exception 'Site inconnu'; end if;
  v_jour := fn_aujourdhui();
  v_dow  := extract(isodow from v_jour);

  if (now() at time zone 'Africa/Dakar')::time >= v_site.cloture then
    raise exception 'Les commandes sont closes depuis %', to_char(v_site.cloture,'HH24:MI');
  end if;

  select * into v_moi from personne
   where site_id = v_site.id and appareil = p_appareil and fusionnee_vers is null;
  if not found then raise exception 'Appareil non inscrit'; end if;

  for v_cmd in select * from jsonb_array_elements(p_commandes) loop
    v_nom := nullif(trim(coalesce(v_cmd->>'pour','')), '');
    if v_nom is null then
      v_benef := v_moi.id;
    else
      select id into v_benef from personne
       where site_id = v_site.id and nom_norm = fn_norm(v_nom) and fusionnee_vers is null;
      if v_benef is null then
        insert into personne (site_id, nom) values (v_site.id, v_nom) returning id into v_benef;
      end if;
    end if;

    -- Une personne n'a qu'une commande par jour (contrainte uq_une_commande_par_jour).
    -- Si elle en a déjà une : on la complète quand c'est la sienne, on refuse
    -- clairement quand c'est celle de quelqu'un d'autre — sinon on ajouterait un
    -- second plat à un collègue qui a déjà commandé pour lui-même.
    v_cid := null; v_statut := null;
    select id, statut into v_cid, v_statut from commande
     where site_id = v_site.id and personne_id = v_benef and jour = v_jour
     for update;

    if v_cid is not null then
      if v_benef <> v_moi.id then
        raise exception '% a déjà commandé aujourd''hui',
          split_part((select nom from personne where id = v_benef), ' ', 1);
      end if;
      -- Une commande déjà réglée peut être complétée tant que les commandes
      -- sont ouvertes : la cuisine n'a pas commencé et la personne paiera la
      -- différence. Le recalcul la remet en « dû » pour le seul complément.
      if v_statut = 'annule' then
        -- on réutilise la ligne (contrainte d'unicité) mais on repart de zéro :
        -- garder les anciens plats ferait réapparaître ce qui vient d'être annulé
        delete from ligne where commande_id = v_cid;
        update commande set statut = 'du' where id = v_cid;
      end if;
    else
      insert into commande (site_id, personne_id, jour, commandee_par)
      values (v_site.id, v_benef, v_jour, case when v_benef = v_moi.id then null else v_moi.id end)
      returning id into v_cid;
    end if;
    if not (v_cid = any(v_ids)) then v_ids := v_ids || v_cid; end if;

    for v_lig in select * from jsonb_array_elements(v_cmd->'lignes') loop
      -- verrou sur l'article : deux personnes ne peuvent pas prendre le dernier plat
      select * into v_art from article
       where id = (v_lig->>'article')::uuid and actif for update;
      if not found then raise exception 'Article inconnu ou inactif'; end if;
      if v_art.jour is not null and v_art.jour <> v_dow then
        raise exception '% n''est pas au menu aujourd''hui', v_art.nom;
      end if;

      if v_art.limite is not null then
        select coalesce(sum(l.qte),0) into v_pris
          from ligne l join commande c on c.id = l.commande_id
         where l.article_id = v_art.id and c.jour = v_jour
           and c.site_id = v_site.id and c.statut <> 'annule';
        if v_pris + (v_lig->>'qte')::int > v_art.limite then
          raise exception '% : il n''en reste que %', v_art.nom, greatest(0, v_art.limite - v_pris);
        end if;
      end if;

      select offert, quantite into v_offert, v_quantite
        from rubrique where id = v_art.rubrique_id;

      -- Le prix vient de la base, jamais du client. Et si l'article est déjà
      -- dans la commande — « j'en reprends une portion » —, on ajoute à la
      -- quantité au lieu d'échouer. Le prix de la première fois est conservé :
      -- un changement de tarif en cours de matinée ne bouge pas une commande
      -- déjà passée.
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

    -- Une rubrique « choix unique » — le plat du jour — ne doit pas finir avec
    -- deux articles. La page l'empêche dans un même écran, mais quelqu'un qui
    -- complète sa commande une heure plus tard passerait à travers : on vérifie
    -- donc la commande entière, pas seulement ce qui vient d'être ajouté.
    for v_r in
      select r.nom as nom
        from ligne l
        join article a on a.id = l.article_id
        join rubrique r on r.id = a.rubrique_id
       where l.commande_id = v_cid and r.mode = 'unique'
       group by r.id, r.nom
      having count(distinct l.article_id) > 1
    loop
      raise exception 'Un seul choix dans « % » — tu en as déjà un dans ta commande du jour.', v_r.nom;
    end loop;
  end loop;

  -- ce qui reste dû, pas le total de la commande : si une partie est déjà
  -- réglée, l'écran ne doit annoncer que la différence
  select coalesce(sum(c.montant - coalesce(pc.affecte,0)),0)::int into v_total
    from commande c
    left join lateral (select sum(montant_affecte) as affecte from paiement_commande
                        where commande_id = c.id) pc on true
   where c.id = any(v_ids);
  return jsonb_build_object('commandes', to_jsonb(v_ids), 'total', v_total);
end $$;

-- ---------------------------------------------------------------------
-- 3 bis. Annuler sa commande
-- ---------------------------------------------------------------------
-- Une réunion tombe, on s'est trompé de plat : sans ce bouton, la personne
-- écrit au traiteur, et c'est précisément le message qu'on voulait supprimer.
-- Une seule limite, et elle est réelle : si le paiement est parti, il est
-- parti — chez Wave, pas chez nous. On ne peut pas le rappeler, donc on
-- renvoie vers le traiteur en disant pourquoi.
create or replace function fn_annuler(p_slug text, p_appareil text, p_commande uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_site site; v_moi personne; v_c commande; v_paye int;
begin
  v_site := fn_site(p_slug);
  if v_site.id is null then raise exception 'Site inconnu'; end if;

  if (now() at time zone 'Africa/Dakar')::time >= v_site.cloture then
    raise exception 'Les commandes sont closes depuis % : vois avec le traiteur.',
      to_char(v_site.cloture,'HH24:MI');
  end if;

  select * into v_moi from personne
   where site_id = v_site.id and appareil = p_appareil and fusionnee_vers is null;
  if not found then raise exception 'Appareil non inscrit'; end if;

  select * into v_c from commande
   where id = p_commande and site_id = v_site.id and jour = fn_aujourdhui()
   for update;
  if not found then raise exception 'Commande introuvable'; end if;
  if v_c.statut = 'annule' then raise exception 'Cette commande est déjà annulée'; end if;

  -- la sienne, ou une qu'on a passée pour quelqu'un d'autre
  if v_c.personne_id <> v_moi.id
     and coalesce(v_c.commandee_par, '00000000-0000-0000-0000-000000000000'::uuid) <> v_moi.id then
    raise exception 'Cette commande n''est pas la tienne';
  end if;

  select coalesce(sum(montant_affecte),0) into v_paye
    from paiement_commande where commande_id = v_c.id;
  if v_paye > 0 then
    raise exception 'Cette commande est déjà réglée (% F versés) : seul le traiteur peut l''annuler.', v_paye;
  end if;

  -- l'ordre compte : le statut d'abord, les lignes ensuite. fn_recalc respecte
  -- « annulé » ; l'inverse ferait passer la commande à « payé » à 0 franc.
  update commande set statut = 'annule' where id = v_c.id;
  delete from ligne where commande_id = v_c.id;

  return jsonb_build_object('commande', v_c.id, 'annulee', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. Ce qu'il reste à régler, et la déclaration de paiement
-- ---------------------------------------------------------------------
create or replace function fn_a_regler(p_slug text, p_appareil text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare v_site site; v_moi personne;
begin
  v_site := fn_site(p_slug);
  select * into v_moi from personne
   where site_id = v_site.id and appareil = p_appareil and fusionnee_vers is null;
  if not found then raise exception 'Appareil non inscrit'; end if;

  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', c.id, 'nom', pe.nom,
            'moi', c.personne_id = v_moi.id,
            'par_moi', c.commandee_par = v_moi.id,
            'montant', c.montant,
            'reste', (c.montant - coalesce((select sum(pc.montant_affecte)
                        from paiement_commande pc where pc.commande_id = c.id), 0))::int,
            'detail', (select string_agg(a.nom || case when l.qte>1 then ' × '||l.qte else '' end, ' + ')
                         from ligne l join article a on a.id=l.article_id
                        where l.commande_id = c.id)) order by c.personne_id = v_moi.id desc, pe.nom), '[]'::jsonb)
          from commande c join personne pe on pe.id = c.personne_id
         where c.site_id = v_site.id and c.jour = fn_aujourdhui() and c.statut = 'du');
end $$;

create or replace function fn_declarer_paiement(
  p_slug text, p_appareil text, p_moyen text,
  p_commandes uuid[], p_preuve text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_site site; v_moi personne; v_moyen uuid; v_pay uuid;
        v_total int; v_c record;
begin
  v_site := fn_site(p_slug);
  select * into v_moi from personne
   where site_id = v_site.id and appareil = p_appareil and fusionnee_vers is null;
  if not found then raise exception 'Appareil non inscrit'; end if;

  select id into v_moyen from moyen_paiement
   where traiteur_id = v_site.traiteur_id and code = p_moyen and actif;
  if v_moyen is null then raise exception 'Moyen de paiement inconnu'; end if;
  if coalesce(array_length(p_commandes,1),0) = 0 then raise exception 'Aucune commande sélectionnée'; end if;

  -- on ne règle que des commandes dues, du bon site, du jour.
  -- verrou d'abord (FOR UPDATE est interdit avec un agrégat), total ensuite.
  perform 1 from commande
   where id = any(p_commandes) and site_id = v_site.id
     and jour = fn_aujourdhui() and statut = 'du'
   for update;

  -- on règle le RESTE dû, pas le total : une commande complétée après un
  -- premier paiement ne doit être facturée que de la différence
  select coalesce(sum(c.montant - coalesce(pc.affecte,0)),0)::int into v_total
    from commande c
    left join lateral (select sum(montant_affecte) as affecte from paiement_commande
                        where commande_id = c.id) pc on true
   where c.id = any(p_commandes) and c.site_id = v_site.id
     and c.jour = fn_aujourdhui() and c.statut = 'du';
  if v_total <= 0 then raise exception 'Ces commandes sont déjà réglées'; end if;

  insert into paiement (site_id, personne_id, moyen_id, montant, preuve_url, jour)
  values (v_site.id, v_moi.id, v_moyen, v_total, p_preuve, fn_aujourdhui())
  returning id into v_pay;

  for v_c in select c.id, c.personne_id,
                    (c.montant - coalesce(pc.affecte,0))::int as reste
               from commande c
               left join lateral (select sum(montant_affecte) as affecte
                                    from paiement_commande where commande_id = c.id) pc on true
              where c.id = any(p_commandes) and c.site_id = v_site.id
                and c.jour = fn_aujourdhui() and c.statut = 'du'
                and (c.montant - coalesce(pc.affecte,0)) > 0 loop
    -- un second versement sur la même commande s'ajoute au premier
    insert into paiement_commande (paiement_id, commande_id, montant_affecte)
    values (v_pay, v_c.id, v_c.reste)
    on conflict (paiement_id, commande_id) do update
      set montant_affecte = paiement_commande.montant_affecte + excluded.montant_affecte;
    if v_c.personne_id <> v_moi.id then
      update commande set commandee_par = coalesce(commandee_par, v_moi.id) where id = v_c.id;
    end if;
  end loop;

  return jsonb_build_object('paiement', v_pay, 'montant', v_total);
end $$;

-- ---------------------------------------------------------------------
-- 5. Droits : aucune table, seulement ces fonctions
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select rolname from pg_roles where rolname in ('anon','authenticated') loop
    execute format('grant execute on function fn_menu(text,text)                  to %I', r.rolname);
    execute format('grant execute on function fn_suggestions(text,text)           to %I', r.rolname);
    execute format('grant execute on function fn_inscrire(text,text,text,text)    to %I', r.rolname);
    execute format('grant execute on function fn_commander(text,text,jsonb)       to %I', r.rolname);
    execute format('grant execute on function fn_annuler(text,text,uuid)         to %I', r.rolname);
    execute format('grant execute on function fn_a_regler(text,text)              to %I', r.rolname);
    execute format('grant execute on function fn_declarer_paiement(text,text,text,uuid[],text) to %I', r.rolname);
    -- les fonctions internes ne sont pas une surface publique
    execute format('revoke execute on function fn_norm(text)        from public');
    execute format('revoke execute on function fn_site(text)        from public');
    execute format('revoke execute on function fn_aujourdhui()      from public');
  end loop;
end $$;

-- L'écran du traiteur ne passe PAS par ici : il lit les vues v_cuisine,
-- v_canal, v_manquant avec un compte authentifié. C'est le seul endroit
-- qui voit l'argent et les numéros de téléphone.
