#!/bin/bash

if [ $# -lt 2 ]; then
  echo "Please run this again and pass in the application name and revision file!"
  exit 1
fi

APP=$(echo $1 | tr '[:upper:]' '[:lower:]')
REVISION=$(cat "$2")

case $APP in
  "intranet") APP_ID="***REMOVED***" ;;
  "website") APP_ID="***REMOVED***" ;;
  "zaibatsu") APP_ID="***REMOVED***" ;;
esac

new_relic_mark_deploy () {
  curl -H "x-api-key:***REMOVED***" -d "deployment[application_id]=$APP_ID" -d                 "deployment[description]=$APP" -d "deployment[revision]=$REVISION" -d "deployment[changelog]=..." -d                             "deployment[user]=Webistrano Deployment" https://api.newrelic.com/deployments.xml
}

echo "INFO: Sending deployment marker to new relic..."
echo $APP - $APP_ID -  $REVISION


exit 0