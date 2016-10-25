#!/bin/bash
## xs_patcher
## detects xenserver version and applies the appropriate patches
PROGNAME=$(basename $0)

## URL to patches: http://updates.xensource.com/XenServer/updates.xml

source /etc/xensource-inventory
TMP_DIR=tmp
CACHE_DIR=cache

# lock dirs/files
LOCKDIR="/var/tmp/$PROGNAME-lock"
#this will only work on the first effort to re-run as the second exiting script will triger the trap and remove the original lockdir
trap 'rmdir $LOCKDIR' 0 1 2 3 15 EXIT # trap SIGHUP SIGINT SIGQUIT SIGTERM # under normal operation the lockdir will be removed at the end of the scripts run

if [[ -d $LOCKDIR ]]; then
    msg_fatal "I am running already. exiting..."
else
    mkdir "$LOCKDIR"
	if [ $? -ne 0 ] ; then
		msg_fatal "someone beat me to it ..."
	fi
fi

function _temp_cleaner {
	rm -rf "${TMP_DIR:?}/"*
}

function get_xs_version {
	# get_version=`cat /etc/redhat-release | awk -F'-' {'print $1'}`
	get_version=$(awk -F'-' '{print $1}' < /etc/redhat-release) 
	case "${get_version}" in
		"XenServer release 6.0.0" )
		DISTRO="boston"
		;;

		"XenServer release 6.0.2" )
		DISTRO="sanibel"
		;;

		"XenServer release 6.1.0" )
		DISTRO="tampa"
		;;

		"XenServer release 6.2.0" )
		DISTRO="clearwater"
		;;

		"XenServer release 6.5.0" )
		DISTRO="creedence"
		;;

		"XenServer release 7.0.0" )
		DISTRO="dundee"
		;;

		* )
		echo "Unable to detect version of XenServer, terminating"
		exit 0
	;;

	esac
}

function apply_patches {
	[ -d $TMP_DIR ] || mkdir $TMP_DIR
	[ -d $CACHE_DIR ] || mkdir $CACHE_DIR

	echo "Looking for missing patches for $DISTRO..."

	grep -v '^#' patches/$DISTRO | while IFS='|'; read PATCH_NAME PATCH_UUID PATCH_URL PATCH_KB; do
		PATCH_FILE=$(echo "$PATCH_URL" | awk -F/ '{print $NF}')

		if [ -f /var/patch/applied/$PATCH_UUID ]; then
			echo "$PATCH_NAME has been applied, moving on..."
		else
			echo "Found missing patch $PATCH_NAME, checking to see if it exists in cache..."

			if [ ! -f $CACHE_DIR/$PATCH_NAME.xsupdate ]; then
				echo "Downloading from $PATCH_URL..."
				wget -q $PATCH_URL -O $TMP_DIR/$PATCH_FILE
				echo "Unpacking..."
				unzip -qq $TMP_DIR/$PATCH_FILE -d $CACHE_DIR
				## cleanup the patchfile 
				rm $TMP_DIR/$PATCH_FILE
			fi	

			echo "Applying $PATCH_NAME... [ Release Notes @ $PATCH_KB ]"

			_target_PATCH_UUID=$(xe patch-upload file-name=$CACHE_DIR/$PATCH_NAME.xsupdate)

			# sanity check

			if [[ -z $_target_PATCH_UUID ]]; then

				echo "Patch $PATCH_UUID failure, not present on host"
				echo "Check that it exists at :"
				echo " $CACHE_DIR/$PATCH_NAME.xsupdate and rerun the script"
			else
				if [[ $_target_PATCH_UUID == "$PATCH_UUID" ]]; then
						xe patch-apply uuid=$PATCH_UUID host-uuid=$INSTALLATION_UUID
						# sanity check
						if [[ $? -eq 0 ]]; then
							rm $CACHE_DIR/${PATCH_NAME}.xsupdate
							rm $CACHE_DIR/${PATCH_NAME}.bz2
						else
							break
							echo "$PATCH_NAME patch failed, wasnt applied on this host"	
							echo "check reasons of possible failure"
							echo "A. full disk"
							echo "B. other reasons in log : ///"
						fi
                else
                		echo "Patch ID $PATCH_UUID is not equal to $_target_PATCH_UUID as returned form the actually uploaded patch"
                		echo " check that the supplied UUIDs in the relevant version file patches/$DISTRO are correct"
                		echo "-------"
                		echo " you can also try reruning this script and/or try to manually apply this patch with uuid $_target_PATCH_UUID"
                fi
          fi

		xe patch-clean uuid=$PATCH_UUID
		fi
done

#call the lceaning function 
# todo(10): ideially it should be incorporated in the trap function with a double loop

_temp_cleaner

	echo "Everything has been patched up!"
}

get_xs_version
apply_patches
