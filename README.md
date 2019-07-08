# KatContainer
A simple bash script that allows you to create and manage Alpine-linux based OCI containers.

### Hardware/software support
This script only works on Linux, and will likely not be ported to other operating systems.
For the best experience, you should run this on an x86_64 system. If you are running this on a different architecuture, you will have to do the workarounds listed below.

#### Workarounds
If you are using a CPU architecture that isn't x86_64, or if you are running on a distro with a very minimal kernel configuration (like Alpine Linux), the built-in crun container runtime WILL not work properly. You will have to set the script's USE_NATIVE_RUNC option to "true", and install runc manually onto the container host, in order to run containers.

If you intend to create containers that use a CPU architecture other than x86_64, you will have to edit the script's ARCH configuration option, and set it to your desired architecture.

#### Supported architectures
- x86_64 (highly recommended)
- x86
- aarch64 (recommended for ARM devices)
- armhf
- armv7
- ppc64le
- s390x

### Dependencies
You will need the commands included in coreutils, along with the following:
- bash (for running the script)
- jq (for parsing OCI container configuration)
- wget (for downloading dependencies the script requires)
- sudo (for running some tasks as the root user)
- tar (for extracting dependencies)

### Usage
You can run the script like so:
```bash katcontainer.sh```
Running the script with the argument "help" specified (```bash katcontainer.sh help```), will show you a listing of the script's commands, and what they do.

#### Where is stuff stored?
By default, containers are stored in ```$PWD/.containers```, and the cache (used for keeping copies of packages, and a copy of the container runtime) is stored in ```$PWD/.cache```.

#### Additional configuration
Some additional configuration (such as changing the default options) can be accessed by directly editing the script. Also, container-specific configuration can be modified using the script's "edit" argument.
