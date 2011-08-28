#!/bin/bash

what=$1

if [ "$what" != "images" ] && [ "$what" != "all" ] && [ "$what" != "html" ]; then
    echo "USAGE: $0 [ images | html | all ]"
    echo "    html = css + html"
    exit 1
fi

files="
    dashboard.html
    profile.html
    workSpaces.html
    contentPage.html
    listPage.html
    settings.html
    settings2.html
    revisionHistory.html
    weblog.html
    listPage2.html
    listPage3.html
    listPage4.html
"

function get () {
    wget http://clients.araucariadesign.com/Socialtext/wiki/$1 --user social --password guest -O $2
}

if [ "$what" == "all" ] || [ "$what" == "html" ]; then
    for i in $files; do
        get $i html/$i
        sed -i 's/\t/    /g' html/$i
    done

    get css/styles.css css/styles.css
    get css/ieStyles.css css/ieStyles.css

    bin/fix-ids
fi

if [ "$what" == "all" ] || [ "$what" == "images" ]; then
    for image in `grep '/images/' css/styles.css css/ieStyles.css | sed 's/.*\/images\/\(\w*\.\w*\).*/\1/' | uniq`; do
        get images/$image images/$image
        continue;
    done
fi
