#!/bin/bash

rundir=`dirname $0`
rundir=`readlink -f $rundir`


cd $rundir


lockfile=.casp12_qa.lock

if [ -f $lockfile ]; then
    echo "lockfile $lockfile exist, exit"
    exit 1
fi

date > $lockfile

trap 'rm -f "$lockfile"' INT TERM EXIT

./clean_bad_predictions.sh
./download_prediction.sh
./run_QA_proq3.pl
./archive_QA.sh
./backupto_triolith.sh

rm -f $lockfile
