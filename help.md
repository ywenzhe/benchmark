sudo mount -t tmpfs -o size=10G,mpol=bind:8 tmpfs /mnt/tmp
dd if=/dev/zero of=/mnt/tmp/chunk_size bs=1M count=8192