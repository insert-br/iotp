#!/bin/bash
PROJECT=$1
rsync -arPhAXE .sketch/ "${PROJECT}/"
mv "${PROJECT}/basic.p4" "${PROJECT}/${PROJECT}.p4"
sed -i -E -e "s@build/basic@build/${PROJECT}@gi" "${PROJECT}/"*-runtime.json

