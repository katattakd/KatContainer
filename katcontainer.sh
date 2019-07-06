### Note: This script REQUIRES that the host system has an x86_64 CPU and a recent Linux kernel!
## Support for more architectures may be added later on, but this script will likely stay Linux-only.

### Note: You will need coreutils du, bash, jq, wget, sudo, and tar to run this script.
## Busybox may work instead of coreutils, but I haven't tested it yet.

### General configuration

export CONTAINERS_DIR="$PWD/.containers"
export CONTAINER_NAME="$2"
export CACHE_DIR="$PWD/.cache"

### Container management config

export CONTAINER_ID="$CONTAINER_NAME-$((1 + RANDOM % 1000))"
export CRUN_DOWNLOAD="https://kittyhacker101.tk/Static/crun"

### Container creation config

## Note: It's recommended that you set the mirror to the one with the lowest ping.
export DEFAULT_MIRROR="http://dl-cdn.alpinelinux.org/alpine"
export BOOTSTRAP_VERSION="v3.10"
export BOOTSTRAP_VERSION_APK_TOOLS="2.10.4-r1"

export DEFAULT_VERSION="v3.10"
## All you need for a functional container. Package management is handled by the script, so having a package manager installed in the container isn't necessary.
export DEFAULT_PACKAGES="busybox"
## The below list of packages is useful for developing containers, but it's recommended that you use as few dependencies as possible for your finished container.
#export DEFAULT_PACKAGES="alpine-base alpine-sdk bash byobu htop curl wget nano busybox-extras python"

export DEFAULT_HOSTNAME="alpine"
export DEFAULT_RESOLV="/etc/resolv.conf"
## Default console width, works with basically all resoultions.
export DEFAULT_CONSOLE_WIDTH="80"
export DEFAULT_CONSOLE_HEIGHT="25"
## Useful for developing containers, but often requires you to resize the console window.
#export DEFAULT_CONSOLE_WIDTH="102"
#export DEFAULT_CONSOLE_HEIGHT="38"

export DEFAULT_ARGS="\"sh\", \"-l\""

export CAPABILITIES="\"CAP_AUDIT_WRITE\", \"CAP_KILL\", \"CAP_NET_BIND_SERVICE\""
export DEFAULT_READ_ONLY_ROOT="false"

export DEFAULT_MAX_MEM_MB="100"
export DEFAULT_MAX_TMP_MEM_MB="250"

export DEFAULT_ASSIGNED_CPUS="0-3"

export DEFAULT_MAX_FILE_DESC="1024"
export DEFAULT_MAX_THREADS="1024"

## Note: The /home directory can't be read or written to by processes in the container. However, if you make folders/files inside the home folder, and chown them with the UID 1000, then the container processes will be able to read and write to those files.

## Note: The bootstrap process uses a shared cache, to reduce bandwidth usage when managing many containers.

export DEFAULT_MIRROR="http://mirror.leaseweb.com/alpine"


### End configuration

list_cache () {
	if [ "$(ls $CACHE_DIR)" ]; then
		echo "Cache sizes:"
		cd $CACHE_DIR
		for CACHE_FOLDER in *; do
			sudo du -sbhPx $CACHE_FOLDER
		done
	fi
}

list_containers () {
	if [ "$(ls $CONTAINERS_DIR)" ]; then
		echo "Configured containers:"
		cd $CONTAINERS_DIR
		for CONTAINER_FOLDER in *; do
			export VERSION=$(cat $CONTAINER_FOLDER/.version)
			sudo printf "$VERSION	"
			sudo du -sbhPx $CONTAINER_FOLDER
		done
	else
		echo "It looks like you don't have any containers configured. Try creating one with this script's \"add\" command."
	fi
	exit
}

del_container () {
	echo "Removing container..."
	sudo rm -rf $CONTAINERS_DIR/$CONTAINER_NAME
	if [ $? -eq 1 ]; then
		echo "Unable to remove container!"
		exit
	fi
	echo "Deleted container \"$CONTAINER_NAME\"!"
}

run_container () {
	download_crun
	echo "Running container \"$CONTAINER_NAME\"..."
	cd $CONTAINERS_DIR/$CONTAINER_NAME
	if [ $? -eq 1 ]; then
		echo "Unable to open container directory!"
		exit
	fi
	sudo $CACHE_DIR/crun/crun run $CONTAINER_ID
}

add_container () {
	get_settings
	download_apk_tools
	init_container
	configure_container
	generate_config
	echo "Created container with name \"$CONTAINER_NAME\"!"
}

update_container () {
	get_update_settings
	download_apk_tools
	cd $CONTAINERS_DIR/$CONTAINER_NAME/rootfs
		if [ $? -eq 1 ]; then
		echo "Unable to open container directory!"
		exit
	fi
	echo "Updating container filesystem..."
	sudo rm etc/apk/repositories
	sudo -E bash -c 'printf "$MIRROR/$FINAL_VERSION/main\n$MIRROR/$FINAL_VERSION/community" > etc/apk/repositories'
	sudo $CACHE_DIR/apk/sbin/apk.static -q --no-progress -X $MIRROR/$FINAL_VERSION/main -X $MIRROR/$FINAL_VERSION/community -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch x86_64 --cache-dir $CACHE_DIR/apk update
	sudo $CACHE_DIR/apk/sbin/apk.static -q -X $MIRROR/$FINAL_VERSION/main -X $MIRROR/$FINAL_VERSION/community -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch x86_64 --cache-dir $CACHE_DIR/apk upgrade
	if [ ! -z "$ADD_PACKAGES" ]; then
		echo "Adding $ADD_PACKAGES to container..."
		sudo $CACHE_DIR/apk/sbin/apk.static -q -X $MIRROR/$FINAL_VERSION/main -X $MIRROR/$FINAL_VERSION/community -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch x86_64 --cache-dir $CACHE_DIR/apk add $ADD_PACKAGES
	fi
	if [ ! -z "$DEL_PACKAGES" ]; then
		echo "Deleting $DEL_PACKAGES from container..."
		sudo $CACHE_DIR/apk/sbin/apk.static -q -X $MIRROR/$FINAL_VERSION/main -X $MIRROR/$FINAL_VERSION/community -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch x86_64 --cache-dir $CACHE_DIR/apk del $DEL_PACKAGES
	fi
	sudo chown -hR 1000 $CONTAINERS_DIR/$CONTAINER_NAME/rootfs
	sudo chown -hR root home
	sudo chmod -R 711 home
	echo "Container updated!"
}

get_settings () {
	echo "You will now choose the settings for your new container. Default options are in brackets, and can be chosen by pressing enter."

	echo -n "Alpine version [$DEFAULT_VERSION]: "
	read FINAL_VERSION
	if [ -z "$FINAL_VERSION" ]; then
		export FINAL_VERSION="$DEFAULT_VERSION"
	fi
	export FINAL_VERSION

	echo -n "Alpine mirror [$DEFAULT_MIRROR]: "
	read MIRROR
	if [ -z "$MIRROR" ]; then
		export MIRROR="$DEFAULT_MIRROR"
	fi
	export MIRROR

	echo -n "Packages [$DEFAULT_PACKAGES]: "
	read PACKAGES
	if [ -z "$PACKAGES" ]; then
		export PACKAGES="$DEFAULT_PACKAGES"
	fi
	export PACKAGES

	echo -n "Hostname [$DEFAULT_HOSTNAME]: "
	read HOSTNAME
	if [ -z "$HOSTNAME" ]; then
		export HOSTNAME="$DEFAULT_HOSTNAME"
	fi
	export HOSTNAME

	echo -n "DNS config [$DEFAULT_RESOLV]: "
	read RESOLV_CONF
	if [ -z "$RESOLV_CONF" ]; then
		export RESOLV_CONF="$DEFAULT_RESOLV"
	fi
	export RESOLV_CONF

	echo -n "Read-only root [$DEFAULT_READ_ONLY_ROOT]: "
	read READ_ONLY_ROOT
	if [ -z "$READ_ONLY_ROOT" ]; then
		export READ_ONLY_ROOT="$DEFAULT_READ_ONLY_ROOT"
	fi
	export READ_ONLY_ROOT

	echo -n "Startup command [$DEFAULT_ARGS]: "
	read ARGS
	if [ -z "$ARGS" ]; then
		export ARGS="$DEFAULT_ARGS"
	fi
	export ARGS

	echo -n "Assigned CPUs [$DEFAULT_ASSIGNED_CPUS]: "
	read ASSIGNED_CPUS
	if [ -z "$ASSIGNED_CPUS" ]; then
		export ASSIGNED_CPUS="$DEFAULT_ASSIGNED_CPUS"
	fi
	export ASSIGNED_CPUS

	echo -n "Max RAM usage (in MB) [$DEFAULT_MAX_MEM_MB]: "
	read MAX_MEM_MB
	if [ -z "$MAX_MEM_MB" ]; then
		export MAX_MEM_MB="$DEFAULT_MAX_MEM_MB"
	fi
	export MAX_MEM_MB

	echo -n "Max /tmp size (in MB) [$DEFAULT_MAX_TMP_MEM_MB]: "
	read MAX_TMP_MEM_MB
	if [ -z "$MAX_TMP_MEM_MB" ]; then
		export MAX_TMP_MEM_MB="$DEFAULT_MAX_TMP_MEM_MB"
	fi
	export MAX_TMP_MEM_MB

	echo -n "Max open files [$DEFAULT_MAX_FILE_DESC]: "
	read MAX_FILE_DESC
	if [ -z "$MAX_FILE_DESC" ]; then
		export MAX_FILE_DESC="$DEFAULT_MAX_FILE_DESC"
	fi
	export MAX_FILE_DESC

	echo -n "Max threads [$DEFAULT_MAX_THREADS]: "
	read MAX_THREADS
	if [ -z "$MAX_THREADS" ]; then
		export MAX_THREADS="$DEFAULT_MAX_THREADS"
	fi
	export MAX_THREADS

	echo -n "Console width [$DEFAULT_CONSOLE_WIDTH]: "
	read CONSOLE_WIDTH
	if [ -z "$CONSOLE_WIDTH" ]; then
		export CONSOLE_WIDTH="$DEFAULT_CONSOLE_WIDTH"
	fi
	export CONSOLE_WIDTH

	echo -n "Console height [$DEFAULT_CONSOLE_HEIGHT]: "
	read CONSOLE_HEIGHT
	if [ -z "$CONSOLE_HEIGHT" ]; then
		export CONSOLE_HEIGHT="$DEFAULT_CONSOLE_HEIGHT"
	fi
	export CONSOLE_HEIGHT
}

get_update_settings () {
	export DEFAULT_MIRROR=$(cat $CONTAINERS_DIR/$CONTAINER_NAME/.mirror)
	export DEFAULT_VERSION=$(cat $CONTAINERS_DIR/$CONTAINER_NAME/.version)

	echo "You will now choose the settings for updating your container's packages. Default options are in brackets, and can be chosen by pressing enter."

	echo -n "Alpine version [$DEFAULT_VERSION]: "
	read FINAL_VERSION
	if [ -z "$FINAL_VERSION" ]; then
		export FINAL_VERSION="$DEFAULT_VERSION"
	fi
	export FINAL_VERSION
	printf "$FINAL_VERSION" > $CONTAINERS_DIR/$CONTAINER_NAME/.version

	echo -n "Alpine mirror [$DEFAULT_MIRROR]: "
	read MIRROR
	if [ -z "$MIRROR" ]; then
		export MIRROR="$DEFAULT_MIRROR"
	fi
	export MIRROR
	printf "$MIRROR" > $CONTAINERS_DIR/$CONTAINER_NAME/.mirror

	echo -n "Packages to add [none]: "
	read ADD_PACKAGES
	export ADD_PACKAGES
	
	echo -n "Packages to remove [none]: "
	read DEL_PACKAGES
	export DEL_PACKAGES
}

# TODO: Update this to work with crun
download_crun () {
	mkdir -p $CACHE_DIR/crun
	cd $CACHE_DIR/crun
	if [ $? -eq 1 ]; then
		echo "Unable to open cache directory!"
		exit
	fi
	wget -nc $CRUN_DOWNLOAD -O crun &> /dev/null
	sudo chmod +x crun
	if [ $? -eq 1 ]; then
		echo "Unable to download crun!"
		exit
	fi
}

download_apk_tools () {
	mkdir -p $CACHE_DIR/apk
	cd $CACHE_DIR/apk
	if [ $? -eq 1 ]; then
		echo "Unable to open cache directory!"
		exit
	fi
	wget -nc $MIRROR/$BOOTSTRAP_VERSION/main/x86_64/apk-tools-static-$BOOTSTRAP_VERSION_APK_TOOLS.apk &> /dev/null
	if [ $? -eq 1 ]; then
		echo "Unable to download apk-tools!"
		exit
	fi
	if [ ! -d "sbin" ]; then
		tar -xzf $CACHE_DIR/apk/apk-tools-static-*.apk &> /dev/null
		if [ $? -eq 1 ]; then
			echo "Unable to extract apk-tools!"
			exit
		fi
		rm .??*
		rm sbin/apk.static.*
	fi
}

init_container () {
	mkdir -p $CONTAINERS_DIR/$CONTAINER_NAME/rootfs
	cd $CONTAINERS_DIR/$CONTAINER_NAME/rootfs
	if [ $? -eq 1 ]; then
		echo "Unable to open container directory!"
		exit
	fi
	echo "Installing container filesystem..."
	sudo $CACHE_DIR/apk/sbin/apk.static -q -X $MIRROR/$FINAL_VERSION/main -X $MIRROR/$FINAL_VERSION/community -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch x86_64 --cache-dir $CACHE_DIR/apk --initdb add $PACKAGES
	if [ $? -eq 1 ]; then
		echo "Unable to install chroot filesystem!"
		exit
	fi
}

configure_container () {
	echo "Finishing up..."
	sudo mkdir -p home root
	sudo -E bash -c 'printf "$MIRROR/$FINAL_VERSION/main\n$MIRROR/$FINAL_VERSION/community" > etc/apk/repositories'
	printf "$MIRROR" > ../.mirror
	printf "$FINAL_VERSION" > ../.version
	sudo cp $RESOLV_CONF etc/resolv.conf
	sudo -E bash -c 'printf "$HOSTNAME" > etc/hostname'
	sudo chown -hR 1000 $CONTAINERS_DIR/$CONTAINER_NAME/rootfs
	sudo chown -hR root home
	sudo chmod -R 711 home
}

# TODO: Figure out why the UID remapping namespace was causing container launches to fail, and fix the issue.
generate_config () {
	let MAX_MEM=$MAX_MEM_MB*1000000
	export MAX_TMP_MEM=$MAX_TMP_MEM_MB"m"

	echo "{
		\"ociVersion\": \"1.0.1-dev\",
		\"process\": {
			\"terminal\": true,
			\"consoleSize\": {
				\"height\": $CONSOLE_HEIGHT,
				\"width\": $CONSOLE_WIDTH
			},
			\"user\": {
				\"uid\": 0,
				\"gid\": 0
			},
			\"args\": [
				$ARGS
			],
			\"env\": [
				\"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\",
				\"TERM=xterm\",
				\"HOME=/root\"
			],
			\"cwd\": \"/root\",
			\"capabilities\": {
				\"bounding\": [
					$CAPABILITIES
				],
				\"effective\": [
					$CAPABILITIES
				],
				\"inheritable\": [
					$CAPABILITIES
				],
				\"permitted\": [
					$CAPABILITIES
				],
				\"ambient\": [
					$CAPABILITIES
				]
			},
			\"rlimits\": [
				{
					\"type\": \"RLIMIT_NOFILE\",
					\"hard\": $MAX_FILE_DESC,
					\"soft\": $MAX_FILE_DESC
				},
				{
					\"type\": \"RLIMIT_NPROC\",
					\"hard\": $MAX_THREADS,
					\"soft\": $MAX_THREADS
				}
			],
			\"noNewPrivileges\": true
		},
		\"root\": {
			\"path\": \"$CONTAINERS_DIR/$CONTAINER_NAME/rootfs\",
			\"readonly\": $READ_ONLY_ROOT
		},
		\"hostname\": \"$HOSTNAME\",
		\"mounts\": [
			{
				\"destination\": \"/proc\",
				\"type\": \"proc\",
				\"source\": \"proc\"
			},
			{
				\"destination\": \"/dev\",
				\"type\": \"tmpfs\",
				\"source\": \"tmpfs\",
				\"options\": [
					\"nosuid\",
					\"strictatime\",
					\"mode=755\",
					\"size=128k\"
				]
			},
			{
				\"destination\": \"/dev/pts\",
				\"type\": \"devpts\",
				\"source\": \"devpts\",
				\"options\": [
					\"nosuid\",
					\"noexec\",
					\"newinstance\",
					\"ptmxmode=0666\",
					\"mode=0620\"
				]
			},
			{
				\"destination\": \"/dev/shm\",
				\"type\": \"tmpfs\",
				\"source\": \"shm\",
				\"options\": [
					\"nosuid\",
					\"noexec\",
					\"nodev\",
					\"mode=1777\",
					\"size=128k\"
				]
			},
			{
				\"destination\": \"/dev/mqueue\",
				\"type\": \"mqueue\",
				\"source\": \"mqueue\",
				\"options\": [
					\"nosuid\",
					\"noexec\",
					\"nodev\"
				]
			},
			{
				\"destination\": \"/sys\",
				\"type\": \"none\",
				\"source\": \"/sys\",
				\"options\": [
					\"rbind\",
					\"nosuid\",
					\"noexec\",
					\"nodev\",
					\"ro\"
				]
			},
			{
				\"destination\": \"/tmp\",
				\"type\": \"tmpfs\",
				\"source\": \"tmpfs\",
				\"options\": [
					\"nosuid\",
					\"noatime\",
					\"mode=755\",
					\"size=$MAX_TMP_MEM\"
				]
			}
		],
		\"linux\": {
			\"resources\": {
				\"cpu\": {
					\"cpus\": \"$ASSIGNED_CPUS\"
				},
				\"memory\": {
					\"limit\": $MAX_MEM,
					\"reservation\": $MAX_MEM,
					\"swap\": $MAX_MEM,
					\"kernel\": -1,
					\"kerneltcp\": -1,
					\"swappiness\": 0
				},
				\"devices\": [
					{
						\"allow\": false,
						\"access\": \"rwm\"
					}
				]
			},
			\"uidMappings\": [
				{
					\"containerID\": 0,
					\"hostID\": 1000,
					\"size\": 32000
				}
			],
			\"gidMappings\": [
				{
					\"containerID\": 0,
					\"hostID\": 1000,
					\"size\": 32000
				}
			],
			\"namespaces\": [
				{
					\"type\": \"pid\"
				},
				{
					\"type\": \"ipc\"
				},
				{
					\"type\": \"uts\"
				},
				{
					\"type\": \"cgroup\"
				},
				{
					\"type\": \"mount\"
				},
				{
					\"type\": \"user\"
				}
			],
			\"maskedPaths\": [
				\"/proc/kcore\",
				\"/proc/latency_stats\",
				\"/proc/timer_list\",
				\"/proc/timer_stats\",
				\"/proc/sched_debug\",
				\"/sys/firmware\",
				\"/proc/scsi\"
			],
			\"readonlyPaths\": [
				\"/proc/asound\",
				\"/proc/bus\",
				\"/proc/fs\",
				\"/proc/irq\",
				\"/proc/sys\",
				\"/proc/sysrq-trigger\"
			]
		}
	}" | jq --tab -M > $CONTAINERS_DIR/$CONTAINER_NAME/config.json
}

if [ "$1" == "add" ]; then
	if [ -z $CONTAINER_NAME ]; then
		echo "You must specify a name for the container."
		exit
	fi
	if [ -d "$CONTAINERS_DIR/$CONTAINER_NAME" ]; then
		echo "A container with that name already exists."
		exit
	fi
	add_container
elif [ "$1" == "del" ]; then
	if [ -z $CONTAINER_NAME ]; then
		echo "You must specify a valid container."
		list_containers
		exit
	fi
	if [ ! -d "$CONTAINERS_DIR/$CONTAINER_NAME" ]; then
		echo "Unable to find container!"
		exit
	fi
	del_container
elif [ "$1" == "run" ]; then
	if [ -z $CONTAINER_NAME ]; then
		echo "You must specify a valid container."
		list_containers
		exit
	fi
	if [ ! -d "$CONTAINERS_DIR/$CONTAINER_NAME" ]; then
		echo "Unable to find container!"
		exit
	fi
	run_container
elif [ "$1" == "update" ]; then
	if [ -z $CONTAINER_NAME ]; then
		echo "You must specify a valid container."
		list_containers
		exit
	fi
	if [ ! -d "$CONTAINERS_DIR/$CONTAINER_NAME" ]; then
		echo "Unable to find container!"
		exit
	fi
	update_container
elif [ "$1" == "edit" ]; then
	if [ -z $CONTAINER_NAME ]; then
		echo "You must specify a valid container."
		list_containers
		exit
	fi
	if [ ! -d "$CONTAINERS_DIR/$CONTAINER_NAME" ]; then
		echo "Unable to find container!"
		exit
	fi
	if [ ! -d "$CONTAINERS_DIR/$CONTAINER_NAME/config_new.json" ]; then
		cp $CONTAINERS_DIR/$CONTAINER_NAME/config.json $CONTAINERS_DIR/$CONTAINER_NAME/config_new.json
	fi
	nano $CONTAINERS_DIR/$CONTAINER_NAME/config_new.json
	cat $CONTAINERS_DIR/$CONTAINER_NAME/config_new.json | jq --tab -M > $CONTAINERS_DIR/$CONTAINER_NAME/config_new.fmt.json
	if [ ! $? -eq 0 ]; then
		rm $CONTAINERS_DIR/$CONTAINER_NAME/config_new.fmt.json $CONTAINERS_DIR/$CONTAINER_NAME/config_new.json
		echo "Unable to parse configuration! All changes have been discarded."
		exit
	fi
	rm $CONTAINERS_DIR/$CONTAINER_NAME/config.json $CONTAINERS_DIR/$CONTAINER_NAME/config_new.json
	mv $CONTAINERS_DIR/$CONTAINER_NAME/config_new.fmt.json $CONTAINERS_DIR/$CONTAINER_NAME/config.json
elif [ "$1" == "list" ]; then
	list_cache
	list_containers
elif [ "$1" == "clean" ]; then
	echo "Emptying the cache..."
	sudo rm -rf $CACHE_DIR
	if [ $? -eq 1 ]; then
		echo "Unable to remove cache directory!"
		exit
	fi
	echo "Cache emptied!"
	mkdir $CACHE_DIR
elif [ "$1" == "help" ]; then
	echo "help - Shows a list of the script's commands, and what they do."
	echo "add [container name] - Creates and configures an Alpine linux based container."
	echo "del [container name] - Deletes a container."
	echo "update [container name] - Updates a container's installed packages, and allows you to add or remove packages."
	echo "edit [container name] - Allows you to edit a container's underlying configuration. Container configuration is in OCI format."
	echo "run [container name] - Securely runs a container."
	echo "list - Lists all configured containers, and displays the cache size."
	echo "clean - Empties all caches used by the script."
else
	echo "You must specify a valid command. Valid commands are \"help\", \"add\", \"del\", \"update\", \"edit\", \"run\", \"list\", and \"clean\"."
	exit
fi