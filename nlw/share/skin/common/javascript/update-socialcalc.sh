#!/bin/bash

TAG=$1
if [ -z "$TAG" ]; then
    echo "You must supply a tag of socialcalc to export!"
    exit
fi

rm -rf SocialCalc
svn export $ST_SVN/socialcalc/tags/$TAG SocialCalc
