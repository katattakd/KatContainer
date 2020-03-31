# KatContainer
A Bash script that allows you to create and manage Alpine-linux based OCI containers.

### Hardware/software support
This script only works on Linux, and will likely require modifications to work on other operating systems. This script will run on the CPU architectures listed below, but keep in mind that you should not move containers or cache folders between hosts with different architectures.

#### Fully supported architectures (works perfectly out of the box)
- x86_64
- aarch64

#### Partially supported architectures (requires some workarounds to get working)
- x86
- armhf
- armv7
- ppc64le
- s390x

### Dependencies
You will need the following dependencies to use the script.
- coreutils, bash, sudo (for running the script)
- curl or apk-tools (for creating containers)
- runc (for running containers)
- jq (for creating or editing containers)

### Usage
You can run the script like so:
```bash katcontainer.sh```
Running the script with the argument "help" specified (```bash katcontainer.sh help```), will show you a listing of the script's commands, and what they do.

#### Where is stuff stored?
By default, containers are stored in ```$PWD/containers```, and the cache is stored in ```$PWD/cache```.

#### Additional configuration
Some additional configuration can be accessed by directly editing the script. Also, container-specific configuration can be modified using the script's "edit" argument.
