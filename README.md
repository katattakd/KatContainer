# KatContainer
A simple bash script that allows you to create and manage Alpine-linux based OCI containers.

### Hardware/software support
You will need a x86_64 CPU to run this script. Support for other architectures, such as ARM, will be added soon. The script only works on Linux, and will likely not be ported to other operating systems.

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
