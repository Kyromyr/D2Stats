# /bin/bash

version=$1
buildTime=$(date +"%Y-%m-%d")

echo "Version: ${version}"
echo "Time: ${buildTime}"

sed -b -i -e "s/{{version}}/${version}/g" D2Stats.au3
sed -b -i -e "s/{{buildTime}}/${buildTime}/g" D2Stats.au3