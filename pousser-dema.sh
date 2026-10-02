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

cat <<FIN

C'est envoyé.

Dernière étape, une seule fois :
  github.com/$COMPTE/$DEPOT  →  Settings  →  Pages
  Source : « Deploy from a branch », branche « main », dossier « / (root) »

Une à deux minutes plus tard :

  Commander (Yas)     https://$(echo "$COMPTE" | tr 'A-Z' 'a-z').github.io/$DEPOT/?s=yas
  Commander (Orange)  https://$(echo "$COMPTE" | tr 'A-Z' 'a-z').github.io/$DEPOT/?s=orange
  Ma journée          https://$(echo "$COMPTE" | tr 'A-Z' 'a-z').github.io/$DEPOT/suivi.html
  Mise en route       https://$(echo "$COMPTE" | tr 'A-Z' 'a-z').github.io/$DEPOT/reglages.html

FIN
