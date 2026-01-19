sudo mount -t tmpfs -o size=10G,mpol=bind:8 tmpfs /mnt/tmp
dd if=/dev/zero of=/mnt/tmp/chunk_size bs=1M count=8192


sudo daxctl reconfigure-device --mode=system-ram -f dax0.0

ndctl create-namespace --force --mode=devdax --reconfig=namespace0.0