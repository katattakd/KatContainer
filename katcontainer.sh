#!/bin/sh
### General configuration
export CONTAINERS_DIR="$PWD/containers"
export CONTAINER_NAME="$2"
export CACHE_DIR="$PWD/cache"
## This MUST be an architecture the container host is capable of running natively (You can use x86 as the ARCH on an x86_64 system, but you can't use ARM as the ARCH on an x86_64 system).
export DEFAULT_ARCH="x86_64"

### Container management config
export CONTAINER_ID="$CONTAINER_NAME-$((1 + RANDOM % 1000))"

### Container creation config
## Note: It's recommended that you set the mirror to the one with the lowest ping.
export DEFAULT_MIRROR="http://dl-cdn.alpinelinux.org/alpine"
export BOOTSTRAP_VERSION="v3.11"
export BOOTSTRAP_VERSION_APK_TOOLS="2.10.4-r3"

export DEFAULT_VERSION="latest-stable"
## Busybox and dumb-init are automatically added to all created containers. Package management is handled by the script, so having a package manager installed in the container isn't necessary.
export DEFAULT_PACKAGES=""
## The minimum set of packages you need to build stuff in a container. You'll probably want more than this.
#export DEFAULT_PACKAGES="alpine-base alpine-sdk"
## The below list of packages is useful for developing containers or building stuff in them, but it's recommended that you use as few dependencies as possible for your finished container.
#export DEFAULT_PACKAGES="alpine-base alpine-sdk coreutils bash byobu htop curl wget nano busybox-extras python perl autoconf cmake automake libtool"

export DEFAULT_ARGS="sh -l"
export DEFAULT_READ_ONLY_ROOT="false"
export DEFAULT_MAX_MEM_MB="512"
export DEFAULT_ASSIGNED_CPUS="0-3"

## Note: The bootstrap and update process uses a shared cache, to reduce bandwidth usage when managing many containers.

### End configuration
#set -euo pipefail

list_cache () {
	if [ "$(ls $CACHE_DIR)" ]; then
		echo "Cache sizes:"
		cd $CACHE_DIR
		for CACHE_FOLDER in *; do
			sudo du -shx $CACHE_FOLDER
		done
	fi
}

list_containers () {
	if [ "$(ls $CONTAINERS_DIR)" ]; then
		echo "Configured containers:"
		cd $CONTAINERS_DIR
		for CONTAINER_FOLDER in *; do
			export ARCH=$(cat $CONTAINER_FOLDER/.arch)
			export VERSION=$(cat $CONTAINER_FOLDER/.version)
			sudo printf "$VERSION	$ARCH	"
			sudo du -shx $CONTAINER_FOLDER
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
	cd $CONTAINERS_DIR/$CONTAINER_NAME
	if [ $? -eq 1 ]; then
		echo "Unable to open container directory!"
		exit
	fi
	echo "Running container \"$CONTAINER_NAME\"..."
	sudo runc run $CONTAINER_ID
}

chroot_container () {
	cd $CONTAINERS_DIR/$CONTAINER_NAME
	if [ $? -eq 1 ]; then
		echo "Unable to open container directory!"
		exit
	fi
	echo "WARNING: You are running in chroot mode. The container has full unrestricted access to the host system!" 
	echo "Running container \"$CONTAINER_NAME\"..."
	sudo mount --bind /dev rootfs/dev
	sudo mount --bind /sys rootfs/sys
	sudo mount --bind /proc rootfs/proc
	sudo mount --bind /tmp rootfs/tmp
	sudo mount --bind /run rootfs/run
	sudo mount --bind / rootfs/mnt
	sudo chroot rootfs /bin/busybox sh
	sudo umount rootfs/dev
	sudo umount rootfs/sys
	sudo umount rootfs/proc
	sudo umount rootfs/tmp
	sudo umount rootfs/run
	sudo umount rootfs/mnt
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
	mkdir -p $CACHE_DIR/apk-$FINAL_VERSION-$ARCH
	sudo $CACHE_DIR/bootstrap-$BOOTSTRAP_VERSION_APK_TOOLS-$ARCH/sbin/apk.static -q --no-progress $MIRROR_CMD -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch $ARCH --cache-dir $CACHE_DIR/apk-$FINAL_VERSION-$ARCH update
	sudo $CACHE_DIR/bootstrap-$BOOTSTRAP_VERSION_APK_TOOLS-$ARCH/sbin/apk.static -q $MIRROR_CMD -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch $ARCH --cache-dir $CACHE_DIR/apk-$FINAL_VERSION-$ARCH upgrade
	if [ ! -z "$ADD_PACKAGES" ]; then
		echo "Adding $ADD_PACKAGES to container..."
		sudo $CACHE_DIR/bootstrap-$BOOTSTRAP_VERSION_APK_TOOLS-$ARCH/sbin/apk.static -q $MIRROR_CMD -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch $ARCH --cache-dir $CACHE_DIR/apk-$FINAL_VERSION-$ARCH add $ADD_PACKAGES
	fi
	if [ ! -z "$DEL_PACKAGES" ]; then
		echo "Deleting $DEL_PACKAGES from container..."
		sudo $CACHE_DIR/bootstrap-$BOOTSTRAP_VERSION_APK_TOOLS-$ARCH/sbin/apk.static -q $MIRROR_CMD -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch $ARCH --cache-dir $CACHE_DIR/apk-$FINAL_VERSION-$ARCH del $DEL_PACKAGES
	fi
	sudo chown -hR 1000 $CONTAINERS_DIR/$CONTAINER_NAME/rootfs
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

	echo -n "Additional packages [$DEFAULT_PACKAGES]: "
	read PACKAGES
	if [ -z "$PACKAGES" ]; then
		export PACKAGES="$DEFAULT_PACKAGES"
	fi
	export PACKAGES

	echo -n "CPU Architecture [$DEFAULT_ARCH]: "
	read ARCH
	if [ -z "$ARCH" ]; then
		export ARCH="$DEFAULT_ARCH"
	fi
	export ARCH

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
}

get_update_settings () {
	export DEFAULT_MIRROR=$(cat $CONTAINERS_DIR/$CONTAINER_NAME/.mirror)
	export DEFAULT_VERSION=$(cat $CONTAINERS_DIR/$CONTAINER_NAME/.version)
	export ARCH=$(cat $CONTAINERS_DIR/$CONTAINER_NAME/.arch)

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

download_apk_tools () {
	mkdir -p $CACHE_DIR/bootstrap-$BOOTSTRAP_VERSION_APK_TOOLS-$ARCH
	cd $CACHE_DIR/bootstrap-$BOOTSTRAP_VERSION_APK_TOOLS-$ARCH
	if [ $? -eq 1 ]; then
		echo "Unable to open cache directory!"
		exit
	fi
	if [ ! -d "sbin" ]; then
		wget -nc $MIRROR/$BOOTSTRAP_VERSION/main/$ARCH/apk-tools-static-$BOOTSTRAP_VERSION_APK_TOOLS.apk &> /dev/null
		if [ $? -eq 1 ]; then
			echo "Unable to download apk-tools!"
			exit
		fi
		tar -xzf $PWD/apk-tools-static-*.apk &> /dev/null
		if [ $? -eq 1 ]; then
			echo "Unable to extract apk-tools!"
			exit
		fi
		rm .??*
		rm sbin/apk.static.*
		rm *.apk
	fi
	# Necessary for using APK-tools
	export MIRROR_CMD="-X $MIRROR/$FINAL_VERSION/main -X $MIRROR/$FINAL_VERSION/community"
	if [ $FINAL_VERSION == "edge" ]; then
		export MIRROR_CMD="$MIRROR_CMD -X $MIRROR/$FINAL_VERSION/testing"
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
	mkdir -p $CACHE_DIR/apk-$FINAL_VERSION-$ARCH
	sudo $CACHE_DIR/bootstrap-$BOOTSTRAP_VERSION_APK_TOOLS-$ARCH/sbin/apk.static -q $MIRROR_CMD -U --allow-untrusted --root $CONTAINERS_DIR/$CONTAINER_NAME/rootfs --arch $ARCH --cache-dir $CACHE_DIR/apk-$FINAL_VERSION-$ARCH --initdb add busybox dumb-init $PACKAGES
	if [ $? -eq 1 ]; then
		echo "Unable to install chroot filesystem!"
		exit
	fi
}

configure_container () {
	echo "Finishing up..."
	sudo mkdir -p root sys run mnt
	sudo -E bash -c 'printf "$MIRROR/$FINAL_VERSION/main\n$MIRROR/$FINAL_VERSION/community" > etc/apk/repositories'
        sudo -E bash -c 'printf "#!/bin/busybox sh\n$DEFAULT_ARGS" > init.sh'
	printf "$MIRROR" > ../.mirror
	printf "$FINAL_VERSION" > ../.version
	printf "$ARCH" > ../.arch
	sudo -E bash -c 'printf alpine > etc/hostname'
	sudo chown -hR 1000 $CONTAINERS_DIR/$CONTAINER_NAME/rootfs
	sudo chmod +x init.sh
}

generate_config () {
	let MAX_MEM=$MAX_MEM_MB*1000000
	export MAX_TMP_MEM=$(($MAX_MEM_MB/2))"m"

	echo "{
		\"ociVersion\": \"1.0.1-dev\",
		\"process\": {
			\"terminal\": true,
			\"consoleSize\": {
				\"width\": 80,
				\"height\": 25
			},
			\"user\": {
				\"uid\": 0,
				\"gid\": 0
			},
			\"args\": [
				\"/usr/bin/dumb-init\",
				\"/init.sh\"
			],
			\"env\": [
				\"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\",
				\"TERM=xterm\",
				\"HOME=/root\"
			],
			\"cwd\": \"/root\",
			\"capabilities\": {
				\"bounding\": [
					\"CAP_AUDIT_WRITE\"
				],
				\"effective\": [
					\"CAP_AUDIT_WRITE\"
				],
				\"inheritable\": [
					\"CAP_AUDIT_WRITE\"
				],
				\"permitted\": [
					\"CAP_AUDIT_WRITE\"
				],
				\"ambient\": [
					\"CAP_AUDIT_WRITE\"
				]
			},
			\"rlimits\": [
				{
					\"type\": \"RLIMIT_CORE\",
					\"hard\": 0,
					\"soft\": 0
				},
				{
					\"type\": \"RLIMIT_NICE\",
					\"hard\": 0,
					\"soft\": 0
				},
				{
					\"type\": \"RLIMIT_NOFILE\",
					\"hard\": 2048,
					\"soft\": 2048
				},
				{
					\"type\": \"RLIMIT_NPROC\",
					\"hard\": 1024,
					\"soft\": 1024
				},
				{
					\"type\": \"RLIMIT_SIGPENDING\",
					\"hard\": 8192,
					\"soft\": 8192
				}
			],
			\"oomScoreAdj\": 1000,
			\"noNewPrivileges\": true
		},
		\"root\": {
			\"path\": \"rootfs\",
			\"readonly\": $READ_ONLY_ROOT
		},
		\"hostname\": \"alpine\",
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
			},
			{
				\"destination\": \"/etc/resolv.conf\",
				\"type\": \"bind\",
				\"source\": \"/etc/resolv.conf\",
				\"options\": [
					\"ro\",
					\"rbind\",
					\"rprivate\",
					\"nosuid\",
					\"noexec\",
					\"nodev\"
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
					\"kernel\": $MAX_MEM,
					\"kerneltcp\": $MAX_MEM
				},
				\"pids\": {
					\"limit\": 1024
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
					\"size\": 1
				}
			],
			\"gidMappings\": [
				{
					\"containerID\": 0,
					\"hostID\": 1000,
					\"size\": 1
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
				\"/proc/acpi\",
				\"/proc/asound\",
				\"/proc/keys\",
				\"/proc/kcore\",
				\"/proc/latency_stats\",
				\"/proc/timer_list\",
				\"/proc/timer_stats\",
				\"/proc/sched_debug\",
				\"/sys/firmware\",
				\"/proc/scsi\"
			],
			\"readonlyPaths\": [
				\"/proc/bus\",
				\"/proc/fs\",
				\"/proc/irq\",
				\"/proc/sys\",
				\"/proc/sysrq-trigger\"
			]
		}
	}" | jq --tab -M . > $CONTAINERS_DIR/$CONTAINER_NAME/config.json
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
elif [ "$1" == "chroot" ]; then
	if [ -z $CONTAINER_NAME ]; then
		echo "You must specify a valid container."
		list_containers
		exit
	fi
	if [ ! -d "$CONTAINERS_DIR/$CONTAINER_NAME" ]; then
		echo "Unable to find container!"
		exit
	fi
	chroot_container
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
	cat $CONTAINERS_DIR/$CONTAINER_NAME/config_new.json | jq --tab -M . > $CONTAINERS_DIR/$CONTAINER_NAME/config_new.fmt.json
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
	echo "chroot [container name] - Runs a container with no sandboxing from the host system. May be useful for troubleshooting issues."
	echo "list - Lists all configured containers, and displays the cache size."
	echo "clean - Empties all caches used by the script."
else
	echo "You must specify a valid command. Valid commands are \"help\", \"add\", \"del\", \"update\", \"edit\", \"run\", \"chroot\", \"list\", and \"clean\"."
	exit
fi
