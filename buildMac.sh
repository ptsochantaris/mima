#!/bin/sh

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

PROJECT=Mima

# Clean
xcodebuild clean archive -project $PROJECT.xcodeproj -scheme "$PROJECT" -destination "generic/platform=macOS" -archivePath ~/Desktop/$PROJECT.xcarchive

if [ $? -eq 0 ]
then
echo
else
echo "!!! Archiving failed, stopping script"
exit 1
fi

# Upload to App Store
xcodebuild -exportArchive -archivePath ~/Desktop/$PROJECT.xcarchive -exportPath ~/Desktop/$PROJECT-Export -allowProvisioningUpdates -exportOptionsPlist exportMac.plist

if [ $? -eq 0 ]
then
echo
else
echo "!!! Exporting failed, stopping script"
exit 1
fi

# Add to Xcode organizer
open ~/Desktop/$PROJECT.xcarchive
