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

**Taille minimale : 16 px.** En dessous, les trois états ne se distinguent plus.

Tout est tracé en suréchantillonnage ×8 puis réduit en Lanczos. Un cercle tracé
à la taille finale montre ses pixels, et ça se voit.

### Où il sert seul

Favicon, icône d'application, avatar WhatsApp, puce de liste dans l'écran du
traiteur. **Jamais à côté du logotype** : le mot contient déjà le signe, le
répéter fabrique un logo redondant.

Dans le mot, le point est toujours **plein** — un point de *i* doit d'abord se
lire comme un point. Isolé, le signe montre un état — un disque plein tout seul
n'est qu'un rond.

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

Un bouton désactivé sort entièrement de l'accent : fond en surface secondaire,
texte en tertiaire. Un accent pâli se lit comme un bouton actif.

## Typographie

**Karla**, version variable, graisses 200 à 800, pour toute l'interface. Licence
SIL OFL — hébergée dans `polices/karla.woff2`, jamais chargée depuis un service
tiers. **Gabarito 700 ne sert qu'au logotype**, et le logotype est un tracé : la
police n'est pas embarquée dans les pages.

Échelle à six paliers, sans valeur intermédiaire :

| px | Emploi |
|---|---|
| 12 | légendes, étiquettes, surtitres — **plancher absolu** |
| 14 | texte secondaire |
| 16 | texte courant, **et tous les champs de saisie** |
| 18 | noms de plats, titres de section |
| 22 | titres d'écran |
| 28 | totaux |

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
