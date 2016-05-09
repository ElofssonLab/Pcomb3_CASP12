#!/bin/bash

rundir=`dirname $0`
$rundir/download_prediction.sh
$rundir/run_QA_proq3.pl
$rundir/archive_QA.sh
