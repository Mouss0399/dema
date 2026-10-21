# Lekk bi — charte

Ce document écrit les règles que le code applique, pour que les images, les
documents et les futurs écrans n'aient pas à les redeviner. Quand une règle est
mesurable, le nombre est donné : une charte qui ne repose que sur le goût ne
survit pas au premier prestataire.

Règle générale : **une seule apparence pour tous les traiteurs.** Le cadre est
celui de Lekk bi ; le contenu — nom, logo, menu, prix, horaires, numéros — est
celui du traiteur. Voir « Ce qui appartient au traiteur », en bas.

## L'idée

**Lekk bi est un registre bien tenu.**

Pas une application de restauration, pas un service de livraison. Ce que le
produit fait et qu'un sondage WhatsApp ne fera jamais : il se souvient. Qui a
commandé, qui a payé, qui doit encore — d'un jour sur l'autre.

Tout le reste découle de là :

- **Le filet est l'élément graphique principal.** Un registre, c'est des lignes.
- **Rien ne flotte** : pas d'ombres, parce qu'une page n'en a pas.
- **Les chiffres s'alignent** en chasse fixe. Ce n'est pas un détail
  typographique, c'est la marque qui s'exprime.
- **L'accent est la marque de celui qui tient le livre** — l'encre
  d'annotation, le « vu ». Il n'apparaît que là où quelqu'un a noté quelque
  chose, ou doit le faire. Jamais en décoration.

## Le signe

**Un disque qui se remplit par le bas, surface ondulée.** Une jauge.

Il ne vient pas d'un objet rapporté — ni assiette, ni cloche, ni couvert. Il
vient de ce que le produit mesure : le reste dû. C'est pour ça qu'il porte une
information au lieu d'en promettre une.

**Le niveau est une part de l'aire, pas de la hauteur.** Un disque ne se remplit
pas comme un verre droit : au quart de sa hauteur il n'est coloré qu'au
huitième. Si on remplissait à la hauteur, « 2 000 F sur 9 000 » afficherait un
disque qui en paraîtrait un sixième, et le chiffre à côté démentirait l'image.
Le tracé inverse donc l'aire du segment circulaire. Écart mesuré entre la part
demandée et la part réellement colorée : moins de deux points.

| Niveau | Sens | Dans l'écran |
|---|---|---|
| vide (anneau seul, en texte tertiaire) | rien n'est payé | en attente |
| partiel | un acompte est arrivé | acompte |
| plein | plus rien à régler | réglé |

**L'onde a une longueur d'onde longue** — 1,90 fois le diamètre, amplitude
0,036. Plus court, la surface se lit comme une colline et non comme un liquide.
En dessous de 28 px l'onde s'aplatit : il n'y a plus la place.

**Le contour s'épaissit quand le signe rétrécit** : 0,085 du diamètre au-dessus
de 48 px, 0,105 entre 28 et 48, 0,135 en dessous.

**Sa couleur dépend aussi de la taille.** L'anneau est le contenant, le liquide
est le contenu : il faut pouvoir les distinguer. Au-dessus de 48 px, les peindre
tous deux en accent les fond en une seule masse, et il ne reste à lire qu'une
échancrure claire — l'anneau repasse donc au texte tertiaire. En dessous de
48 px c'est l'inverse : il n'y a plus assez de liquide pour porter la couleur à
lui seul, et l'anneau prend l'accent dès que le disque est entamé. Dans les deux
cas c'est le liquide qui porte l'information ; l'anneau ne fait que la cadrer.

**Taille minimale : 16 px.** En dessous, les trois états ne se distinguent plus.

Tout est tracé en suréchantillonnage ×8 puis réduit en Lanczos. Un cercle tracé
à la taille finale montre ses pixels, et ça se voit.

### Où il sert en grand

En tête de l'onglet « Encaissé », un disque de 92 px donne la part de la journée
déjà rentrée, avant même qu'on lise les montants. C'est le seul endroit du
produit où le signe est **regardé** plutôt que parcouru — et donc le seul où il
est assez grand pour que l'onde existe. Partout ailleurs il fait 16 à 20 px,
où la charte veut une surface droite.

### Le mouvement

**Le signe est la seule chose qui bouge, et seulement là où on le regarde.**
Sur la vitrine, le disque monte une fois à l'arrivée — 1,15 s, et il s'arrête à
la part réelle. C'est le geste que le produit décrit, montré au lieu d'être
raconté. Rien d'autre sur la page n'a le droit de bouger : ni survol animé, ni
apparition au défilement, ni compteur qui s'incrémente.

Dans le produit, le signe ne bouge jamais : il porte un état, et un état qui
s'anime se lit comme un chargement.

**Une seule autre chose a le droit de bouger : ce qui répond au doigt.** Un lien,
un bouton, un onglet changent de couleur en **150 ms**. En dessous on ne le
perçoit pas ; au-dessus ça traîne et l'interface paraît molle. Ça ne concerne que
`color`, `background-color` et `border-color` — jamais la position, jamais la
taille, jamais l'opacité d'un bloc entier.

Ce qui reste interdit, et nommément : les apparitions au défilement. C'est
l'effet le moins cher du web, il contredit la grammaire d'imprimé — une page
n'apparaît pas, elle est là — et sur une connexion lente il donne une page qui
saccade au lieu d'une page qui se lit.

`prefers-reduced-motion: reduce` supprime l'animation — le disque est alors à
son niveau dès la première image. Désactiver veut dire immobile, pas invisible.

### Où il sert seul

Favicon, icône d'application, avatar WhatsApp, puce de liste dans l'écran du
traiteur. **Jamais à côté du logotype** : le mot contient déjà le signe, le
répéter fabrique un logo redondant.

Dans le mot, le point est toujours **plein** — un point de *i* doit d'abord se
lire comme un point. Isolé, le signe montre un état — un disque plein tout seul
n'est qu'un rond.

Dans le produit il est tracé en **SVG**, pas en image : il prend la couleur du
thème, reste net à toute taille et ne coûte aucune requête. Deux tracés selon
la taille, exactement comme la règle de l'onde ci-dessus :

- **sous 28 px**, la surface est droite — un seul arc de cercle, aucun
  identifiant à inventer, donc autant de jauges qu'on veut sur un écran ;
- **à partir de 28 px**, la surface est échantillonnée sur l'onde et bornée par
  le cercle à chaque abscisse, ce qui garantit que le liquide ne déborde jamais
  de l'anneau.

Le disque du liquide mord d'un cheveu sur l'anneau : bord à bord,
l'anti-crénelage laisse un liseré clair entre les deux.

Fichiers : `marque/etat-*.png`, `marque/icone-*.png`, `marque/avatar-*.png`,
`favicon.ico`.

## Le logotype

**« lekkbi » en bas de casse, Gabarito 700, en deux couleurs** : « lekk » à
l'encre, « bi » à l'accent. Le point du *i* est remplacé par le signe, grossi de
16 % par rapport au point d'origine — assez pour qu'on voie que c'est délibéré,
pas assez pour qu'il se détache du fût.

Deux couleurs parce que c'est un article défini wolof : *lekk* + *bi*. La
structure du nom devient visible pour quelqu'un qui ne parle pas la langue.

**Gabarito plutôt qu'une géométrique courante.** Le point de son *i* fait 6,4 %
de la largeur du mot, contre 4,7 % pour Rubik : un tiers de surface en plus pour
le signe. À largeur d'en-tête courante, c'est la différence entre une jauge
lisible et une tache.

**Attaché, jamais détaché.** Le domaine s'écrit `lekkbi.com`, le bicolore fait
déjà la séparation. « Lekk bi » en deux mots ne s'écrit qu'en toutes lettres
dans une phrase.

Le logotype est un **SVG en ligne** (`marque/lekkbi.svg`) : aucune requête
réseau, net à toute taille, et il prend les couleurs du thème par les variables
`--logo-ink` et `--logo-accent`. Les versions image sont pour l'extérieur
(`marque/logotype-papier.png`, `-encre.png`, `-mono.png`).

**Taille minimale : 72 px de large.**
**Zone de réserve :** le diamètre du point du *i* tout autour — elle grandit
donc avec le logo.

Ce qu'on ne fait pas : pas d'inclinaison, pas d'étirement, pas d'ombre, pas de
contour, pas de framboise sur fond clair, pas d'autre couleur que les deux.

## Pas de signature

**Le bloc logo n'a pas de baseline.** Pas de ligne en capitales grises entre
deux filets sous le mot — c'est l'élément le plus interchangeable des planches
de marque, et notre mot porte déjà du sens : le bicolore dit la structure, le
point dit l'état. Une légende dirait au lecteur que ce qu'il voit ne suffit pas.

Là où quelqu'un découvre le produit sans contexte — image de partage, vitrine —
c'est une **ligne d'explication**, pas une baseline :

> **Commande ton déjeuner. Le reste est noté.**

Elle n'a pas à tenir sous le mot, donc elle peut dire le produit en entier.

Elle s'adresse à **l'employé**, pas au traiteur : l'image de partage est vue
dans le groupe WhatsApp, par quelqu'un qui veut commander, pas par quelqu'un
qui surveille. Une ligne écrite du point de vue du traiteur — « qui mange quoi,
qui a payé » — se lit là comme de la surveillance. Et « le reste est noté »
reprend le mot de l'application quand un règlement est enregistré, donc elle
désamorce le malentendu le plus coûteux — « l'application prend l'argent » —
sans avoir à s'en expliquer.

Une phrase, pas trois : le titre et la description du lien s'affichent déjà
sous l'image. Ce qui est gravé dans l'image est aussi la seule chose qu'on ne
peut pas changer sans refabriquer un fichier et attendre le cache.

Si une enseigne ou un pied de facture réclame un jour une baseline, c'est
**« LE MIDI, RÉGLÉ »** — *réglé* est déjà le mot de l'application quand la jauge
est pleine.

## Couleurs

| Rôle | Clair | Sombre |
|---|---|---|
| Fond (papier) | `#FAF7F2` | `#15120F` |
| Surface (carte) | `#FFFFFF` | `#1E1A16` |
| Surface secondaire | `#F2EDE5` | `#272119` |
| Filet | `#E3DACE` | `#352D24` |
| Filet appuyé | `#C9BCA9` | `#4B4035` |
| Texte | `#241C18` | `#F3EDE5` |
| Texte secondaire | `#5A4C43` | `#C3B6A8` |
| Texte tertiaire | `#8B7B6E` | `#95877A` |
| **Accent** | `#A3123C` *crimson* | `#F2456F` *framboise* |
| Accent léger | `#F7E3E9` | `#3A1722` |
| Sur accent | `#FFFFFF` | `#1B0A11` |
| Succès | `#1F6B4A` | `#6FCFA2` |
| Alerte | `#9A5B06` | `#E5A851` |

Les neutres sont **chauds** — c'est ce qui distingue Lekk bi au premier regard
d'un produit logiciel ordinaire, qui part toujours de gris froids. Ne pas les
remplacer par des gris neutres.

### Un accent par fond, jamais deux

Le crimson et le framboise ne sont pas deux couleurs : c'est la même teinte sous
deux éclairages. Le partage se fait par le **fond**, pas par la fonction.

| Couple | Contraste | Verdict |
|---|---|---|
| crimson sur papier | 7,25 | AAA |
| crimson sur encre | **2,16** | inutilisable |
| framboise sur encre | 4,67 | AA |
| framboise sur papier | **3,36** | insuffisant en texte |
| blanc sur crimson | 7,75 | AAA |
| blanc sur framboise | **3,59** | insuffisant — d'où l'encre sur framboise |

D'où les deux interdits : **pas de crimson sur fond sombre, pas de framboise sur
fond clair.** Toute nouvelle couleur doit avoir ses deux valeurs et ses deux
mesures.

### Un seul aplat d'accent par écran

C'est le bouton principal. Partout ailleurs l'accent est en filet ou en texte,
ou n'est pas là :

- l'option sélectionnée se marque à l'**encre**, pas à l'accent — « choisi » est
  une information neutre ;
- la pastille de comptage est en texte secondaire sur surface secondaire ;
- le message d'erreur garde un filet d'accent, mais son fond est une surface et
  son texte est à l'encre.

Sans cette règle, un plat coché, un compteur et le bouton « payer » portent le
même rouge, et le bouton n'a plus rien contre quoi ressortir.

**Sur une page qui défile, « par écran » se compte par hauteur d'écran.** La
règle existe pour que le bouton principal ait quelque chose contre quoi
ressortir ; deux aplats qu'on ne peut pas voir en même temps ne se concurrencent
pas. La vitrine porte donc deux boutons pleins — un sous le titre, un à la fin —
et rien entre les deux.

**Le signe fait exception.** La jauge porte l'accent en aplat, à toutes les
tailles et autant de fois qu'il le faut : sa couleur est l'information, pas une
décoration. C'est justement parce qu'elle prend l'état en charge que le reste
de l'écran peut rester neutre — la sélection passe à l'encre, les pastilles de
noms perdent leur vert.

**Le vert ne sert qu'à l'argent réellement reçu** — les totaux encaissés. Il ne
marque jamais un état de commande : c'est le travail du signe.

Un bouton désactivé sort entièrement de l'accent : fond en surface secondaire,
texte en tertiaire. Un accent pâli se lit comme un bouton actif.

## Typographie

**Karla**, version variable, graisses 200 à 800, pour toute l'interface. Licence
SIL OFL — hébergée dans `polices/karla.woff2`, jamais chargée depuis un service
tiers. **Gabarito 700 ne sert qu'au logotype**, et le logotype est un tracé : la
police n'est pas embarquée dans les pages.

Échelle à six paliers pour l'interface, sans valeur intermédiaire :

| px | Emploi |
|---|---|
| 12 | légendes, étiquettes, surtitres — **plancher absolu** |
| 14 | texte secondaire |
| 16 | texte courant, **et tous les champs de saisie** |
| 18 | noms de plats, titres de section |
| 22 | titres d'écran |
| 28 | totaux |
| 32 → 56 | **titre de vitrine — fluide, cette page-là seulement** |

Le septième n'appartient pas à l'interface, et il n'est pas un palier : c'est une
**plage**. Sur la vitrine, quelqu'un découvre le produit sans contexte, sur son
téléphone, en dix secondes — et quand le plus gros corps disponible vaut un
total, aucun titre ne peut dominer : la page se lit comme un paragraphe de
conditions générales.

Deux valeurs y coulent avec la largeur, bornées des deux côtés :

| Élément | Plage | Formule |
|---|---|---|
| Titre de vitrine | 32 → 56 px | `clamp(32px, 1.3rem + 3.6vw, 56px)` |
| Ligne d'accroche | 16 → 20 px | `clamp(16px, .95rem + .35vw, 20px)` |

32 px pour que la phrase tienne sur un petit téléphone, 56 px pour qu'elle tienne
la page sur un écran large. **Rien d'autre ne coule** : le reste de la vitrine,
et la totalité du produit, restent sur les six paliers. Une échelle fluide
partout, c'est une échelle qu'on ne peut plus vérifier.

Les champs de saisie ne descendent jamais sous 16 px : en dessous, Safari iOS
zoome la page à chaque fois qu'on les touche. La règle qui l'impose doit rester
**en dernier** dans la feuille de style — elle a été battue une fois par une
règle plus spécifique, et le défaut ne se voit pas sans mesurer.

Surtitres : capitales, interlettrage `.1em`, 12 px, en texte tertiaire.
Chiffres : toujours `font-variant-numeric: tabular-nums`.
Titres : graisse 800, interlettrage `-.015em`.

## Formes

Rayons de 10 à 12 px sur les cartes et les boutons ; 20 px sur les pastilles ;
0,235 du côté sur l'icône d'application.
**Aucune ombre portée. Aucun dégradé. Aucune icône décorative.** La séparation se
fait au filet — c'est une grammaire d'imprimé, pas d'interface logicielle.

Un `box-shadow: inset` n'est pas une ombre : c'est un filet tracé à l'intérieur,
le seul moyen d'épaissir une bordure sans déplacer ce qu'elle entoure. Il est
permis. Une ombre portée — un `box-shadow` sans `inset` — ne l'est pas.

## Ton

Tutoiement. Phrases courtes. On nomme les choses comme la personne les nomme :
« ton plat », « il reste 500 F à régler », « reviens demain matin ».

On n'écrit jamais une consigne sans sa raison — « ajoute la capture : elle aide
le traiteur à retrouver ton paiement » plutôt que « ajoute la capture ».

Pas d'emoji. Pas de point d'exclamation. Pas de vocabulaire logiciel :
on ne « valide pas une transaction », on « envoie l'argent ».

## Ce qui appartient au traiteur

Son nom et son logo, son menu, ses prix, ses rubriques, ses heures de clôture,
ses numéros d'encaissement.

Sur sa page de commande, c'est **son** nom en en-tête ; Lekk bi signe en bas, en
petit. Sur son tableau de bord, c'est l'inverse : Lekk bi en tête, son nom en
sous-titre — c'est l'écran qu'elle paie, elle doit voir pour quoi.

Les couleurs et la typographie ne se personnalisent pas. Un logo de traiteur
s'affiche sur fond blanc, dans la carte, jamais sur l'accent.
