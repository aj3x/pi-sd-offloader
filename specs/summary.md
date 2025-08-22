# Application Summary
Detects an SD card being plugged in. This stores the images in a folder that is named based on today's date like so `YYYYMMDD`. Files must be imported within the import date folder as the filenames will loop around causing overwrites. The import should not be allowed to overwrite any information during this part of the process. All the images are transferred to this folder. Once the transfer is complete the script should run a checksum to ensure the files have been transferred uncorrupted and correct those that failed. Once the checksum is complete selete the files on the SD card. The machine running this is a raspberry pi running a linux distro like Raspberry Pi OS (Lite) or DietPi. The pi will be uploading these files to a synology. The system may need to check if the NAS is locally available or if it needs to go across the internet or through a VPN to then access. 

# Questions
Should the files be first transferred to the pi's local storage then moved across the internet? I have a decent number of SD cards so this may not be needed.

What protocol should be used to sync the data?

Is using a docker container for this plausible? Or should this be run on bare metal?

How should the user be notified of completion?

Are there other things I need to test for or check to validate the files?

