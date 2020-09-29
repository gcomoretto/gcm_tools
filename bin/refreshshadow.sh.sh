#!/bin/bash
# update all repos in a shadow organization


usage() { 
  echo "Usage: $0 -o <upstream org> -d <shadow org> [-b <branch>]"
  echo "  (shadow org name shall include the string 'shadow' in it)"
  exit 1
}


config_curl() {
  # Prefer system curl; user-installed ones sometimes behave oddly
  if [[ -x /usr/bin/curl ]]; then
    CURL=${CURL:-/usr/bin/curl}
  else
    CURL=${CURL:-curl}
  fi

  # disable curl progress meter unless running under a tty -- this is intended to
  # reduce the amount of console output when running under CI
  CURL_OPTS=('-#')
  if [[ ! -t 1 ]]; then
    CURL_OPTS=('-sS')
  fi

  # curl will exit 0 on 404 without the fail flag
  CURL_OPTS+=('--fail')
}


update_repo() {
  local gitrepo="https://github.com/${SHD_ORG}/${repo}"
  local upsrepo="https://github.com/${UPS_ORG}/${repo}"
  # if upstream do not exists, return
  if ! $CURL --output /dev/null --silent --head --fail "$upsrepo"; then
    echo  "  >>  No respository $repo found in $UPS_ORG organization"
    return
  fi 
  i=$((i+1))
  echo "  -${i}-   Updating repository: ${repo}   ... "
  (
  if [ -d "$repo" ]; then
    cd $repo
    # check working dir is clean
    if [ ! -z "$(git status --porcelain)" ]; then
      echo "Wroking directory not clean"
      return
    fi
    # checkout master and pull
    echo "Checkout master and pull from remote"
    git checkout master
    # not sure this is usefull, not expecting any changes in the forked repos
    git pull
  else
    echo "Clone repository"
    git clone "${gitrepo}"
    cd "${repo}"
  fi

  echo
  # add upstream if not already there
  if ! UURL=$(git remote get-url upstream 2>/dev/null); then
    echo "Adding upstream repo ${upsrepo}"
    git remote add upstream "${upsrepo}"
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

  git remote rm upstream

  echo
  echo "git push origin master"
  git push -f --all origin
  git push --tags origin
  ) 2>&1 > "$update_{repo}_fork.log."
  git log -n 1
  echo 

  if [[ -z $BRANCH]]; then
    echo $BRANCH
  fi

  cd ..
}

#################################################
# main

config_curl

UPS_ORG=
SHD_ORG=
BRANCH=

skip="lsstsw repos"

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

# from https://gist.github.com/erdincay/4f1d2e092c50e78ae1ffa39d13fa404e
list=$($CURL -s "https://api.github.com/users/gcmshadow/repos?page+1&per_page=100" | grep -e 'git_url*' | grep gcmshadow| awk -F '"' '{ print $4 }' | awk -F '/' '{ print $5 }' | awk -F '.' '{ print $1 }')
repos_list=($list)
echo "Found $(echo $list |wc -w) repositories in ${SHD_ORG} organization"

mkdir -p $SHD_ORG

# first update "repos"
repo="repos"
update_repo

cd $SHD_ORG
i=0
for repo in "${repos_list[@]}"; do
  if [[ ! ${skip} =~ ${repo} ]]; then
    update_repo
  fi
done

exit

