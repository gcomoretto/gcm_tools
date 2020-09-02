#!/bin/bash
#
#


usage() { echo "Usage: $0 [-o <organization>]" repo_url  1>&2; exit 1; }


while getopts "o:h" opt; do
  case "$opt" in
  o)
    ORG="$OPTARG"
    ;;
  h)
    usage
    ;;
  *)
    echo "wrong input option"
    usage
    ;;
  esac
done
shift $((OPTIND-1))

REPO=$1

# getting repo name
REPO_NAME=$(echo ${REPO%".git"} | awk -F '/' '{print $5}')
UPS_ORG=$(echo ${REPO%".git"} | awk -F '/' '{print $4}')

echo "Repository to fork: "
echo "   [$UPS_ORG/$REPO_NAME]   $REPO"
echo " into organization:"
echo "          $ORG"

# clone given repo
#   - should we get all branches? (probably not)
echo
echo "Cloning $REPO"
git clone $REPO

cd $REPO_NAME

# rename remote origin to upstream
echo
echo "Renaming origin to upstream"
git remote rename origin upstream

# add new remote origin to forked organization
echo
echo "Adding new origin in $ORG organization"
git remote add origin https://github.com/$ORG/$REPO_NAME

# fetch all branches and tags
git checkout --detach
git fetch upstream '+refs/heads/*:refs/heads/*'
git checkout master

# https://developer.github.com/v3/repos/#create-an-organization-repository
# create the repo in the forked organization:
d_json=$(echo '{"name":"'"$REPO_NAME"'","description":"Fork from '"$UPS_ORG/$REPO_NAME"'"}')
echo $d_json
curl -u "gcomoretto" https://api.github.com/orgs/gcmshadow/repos -d "$d_json"

git push --all origin
git push --tags origin
