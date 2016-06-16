#Pipeline for calculating Pcomb3 (ProQ3+Pcons) for CASP12

##Author

Nanjiang Shu


Example usage in crontab


0 */02 * * * /big/server/www_from_dany/pcons_nanjiang/CASP12/QA/bat_CASP12_QA_stage1.sh >> /data3/log/download_prediction_and_run_QA_CASP12_stage1.log 2>&1

0 */02 * * * /big/server/www_from_dany/pcons_nanjiang/CASP12/QA/bat_CASP12_QA_stage2.sh >> /data3/log/download_prediction_and_run_QA_CASP12_stage2.log 2>&1


0 */02 * * * /big/server/www_from_dany/pcons_nanjiang/CASP12/QA/bat_CASP12_QA_stageall.sh >> /data3/log/download_prediction_and_run_QA_CASP12_stageall.log 2>&1
