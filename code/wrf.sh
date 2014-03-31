#!/bin/sh
cd `dirname ${0}` || exit 1
. /util/opt/lmod/lmod/init/profile
export -f module
echo "Today is `date +%y/%m/%d`"

#Check if updates available
url="http://www.ftp.ncep.noaa.gov/data/nccf/com/nam/prod/nam.20`date +%y%m%d`"
if curl --output /dev/null --silent --head --fail "$url"; then
  echo "Updates found" && sleep 2
else
  echo "Updates NOT found" && sleep 2 && exit
fi 

#Delete old fils if exist
files=nam.t00z.awphys*
[[ "${#files[@]}" -gt 0 ]] && rm nam.t00z.awphys* && echo "Old Files Deleted"

#Fetch Files
for i in {0..72}; do	###CHANGE HERE###
URL1="http://www.ftp.ncep.noaa.gov/data/nccf/com/nam/prod/nam.20`date +%y%m%d`/nam.t00z.awphys`printf "%02d" $i`.grb2.tm00"
URL2="http://www.ftp.ncep.noaa.gov/data/nccf/com/nam/prod/nam.20`date +%y%m%d`/nam.t00z.awphys`printf "%02d" $i`.grb2.tm00.idx"
wget $URL1 &> /dev/null
wget $URL2 &> /dev/null
done

#Run WPS
#STEP 1: Build the links using ./link_grib.csh
cd /work/swanson/jingchao/wrf/WRF_forecast/WPS
grfiles=GRIBFILE*; [[ "${#grfiles[@]}" -gt 0 ]] && rm GRIBFILE* && echo "Delete Previous GRIBFILE* Links" && sleep 2
./link_grib.csh source/nam.t00z.awphys*

#STEP 2: Unpack the GRIB data using ./ungrib.exe
sed -i "4s/.*/ start_date = '20`date +%y-%m-%d`_00:00:00'/" namelist.wps	###CHANGE HERE###
sed -i "5s/.*/ end_date = '20`date --date='72 hour' +%y-%m-%d`_00:00:00'/" namelist.wps		###CHANGE HERE###
#sed -i "5s/.*/ end_date = '20`date +%y-%m`-`date --date='tomorrow' +%d`_12:00:00'/" namelist.wps
ugfiles=FILE*; [[ "${#ugfiles[@]}" -gt 0 ]] && rm FILE* && echo "Delete Previous FILE* Files" && sleep 2
id1=`sbatch ungrib.submit | cut -d ' ' -f 4`

#STEP 3: Generate input data for WRFV3
metfiles=met_em*; [[ "${#metfiles[@]}" -gt 0 ]] && rm met_em* && echo "Delete Previous met_em* Files" && sleep 2
id2=`sbatch -d afterok:$id1 metgrid.submit | cut -d ' ' -f 4`

#Create new folder for file transfer
#cd /work/swanson/jingchao/wrf/data
#ndir="`date +%y%m%d%H%M`"
#mkdir $ndir && cd $ndir && mkdir wrfout
##Copy the dir.submit file to the new dir and start file moving
#cp /work/swanson/jingchao/wrf/WRF_forecast/WPS/dir.submit ./
#id3=`sbatch -d afterok:$id2 dir.submit | cut -d ' ' -f 4`

#Run WRFV3
#Step 1: real.exe
cd /work/swanson/jingchao/wrf/WRF_forecast/WRFV3/test/em_real
lfiles=met_em*; [[ "${#lfiles[@]}" -gt 0 ]] && rm met_em* && echo "Delete Previous met_em* Links" && sleep 2
sed -i "3s/.*/ run_hours                           = 72,/" namelist.input						 ###CHANGE HERE###
sed -i "6s/.*/ start_year                          = 20`date +%y`,  2012, 2012,/" namelist.input			 ###CHANGE HERE###
sed -i "7s/.*/ start_month                         = `date +%m`,  07,  07,/" namelist.input				 ###CHANGE HERE###
sed -i "8s/.*/ start_day                           = `date +%d`,   25,  25,/" namelist.input				 ###CHANGE HERE###
sed -i "9s/.*/ start_hour                          = 00,   12,   12,/" namelist.input					 ###CHANGE HERE###
sed -i "12s/.*/ end_year                            = 20`date --date='72 hour' +%y`,   2012,  2012,/" namelist.input	 ###CHANGE HERE###
sed -i "13s/.*/ end_month                           = `date --date='72 hour' +%m`,  07,  07,/" namelist.input		 ###CHANGE HERE###
sed -i "14s/.*/ end_day                             = `date --date='72 hour' +%d`,    27,   27,/" namelist.input	 ###CHANGE HERE###
sed -i "15s/.*/ end_hour                            = 00,   00,   00,/" namelist.input					 ###CHANGE HERE###
sed -i "28s/.*/ auxinput1_inname                    = \"\.\/met_em.d<domain>.<date>\"/" namelist.input
sed -i "29s/.*/ history_outname                     = \"\.\/wrfout\/wrfout_d<domain>_<date>\"/" namelist.input
id3=`sbatch -d afterok:$id2 real.submit | cut -d ' ' -f 4`

#Step 2: wrf.exe
id4=`sbatch -d afterok:$id3 wrf.submit | cut -d ' ' -f 4`

#Step 3: File Transfer
cd /work/swanson/jingchao/wrf/data/wrf_only
find . -type d -mtime +3 | xargs rm -rf
ndir="`date +%y%m%d%H`"
mkdir $ndir && cd $ndir
cp /work/swanson/jingchao/wrf/WRF_forecast/WPS/dir.submit ./
id5=`sbatch -d afterok:$id4 dir.submit | cut -d ' ' -f 4`

echo "Submitted batch job $id1(ungrib) --> $id2(metgrid) --> $id3(real) --> $id4(wrf) --> $id5(File_transfer)"
