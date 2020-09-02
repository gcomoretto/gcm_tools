#!/bin/bash
# update a from his orogin


usage() { echo "Usage: $0 -o <upstream organization>"  1>&2; exit 1; }

UPS_ORG=

while getopts "o:h" opt; do
  case "$opt" in
  o)
    UPS_ORG="$OPTARG"
    ;;
  h)
    usage
    ;;
  *)
    echo "Wrong input option"
    usage
    ;;
  esac
done
shift $((OPTIND-1))

if [[ -z $UPS_ORG ]]; then
  echo "Missing input parameter"
  usage
fi

REPO=$(basename -s .git `git config --get remote.origin.url`)
ORG=$(git remote get-url origin | awk -F '/' '{print $4}')

if [ "$ORG" == "$UPS_ORG" ]; then
  echo "Can't update on the same org"
  exit -1
fi
echo "Updating repository $ORG/$REPO from upstream organization $UPS_ORG"

# check working dir is clean
if [ ! -z "$(git status --porcelain)" ]; then
  echo "Wroking directory not clean"
  exit
fi

# checkout master and pull
echo "Checkout master and pull from remote"
git checkout master
git pull

echo
# add upstream if not already there
if ! UURL=$(git remote get-url upstream); then
  echo "Adding upstream repo https://github.com/${UPS_ORG}/${REPO}"
  git remote add upstream "https://github.com/${UPS_ORG}/${REPO}"
else
  echo "Upstream repo already configure as ${UURL}"
fi

echo
echo "git pull upstream master"
git pull --all upstream
# fetch all branches and tags
git checkout --detach
git fetch upstream '+refs/heads/*:refs/heads/*'
git checkout master


echo
echo "git rebase upstream/master"
git rebase upstream/master

echo
echo "git push origin master"
git push --all origin
git push --tags origin
