#!/bin/bash

rundir=`dirname $0`

cd $rundir
./clean_bad_predictions.sh
./download_prediction.sh
./run_QA_proq3.pl
./archive_QA.sh
./backupto_triolith.sh
