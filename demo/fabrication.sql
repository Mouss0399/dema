-- Une journée de démonstration. Tout passe par les fonctions publiques —
-- fn_inscrire, fn_commander, fn_declarer_paiement, fn_encaisser — pour que
-- les données soient exactement celles que le produit fabrique, et pas une
-- approximation écrite à la main qui divergerait au premier changement.
do $$
declare
  v_t uuid; v_ter uuid; v_dia uuid; v_rp uuid; v_rj uuid;
  v_thieb uuid; v_lasa uuid; v_jus uuid;
  i int; v_slug text; v_nom text; v_app text;
  v_art uuid; v_lignes jsonb; v_cid uuid;
  v_somme int := 0; v_cible int := 89000; v_reste int;
  prenoms text[] := array['Awa','Mamadou','Fatou','Ibrahima','Aïssatou','Ousmane',
    'Khady','Modou','Ndeye','Cheikh','Mariama','Alioune','Sokhna','Babacar',
    'Rama','Serigne','Bineta','Moustapha','Adama','Pape','Coumba','Lamine',
    'Astou','Souleymane','Dieynaba','Malick','Nafissatou','Abdou','Yacine',
    'Saliou','Mame','Daouda','Penda','Oumar','Seynabou','Idrissa','Fama',
    'Ass','Rokhaya'];
  noms text[] := array['Diop','Ndiaye','Fall','Sarr','Ba','Sow','Gueye','Faye',
    'Diallo','Cissé','Mbaye','Thiam','Sy','Kane','Seck','Niang','Camara','Dieng',
    'Diouf','Sagna'];
begin
  -- ── la maison : fictive, et qui le reste ────────────────────────────────
  update traiteur set nom = 'Le Bon Plat', tel = '770000000';
  select id into v_t from traiteur limit 1;

  delete from paiement_commande; delete from paiement;
  delete from ligne; delete from commande; delete from personne;
  delete from article; delete from rubrique; delete from site;

  insert into site (traiteur_id, nom, slug, cloture, actif)
       values (v_t, 'Teranga Digital', 'teranga', '10:30', true) returning id into v_ter;
  insert into site (traiteur_id, nom, slug, cloture, actif)
       values (v_t, 'Cabinet Diallo',  'diallo',  '11:00', true) returning id into v_dia;

  -- par_jour = false : le menu de la démo ne dépend pas du jour de la semaine,
  -- sinon la page changerait de contenu selon quand on la regarde.
  insert into rubrique (traiteur_id, nom, mode, obligatoire, quantite, par_jour, offert, ordre)
       values (v_t, 'Plats du jour', 'unique', true, true, false, false, 1) returning id into v_rp;
  insert into rubrique (traiteur_id, nom, mode, obligatoire, quantite, par_jour, offert, ordre)
       values (v_t, 'Jus', 'unique', false, true, false, false, 2) returning id into v_rj;

  insert into article (rubrique_id, nom, prix, jour, ordre, actif)
       values (v_rp, 'Thiéboudiène', 3000, null, 1, true) returning id into v_thieb;
  insert into article (rubrique_id, nom, prix, jour, ordre, actif)
       values (v_rp, 'Lasagnes', 3500, null, 2, true) returning id into v_lasa;
  insert into article (rubrique_id, nom, prix, jour, ordre, actif)
       values (v_rj, 'Jus bissap', 1000, null, 1, true) returning id into v_jus;

  -- ── la journée : 27 thiéboudiène, 12 lasagnes, 9 jus ────────────────────
  for i in 1..39 loop
    v_slug := case when i <= 24 then 'teranga' else 'diallo' end;
    v_nom  := prenoms[i] || ' ' || noms[1 + (i * 7) % 20];
    v_app  := 'demo-' || i;
    perform fn_inscrire(v_slug, v_nom, '77' || lpad((1000000 + i * 13147)::text, 7, '0'), v_app);

    v_art := case when i <= 27 then v_thieb else v_lasa end;
    v_lignes := jsonb_build_array(jsonb_build_object('article', v_art, 'qte', 1));
    if i % 4 = 0 and i <= 36 then      -- 9 jus : i = 4, 8, 12 … 36
      v_lignes := v_lignes || jsonb_build_array(jsonb_build_object('article', v_jus, 'qte', 1));
    end if;
    perform fn_commander(v_slug, v_app, jsonb_build_array(
              jsonb_build_object('pour', null, 'lignes', v_lignes)));
  end loop;

  -- ── les règlements : on vise 89 000 F rentrés sur 132 000 ───────────────
  -- La plupart par l'application, deux saisis par la traiteuse (espèces), et
  -- un acompte : l'écran doit montrer les trois états du signe, sinon la
  -- démonstration ne démontre rien.
  -- on panache les deux entreprises : solder la première et laisser toute la
  -- dette sur la seconde donnerait une journée que personne n'a jamais vue
  for v_cid, v_reste in
    select c.id, c.montant from commande c
     where c.statut <> 'annule' order by md5(c.id::text)
  loop
    exit when v_somme >= v_cible - 1200;
    if v_somme + v_reste > v_cible - 1200 then exit; end if;
    perform fn_encaisser(array[v_cid],
              case when v_somme % 3 = 0 then 'especes' else 'wave' end, null);
    v_somme := v_somme + v_reste;
  end loop;

  -- l'acompte qui tombe juste
  select c.id into v_cid from commande c
   where c.statut <> 'annule'
     and not exists (select 1 from paiement_commande pc where pc.commande_id = c.id)
   order by md5(c.id::text) limit 1;
  if v_cid is not null and v_cible - v_somme > 0 then
    perform fn_encaisser(array[v_cid], 'wave', v_cible - v_somme);
    v_somme := v_cible;
  end if;

  -- Les heures. Tout est tombé dans la même milliseconde parce que la boucle
  -- s'exécute d'un coup ; une colonne « arrivée » où 39 personnes commandent à
  -- 01 h 45 ne ressemble à aucune journée réelle. On les étale sur la matinée.
  with ordre as (
    select id, row_number() over (order by md5(id::text)) - 1 as n from commande)
  update commande c
     set cree_le = (c.jour + time '07:38') at time zone 'Africa/Dakar'
                 + make_interval(mins => (o.n * 4 + (o.n * 7) % 3)::int)
    from ordre o where o.id = c.id;

  -- un règlement arrive après la commande qu'il solde, jamais avant
  update paiement p
     set cree_le = greatest(
           (select max(c.cree_le) from commande c
              join paiement_commande pc on pc.commande_id = c.id
             where pc.paiement_id = p.id),
           (p.jour + time '08:05') at time zone 'Africa/Dakar')
         + make_interval(mins => (abs(hashtext(p.id::text)) % 95)::int),
         pointe_le = case when p.pointe then p.cree_le else null end;

  raise notice 'encaissé : % F', v_somme;
end $$;

select 'commandes', count(*)::text from commande where statut <> 'annule'
union all select 'dû total', sum(montant)::text from commande where statut <> 'annule'
union all select 'encaissé', (select coalesce(sum(montant),0) from paiement)::text
union all select 'personnes', count(*)::text from personne;
