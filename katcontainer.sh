#!/bin/bash

# Required dependencies: Coreutils, bash, sudo
# Additional dependencies:
#	- curl OR apk-tools (Required for bootstrapping containers, curl can be removed after apk-tools is cached.)
#	- runc (Required for running sandboxed containers, containers can be run unsandboxed with the chroot command.)
#	- jq (Required for creating or modifying containers.)

# Warning: Do not move cache or container directories to hosts with different CPU architectures. This can result in container packages becoming corrupted.

# Storage directories
export CONTAINER_DIR="$PWD/containers"
export CACHE_DIR="$PWD/cache"

# Package manager options
export MIRROR="https://sjc.edge.kernel.org/alpine/" # Change this to your closest mirror.
export DEFAULT_VERSION="latest-stable"
export APK_FLAGS="--cache-max-age 360"

# Bootstrap config (ignored if apk is installed)
export BOOTSTRAP_VERSION="v3.11"
export BOOTSTRAP_VERSION_APK="2.10.5-r0" # Package apk-tools-static

#################### END OF CONFIGURATION ####################

set -euo pipefail

# Returns the path to apk in the $APK variable. If apk is not installed, it is downloaded into the cache.
get_apk () {
	if which apk &> /dev/null; then
		export APK=$(which apk)
	else
		if [ ! -f "$CACHE_DIR/bootstrap/apk-$BOOTSTRAP_VERSION_APK" ]; then
			case "`uname -m`" in
				x86_64)
					export ARCH="x86_64";;
				aarch64)
					export ARCH="aarch64";;
				*)
					echo "Unsupported architecture! Please install apk-tools manually."
					exit;;
			esac

			mkdir -p "$CACHE_DIR/bootstrap"
			cd "$CACHE_DIR/bootstrap"

			echo "Downloading bootstrap apk-tools..."
			curl -sS "$MIRROR/$BOOTSTRAP_VERSION/main/$ARCH/apk-tools-static-$BOOTSTRAP_VERSION_APK.apk" | tar xzf - &> /dev/null

			mv sbin/apk.static "$CACHE_DIR/bootstrap/apk-$BOOTSTRAP_VERSION_APK"
			rm -r sbin
			rm .??*
		fi
		export APK="$CACHE_DIR/bootstrap/apk-$BOOTSTRAP_VERSION_APK"
	fi
	if [ ! -d "$CACHE_DIR/bootstrap/apk-keys" ]; then
		mkdir -p "$CACHE_DIR/bootstrap/apk-keys"
		cd "$CACHE_DIR/bootstrap/"

		sudo $APK -X "$MIRROR/$BOOTSTRAP_VERSION/main" $APK_FLAGS -U --allow-untrusted --root "$CACHE_DIR/bootstrap" --cache-dir "$CACHE_DIR/apk-$BOOTSTRAP_VERSION" --initdb add alpine-keys

		cp -r usr/share/apk/keys/* "$CACHE_DIR/bootstrap/apk-keys"
		sudo rm -r dev etc lib proc tmp usr var
	fi
	export APK_FLAGS="$APK_FLAGS --keys-dir $CACHE_DIR/bootstrap/apk-keys"
}

# Get the settings for a new container.
get_container_settings () {
	echo "Please choose the settings for your new container. Defaults are in brackets, and can be picked by pressing enter."

	echo -n "Alpine version [latest-stable]: "
	read VERSION
	[ -z "$VERSION" ] && export VERSION="latest-stable"

	echo -n "Additional packages [none]: "
	read PACKAGES

	echo -n "Assigned CPUs [0-3]: "
	read ASSIGNED_CPUS
	[ -z "$ASSIGNED_CPUS" ] && export ASSIGNED_CPUS="0-3"

	echo -n "Max RAM usage (in MB) [512]: "
	read MAX_MEM_MB
	[ -z "$MAX_MEM_MB" ] && export MAX_MEM_MB="512"
}

# Get the settings for updating a container.
get_update_settings () {
	export DEFAULT_VERSION=$(cat $CONTAINER_DIR/$CONTAINER_NAME/.version)

	echo "Please choose the settings for updating your container. Defaults are in brackets, and can be picked by pressing enter."

	echo -n "Alpine version [$DEFAULT_VERSION]: "
	read VERSION
	[ -z "$VERSION" ] && export VERSION="$DEFAULT_VERSION"

	echo -n "Packages to add [none]: "
	read ADD_PACKAGES

	echo -n "Packages to remove [none]: "
	read DEL_PACKAGES
}

# Create a basic container filesystem.
init_container () {
	mkdir -p "$CONTAINER_DIR/$CONTAINER_NAME/rootfs"
	mkdir -p "$CACHE_DIR/apk-$VERSION"
	cd "$CONTAINER_DIR/$CONTAINER_NAME/rootfs"

	export MIRROR_STRING="-X $MIRROR/$VERSION/main -X $MIRROR/$VERSION/community"
	[ "$VERSION" == "edge" ] && export MIRROR_STRING="$MIRROR_STRING -X $MIRROR/$VERSION/testing"

	echo "Creating container filesystem..."
	sudo $APK $MIRROR_STRING $APK_FLAGS -U --root "$CONTAINER_DIR/$CONTAINER_NAME/rootfs" --cache-dir "$CACHE_DIR/apk-$VERSION" --initdb add busybox dumb-init $PACKAGES
}

# Update a container filesystem.
update_container () {
	mkdir -p "$CACHE_DIR/apk-$VERSION"
	cd "$CONTAINER_DIR/$CONTAINER_NAME/rootfs"

	export MIRROR_STRING="-X $MIRROR/$VERSION/main -X $MIRROR/$VERSION/community"
	[ "$VERSION" == "edge" ] && export MIRROR_STRING="$MIRROR_STRING -X $MIRROR/$VERSION/testing"

	echo "Updating container..."
	sudo $APK $MIRROR_STRING $APK_FLAGS --root "$CONTAINER_DIR/$CONTAINER_NAME/rootfs" --cache-dir "$CACHE_DIR/apk-$VERSION" update
	sudo $APK $MIRROR_STRING $APK_FLAGS --root "$CONTAINER_DIR/$CONTAINER_NAME/rootfs" --cache-dir "$CACHE_DIR/apk-$VERSION" upgrade
	[ ! -z "$ADD_PACKAGES" ] && sudo $APK $MIRROR_STRING $APK_FLAGS --root "$CONTAINER_DIR/$CONTAINER_NAME/rootfs" --cache-dir "$CACHE_DIR/apk-$VERSION" add $ADD_PACKAGES
	[ ! -z "$DEL_PACKAGES" ] && sudo $APK $MIRROR_STRING $APK_FLAGS --root "$CONTAINER_DIR/$CONTAINER_NAME/rootfs" --cache-dir "$CACHE_DIR/apk-$VERSION" del $DEL_PACKAGES

	echo "$VERSION" > ../.version
}

# Populate a container filesystem with necessary files.
configure_container () {
	cd "$CONTAINER_DIR/$CONTAINER_NAME/rootfs"

	sudo mkdir -p root sys run mnt
	printf "alpine" | sudo tee etc/hostname > /dev/null
	sudo touch etc/resolv.conf

	printf "$VERSION" > ../.version

	printf "{
		\"ociVersion\": \"1.0.1\",
		\"root\": {
			\"path\": \"rootfs\",
			\"readonly\": false
		},
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
					\"size=$(($MAX_MEM_MB/2))m\"
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
		\"process\": {
			\"terminal\": true,
			\"consoleSize\": {
				\"width\": 80,
				\"height\": 25
			},
			\"cwd\": \"/root\",
			\"env\": [
				\"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\",
				\"TERM=xterm\",
				\"HOME=/root\"
			],
			\"args\": [
				\"/usr/bin/dumb-init\",
				\"/bin/busybox\",
				\"sh\", \"-l\"
			],
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
					\"hard\": 512,
					\"soft\": 512
				},
				{
					\"type\": \"RLIMIT_SIGPENDING\",
					\"hard\": 4096,
					\"soft\": 4096
				}
			],
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
			\"noNewPrivileges\": true,
			\"oomScoreAdj\": 1000,
			\"user\": {
				\"uid\": 0,
				\"gid\": 0
			}
		},
		\"hostname\": \"alpine\",
		\"linux\": {
			\"namespaces\": [
				{
					\"type\": \"pid\"
				},
				{
					\"type\": \"mount\"
				},
				{
					\"type\": \"ipc\"
				},
				{
					\"type\": \"uts\"
				},
				{
					\"type\": \"user\"
				},
				{
					\"type\": \"cgroup\"
				}
			],
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
			\"resources\": {
				\"cpu\": {
					\"cpus\": \"$ASSIGNED_CPUS\"
				},
				\"memory\": {
					\"limit\": $(($MAX_MEM_MB*1000000)),
					\"swap\": $(($MAX_MEM_MB*1000000))
				},
				\"pids\": {
					\"limit\": 512
				},
				\"devices\": [
					{
						\"allow\": false,
						\"access\": \"rwm\"
					}
				]
			},
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
	}" | jq -c > $CONTAINER_DIR/$CONTAINER_NAME/config.json
}

# Edit a container's OCI configuration.
edit_container () {
	cd "$CONTAINER_DIR/$CONTAINER_NAME"

	cat "config.json" | jq --tab -M > "config.new.json"
	$EDITOR "config.new.json"

	set +e
	cat "config.new.json" | jq -c > "config.new.fmt.json"
	if [ ! $? -eq 0 ]; then
		echo "Unable to parse new config! All changes have been discarded."
		rm config.new.*
		exit
	fi

	rm config.json
	mv config.new.fmt.json config.json
	rm config.new.json
	set -e
}

# Launch an interactive shell into an unsandboxed container.
chroot_container () {
	cd "$CONTAINER_DIR/$CONTAINER_NAME/rootfs"

	sudo mount --rbind /dev dev
	sudo mount --make-rslave dev
	sudo mount --rbind /sys sys
	sudo mount --make-rslave sys
	sudo mount --rbind /proc proc
	sudo mount --make-rslave proc
	sudo mount --rbind /tmp tmp
	sudo mount --make-rslave tmp
	sudo mount --rbind /run run
	sudo mount --make-rslave run
	sudo mount --rbind / mnt
	sudo mount --make-rslave mnt
	sudo mount --bind /etc/resolv.conf etc/resolv.conf

	echo "WARNING: You are running your container in chroot mode, which gives it unrestricted access to the host system."
	echo "Please don't use chroot mode in production. It's an ugly hack that is slow, insecure, and sometimes breaks."
	set +e
	sudo chroot . /bin/busybox sh -l

	sleep 2
	echo "WARNING: If an error occurs while unmounting the chroot, reboot ASAP to avoid data loss!"
	sudo umount -R dev
	sudo umount -R sys
	sudo umount -R proc
	sudo umount -R tmp
	sudo umount -R run
	sudo umount -R mnt
	sudo umount etc/resolv.conf
	set -e
}

# Run a sandboxed container according to it's OCI configuration.
run_container () {
	cd "$CONTAINER_DIR/$CONTAINER_NAME"
	sudo runc run "$CONTAINER_NAME-$(date +%s)"
}

# Delete a container.
del_container () {
	echo "Deleting container..."
	sudo rm -r "$CONTAINER_DIR/$CONTAINER_NAME"
}

# Empty the shared cache.
clean_cache () {
	echo "Emptying cache..."
	sudo rm -r "$CACHE_DIR"
	mkdir "$CACHE_DIR"
}

# List cache sizes.
list_cache () {
	if [ ! -z "$(ls -A -- "$CACHE_DIR")" ]; then
		echo "Cache sizes:"
		cd "$CACHE_DIR"
		sudo du -shx *
	fi
}

# List container sizes.
list_containers () {
	if [ ! -z "$(ls -A -- "$CONTAINER_DIR")" ]; then
		echo "Configured containers:"
		cd "$CONTAINER_DIR"
		for CONTAINER_FOLDER in *; do
			printf "$(cat "$CONTAINER_FOLDER/.version")	"
			sudo du -shx "$CONTAINER_FOLDER"
		done
	fi
}

# Check the container name passed to the script.
check_container_name () {
	if [ -z "$CONTAINER_NAME" ]; then
		echo "You must specify a valid container."
		list_containers
		exit
	fi
	if [ ! -d "$CONTAINER_DIR/$CONTAINER_NAME" ] && [ "$COMMAND" != "add" ]; then
		echo "Unable to find container!"
		exit
	fi
}

set +u
export COMMAND="$1"
export CONTAINER_NAME="$2"
set -u

case "$COMMAND" in
	"add")
		check_container_name
		get_apk
		get_container_settings
		init_container
		configure_container;;
	"update")
		check_container_name
		get_apk
		get_update_settings
		update_container;;
	"edit")
		check_container_name
		edit_container;;
	"chroot")
		check_container_name
		chroot_container;;
	"run")
		check_container_name
		run_container;;
	"list")
		list_cache
		list_containers;;
	"clean")
		clean_cache;;
	"del")
		check_container_name
		del_container;;
	"bequiet")
		;; # Useful for making scripts based on KatContainer.
	"help")
		echo "help - Shows this menu"
		echo "add [name] - Creates a container."
		echo "del [name] - Deletes a container."
		echo "update [name] - Updates a container's installed packages."
		echo "edit [name] - Edits a container's OCI configuration."
		echo "run [name] - Runs a container based on it's OCI configuration."
		echo "chroot [name] - Runs a container with unrestricted access to the host."
		echo "list - Lists the sizes of containers and the script's caches."
		echo "clean - Empties the script's caches.";;
	*)
		echo "Please specify a valid command."
		echo "For a list of this script's commands, pass the \"help\" command to it.";;
esac
