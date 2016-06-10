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

echo "Clean bad predictions..."
./clean_bad_predictions.sh

echo "Download CASP predictions..."
./download_prediction.sh

echo "Run ProQ3..."
./run_QA_proq3.pl

echo "Archive Pcomb predictions..."
./archive_QA.sh

echo "Backup the result to triolith..."
./backupto_triolith.sh

rm -f $lockfile
