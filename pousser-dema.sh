#!/usr/bin/env bash
# Publie le site sur GitHub Pages.  Usage : ./pousser-dema.sh <compte-github>
set -euo pipefail

COMPTE="${1:-}"
DEPOT="${2:-dema}"
if [ -z "$COMPTE" ]; then
  echo "Usage : ./pousser-dema.sh <compte-github> [nom-du-depot]"
  echo "Exemple : ./pousser-dema.sh Mouss0399"
  exit 1
fi

cd "$(dirname "$0")"

if [ ! -d .git ]; then
  git init -q
  git branch -M main
fi

git add -A
git commit -qm "Dema — commandes de déjeuner" || echo "(rien de nouveau à enregistrer)"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "https://github.com/$COMPTE/$DEPOT.git"
else
  git remote add origin "https://github.com/$COMPTE/$DEPOT.git"
fi

echo
echo "Envoi vers https://github.com/$COMPTE/$DEPOT …"
echo "Si le dépôt n'existe pas encore, crée-le d'abord sur github.com/new"
echo "  — nom : $DEPOT   — public   — sans README"
echo
git push -u origin main

DOMAINE=""
[ -f CNAME ] && DOMAINE="$(head -1 CNAME | tr -d '\r\n')"
MINUS="$(echo "$COMPTE" | tr 'A-Z' 'a-z')"
if [ -n "$DOMAINE" ]; then BASE="https://$DOMAINE"; else BASE="https://$MINUS.github.io/$DEPOT"; fi

cat <<FIN

C'est envoye.

FIN

if [ -n "$DOMAINE" ]; then
cat <<FIN
Domaine personnalise detecte dans CNAME : $DOMAINE

  A faire UNE SEULE FOIS, chez ton bureau d'enregistrement :
    4 enregistrements A sur le domaine nu  ->  185.199.108.153
                                               185.199.109.153
                                               185.199.110.153
                                               185.199.111.153
    1 enregistrement CNAME  www            ->  $MINUS.github.io.

  Puis, UNE SEULE FOIS, sur GitHub :
    github.com/$COMPTE/$DEPOT  ->  Settings  ->  Pages
    Custom domain : $DOMAINE   ->  Save
    Attends le certificat (quelques minutes), puis coche « Enforce HTTPS »

FIN
else
cat <<FIN
Dernière étape, une seule fois :
  github.com/$COMPTE/$DEPOT  ->  Settings  ->  Pages
  Source : « Deploy from a branch », branche « main », dossier « / (root) »

FIN
fi

cat <<FIN
Une à deux minutes plus tard :

  Commander (Yas)     $BASE/?s=yas
  Commander (Orange)  $BASE/?s=orange
  Ma journée          $BASE/suivi.html
  Mise en route       $BASE/reglages.html

FIN
