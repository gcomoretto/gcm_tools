#!/bin/bash
# update all repos in a shadow organization


usage() { 
  echo "Usage: $0 -o <upstream org> -d <shadow org> [-b <branch>]"
  echo "  (shadow org name shall include the string 'shadow' in it)"
  exit 1
}

UPS_ORG=
SHD_ORG=
BRANCH=

while getopts "o:d:b:h" opt; do
  case "$opt" in
  o)
    UPS_ORG="$OPTARG"
    ;;
  d)
    SHD_ORG="$OPTARG"
    ;;
  b)
    BRANCH="$OPTARG"
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
  echo "Missing input parameter: Upstream Organization"
  usage
fi
if [[ -z $SHD_ORG ]]; then
  echo "Missing input parameter: Shadow Organization (to update)"
  usage
fi
if [[ ! $SHD_ORG =~ "shadow" ]]; then
  echo "Invalid shadow organization name: ${SHD_ORG} "
  echo "Shadow organization shall have the string 'shadow' in it (security)"
  usage
fi
if [[ $SHD_ORG == $UPS_ORG ]]; then
  echo "Upstream org and shadow org cannot be the same."
  usage
fi

list=$(curl "https://api.github.com/users/gcmshadow/repos?page+1&per_page=100" | grep -e 'git_url*' | grep gcmshadow| awk -F '"' '{ print $4 }' | awk -F '/' '{ print $5 }' | awk -F '.' '{ print $1 }')

echo $list

exit

REPO=$(basename -s .git `git config --get remote.origin.url`)
ORG=$(git remote get-url origin | awk -F '/' '{print $4}')

if [ ! -d ".git" ]; then
  echo "Not a git repository"
  exit 1
fi

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
echo "git pull --all"
git pull --all
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

git remote rm upstream
