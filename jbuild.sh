#!/bin/bash
#
# Jenkins build shortcut script
# 
# Allows you to quickly build the current branch to the specified dev server
#

# Credentials
USERNAME=""
PASSWORD=""

# URLS
JENKINS_ROOT=https://ci.your-company.com/
JENKINS_JOB_URL=${JENKINS_ROOT}/job/buildbranch-dev$DEV_SERVER-direct
JENKINS_STATUS_URL=${JENKINS_JOB_URL}/lastBuild/api/json
JENKINS_LOG_URL=${JENKINS_JOB_URL}/lastBuild/logText/progressiveText


# Defaults
BRANCH_NAME=
DEV_SERVER=
PROD_DATA="No"
LOG_STREAM=0
VERBOSE=0

# Backup IFS
BACKUP_IFS=$IFS


usage()
{
cat << EOF
usage: $0 options

Build a branch on ${JENKINS_ROOT}

Examples:

   $0 -b master -d 18 -p
     Build master to dev18 with production data

OPTIONS:
   -h      Show this message
   -d      Dev server (e.g 18) (REQUIRED)
   -b      Branch
   -s      Stream console output from Jenkins
   -p      Build with production data
   -v      Verbose
EOF
}


function jsonval {
  temp=`echo $JENKINS_RESPONSE | sed 's/\\\\\//\//g' | sed 's/[{}]//g' | awk -v k="text" '{n=split($0,a,","); for (i=1; i<=n; i++) print a[i]}' | sed 's/\"\:\"/\|/g' | sed 's/[\,]/ /g' | sed 's/\"//g' | grep -w 'result'`
  echo ${temp##*|}
}


while getopts “hb:d:spvr” OPTION
do
  case $OPTION in
    h)
      usage
      exit 1
      ;;
    b)
      BRANCH_NAME=$OPTARG
      ;;
    d)
      DEV_SERVER=$OPTARG
      ;;
    s)
      LOG_STREAM=1
      ;;
    p)
      PROD_DATA="Yes"
      ;;
    v)
      VERBOSE=1
      ;;
    ?)
      usage
      exit
      ;;
 esac
done


# Restore IFS
function finish {
  IFS=$OLD_IFS
  rm header.tmp.txt
}

trap finish EXIT


# Dev server must be provided
if [ -z $DEV_SERVER ]
then
  usage
  exit 1
fi

GIT_BRANCH_NAME="$(git symbolic-ref HEAD 2>/dev/null)" ||
GIT_BRANCH_NAME="(unnamed branch)"     # detached HEAD
GIT_BRANCH_NAME=${GIT_BRANCH_NAME##refs/heads/}

# Use the branch of the current path to build
if [ -z $BRANCH_NAME ]
then
  BRANCH_NAME=$GIT_BRANCH_NAME
  if [ "$BRANCH_NAME" = "(unnamed branch)" ]
  then
    echo "error: Not a git repository $BRANCH_NAME"
    echo
    usage
    exit 1
  fi
fi

# Verbose output
if [ $VERBOSE = 1 ]
then
  BASENAME=  
  if [ "$GIT_BRANCH_NAME" != "(unnamed branch)" ]
  then
    BASENAME = basename $(git remote show -n origin | grep Fetch | cut -d: -f2-)
  fi
  echo "Building branch... " $BASENAME $BRANCH_NAME
fi


# Build!
JSON_BUILD_PARAMS="{\"parameter\": [{\"name\": \"BRANCH\", \"value\": \"$BRANCH_NAME\"},{\"name\": \"PROD_DATA\", \"value\": \"$PROD_DATA\"}], \"\": \"\"}"

curl -X POST -u $USERNAME:$PASSWORD $JENKINS_JOB_URL/build --data-urlencode json="$JSON_BUILD_PARAMS"


# Stream all the logs!
if [ $LOG_STREAM = 1 ]
then
  
  # trap will restore this
  IFS=$'\n'

  TEXT_SIZE=0
  CONTINUE="true"

  while [ "$CONTINUE" == "true" ]
  do
    sleep 5

    curl -s -D header.tmp.txt -u $USERNAME:$PASSWORD $JENKINS_LOG_URL?start=$TEXT_SIZE
    
    MORE_DATA=
    PARSING_HEADER="true"

    HEADER=($(cat header.tmp.txt))

    for i in ${HEADER[@]}
    do
      TEMP_SIZE=`echo $i | awk '/^X-Text-Size/ {print $2}' | sed -e 's///g'`
      TEMP_DONE=`echo $i | awk '/^X-More-Data/ {print $2}' | sed -e 's///g'`
      [ "$TEMP_SIZE" != "" ] && TEXT_SIZE=$TEMP_SIZE
      [ "$TEMP_DONE" != "" ] && MORE_DATA=$TEMP_DONE
    done
    
    CONTINUE=$MORE_DATA
  done
fi

