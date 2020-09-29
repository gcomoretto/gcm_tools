#!/bin/bash
# update all repos in a shadow organization


usage() { 
  echo "Usage: $0 -o <upstream org> -d <shadow org> [-b <branch>]"
  echo "  (shadow org name shall include the string 'shadow' in it)"
  exit 1
}


parse_repos_yaml() {
  filepath="${WORKDIR}/repos/etc/repos.yaml"
  local prefix=""
  local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
  repos_yaml=$(sed -ne "s|^\($s\):|\1|" \
       -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
       -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $filepath |
  awk -F$fs '{
     indent = length($1)/2;
     vname[indent] = $2;
     for (i in vname) {if (i > indent) {delete vname[i]}}
     if (length($3) > 0) {
        vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
        printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
     }
  }' | grep "_ref")
  echo "Found following repos with diffent master reference:"
  echo "${repos_yaml}"
  echo

}


run() {
  if [[ $DRYRUN == true ]]; then
    echo "$@"
  elif [[ $DEBUG == true ]]; then
    (set -x; "$@")
  else
    echo "$@" >> "${logfile}" 2>&1
    "$@" >> "${logfile}" 2>&1
  fi
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
  ref="master"
  # if upstream do not exists, return
  if ! $CURL --output /dev/null --silent --head --fail "$upsrepo"; then
    echo  "  >>  No respository $repo found in $UPS_ORG organization"
    return
  fi 
  i=$((i+1))
  logfile="updste_${repo}_fork.log"
  echo "  -${i}-   Updating repository: ${repo}   ... "
  repos_array=($repos_yaml)
  for entry in "${repos_array[@]}"; do
     entry_name=$(echo $entry | awk -F'_' '{ print $1 }')
     entry_ref=$(echo $entry | awk -F '"' '{ print $2}')
     if [[ "$entry_name" == "$repo" ]]; then
       ref=$entry_ref
       echo "Main ref is $ref" 
     fi
  done
  if [ -d "$repo" ]; then
    cd $repo
    # check working dir is clean
    if [ ! -z "$(git status --porcelain -uno)" ]; then
      echo "Wroking directory not clean"
      cd ..
      return
    fi
  else
    git clone "${gitrepo}" 
    cd "${repo}"
  fi
  > ${logfile}
  run git checkout "${ref}" 

  before=$(git rev-parse HEAD)
  echo "At: ${before}"
  # add upstream if not already there
  if ! UURL=$(git remote get-url upstream 2>/dev/null); then
    run git remote add upstream "${upsrepo}"
  else
    run echo "Upstream repo already configure as ${UURL} (${upsrepo})"
  fi
  run git pull --all
  # fetch all branches and tags
  run git checkout --detach
  run git fetch upstream '+refs/heads/*:refs/heads/*'
  run git checkout "${ref}"
  run git rebase upstream/master
  run git remote rm upstream
  run git push -f --all origin
  run git push --tags origin
  after=$(git rev-parse HEAD)
  if [[ "$before" != "$after" ]]; then
    echo "Now last commit is:"
    git log -n 1
  fi
  echo 

  if [[ -z $BRANCH ]]; then
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
cd $SHD_ORG
i=0
WORKDIR=$(pwd)

# first update "repos"
repo="repos"
update_repo

parse_repos_yaml

for repo in "${repos_list[@]}"; do
  if [[ ! ${skip} =~ ${repo} ]]; then
    update_repo
  fi
done

