# Stacker - manage device-mapper stacks for testing

Stacker provides a command line tool and a scripting interface for defining and
interacting with stacks of device-mapper devices.

The project is hosted at:

  * https://github.com/bmr-cymru/stacker

For the latest version, to contribute, and for further information, please
visit the project pages.

To clone the current development branch, run:

```
$ git clone https://github.com/bmr-cymru/stacker.git
```

## Getting started

To install stacker to the system where the git repository has been cloned, run
`make install`:

```
# make install
mkdir -p /usr/lib/stacker
mkdir -p /usr/lib/stacker/layers
mkdir -p /usr/bin
mkdir -p /etc/stacker
mkdir -p /var/lib/stacker/stacks
mkdir -p /usr/share/man/man8
install -m755 stkr /usr/bin
install -m755 stacker-functions.sh /usr/lib/stacker
install -m755 stacklog.sh /usr/lib/stacker
install -m755 stacklib.sh /usr/lib/stacker
install -m755 etc/stkr.conf /etc/stacker
for l in _layer_init.sh _part_disk_init.sh linear loop nvme sd thin thin-pool vd; do install -m755 layers/$l /usr/lib/stacker/layers/; done
```

## Configuring stacker

Stacker installs a simple configuration file to `/etc/stacker/stkr.conf`. The
values defined in this file control the logging configuration for the `stkr`
command:

```
STKR_LOGFILE="/var/log/stacker.log"
STKR_LOGFILE_LEVEL="6"
# STKR_SYSLOG="user"
# STKR_SYSLOG_LEVEL="6"
```

Stacker logs by default to a log file in `/var` but can optionally log to the
system logging facility (`syslog` or `journald`).

## The stkr command

```
# stkr --help
Usage: stkr <command> [OPTION] <stack> [STACK_OPTIONS]
Version: 001

Execute and interact with stacker scripts for building test device stacks.
```

Executing a stacker script creates a persistent configuration describing the
stack which can then be started, stopped, inspected or used as a target for
IO.

## Stack script

Stack script is a shell script dialect for defining stacks of devices. Stacks
may incorporate physical devices from the system as well as arbitrary
combinations of device-mapper target layers.

Devices and layers in a stacker stack are defined by calling shell functions
from the stacklib library. The arguments to the functions control device naming
and properties and allow stacks to be repeatably defined, started, stopped and
modified.

To begin a new, named stack definition the function `stk_new()` is called with
the name of the newly defined stack:

```
stk_new mystack
```

This creates a new and empty stack configuration (normally in a subdirectory
of `/var/lib/stacker/stacks`). Subsequent calls to stacklib functions populate
the stack with the device hierarchy that will be activated when it is started.

To end the current stack definition (and either begin another stack, or end the
current script), the function `stk_end` is called with no arguments.

```
stk_end
```

It is possible to break a stacker script up into multiple parts that execute
separately (for example, to define a base stack and then subsequently modify
it by inserting or altering layers).

When used in this way the function `stk_load()` is used to retrieve the
previously stored stack configuration:

```
stk_load mystack
# modify mystack device definitions
stk_end
```

## Layers and layer templates

Stacks of devices configured with stacker consist of layers of device
definitions, starting with system devices (physical or virtual storage
provided by the system environment), and proceeding through various types of
device-mapper layer providing specific IO mapping capabilities.

Each layer consists of a layer template (a script that can configure devices
of that layer type), and configuration data set up by calling the corresponding
stacklib function to instantiate a layer.

At the top of each stack exist the *leaf devices* that are used for IO.

The stacklib functions that configure layers accept arguments that configure
the specific type of IO mapping offered by that layer. Layer functions can
accept optional arguments and provide default values for some arguments. An
optional argument that appears at the end of a function's argument list can
be simply ommitted to accept the default values. For arguments that are
followed by further mandatory parameters the empty string (`""`) should be
used to request default values.

## Defining system devices used for tests

System devices (for e.g. Linux loop back devices, SCSI, or Virtio disks) must
be declared in a script before being used to define further layers. The
following functions declare and configure a named device of the corresponding
type:

```
loop_dev <name> <size>[KMGPT]
sd_dev <name> <min_size>[KMGPT]
vd_dev <name> <min_size>[KMGPT]
nvme_dev <name> <min_size>[KMGPT]
```

For example, to create a Linux loop back device of size 1GiB and bound to
device loop0:

  `loop_dev loop0 1G`

### Partitioning system devices

Stacker supports an optional GPT or MBR partition label on all partitionable
device types (loop, SCSI, VirtIO, NVME). To define partitions use the
`--mbr` or `--gpt` option and provide a list of partition sizes. The final
partition can be made to consume the remaining available space by using the
special value `-` in place of the size.

To define a SCSI disk sda of at least 10GiB with three partitions using the
GPT disk label format:

  `sd_dev sda 10G --gpt 500M 4500M 5G`

To define a partitioned loop device of 1GiB, with two MBR primary partitions,
one of 100MiB and the other taking up the remaining space:

  `loop_dev loop0 1G --mbp 100M -`

### MBR partitioning limits
Stacker currently supports a maximum of four (primary) partitions on devices
using the MBR partition table format. This limit may be removed in a future
version.

## Defining device-mapper layers in stacker stacks

In addition to system provided block devices stacker allows device layers to
be created using a range of device-mapper targets. See the [device-mapper
documentation][1] in the Linux kernel sources for a complete description of the
available target types and the IO mapping options that they provide.


The currently supported device-mapper targets in stacker are:

* [linear][2]
* [thin-pool][3]
* [thin][3]
* [cache][4]
* [writecache][5]

Additional target support is planned for future updates.

### Stacklib functions for device-mapper targets

Functions are provided to configure each supported device-mapper target. All
device-mapper device functions accept the device name as the first argument
and subsequent arguments (specific to each target type) that specify the
device configuration.

Once a device has been defined in the current stack by calling its definition
function the name given as the first parameter can be used in subsequent calls
to specify devices to use for further layers in the stack.

#### linear

The linear target is configured by calling the `linear_dev` function to create
a new linear device. The devices that make up the linear device are specified as
a device name, with an optional range of sectors.

```
linear_dev <name> <dev_range1> [<dev_range_2> ... <dev_range_N>]
```

If a range is not specified for a given device name the linear device will span
the entire device address space.

Ranges may be given in sectors, or in human readable units by using a unit
suffix. Units are power-of-two based.

  `<device_name>[:<offset>+<len>[KMGPT]]`

For example:

  * `sda`

Maps the entire span of SCSI disk device `sda`.

  * `loop0:0+512M`

Maps the first 512MiB of Linux loop back device `loop0`.

  * `vdc1:1G+1G`

Maps the second 1GiB of VirtIO disk device `vdc1`.

#### thin-pool

The thin-pool target provides an implementation of thin provisioned space
management. See the [Linux kernel documentation][3] for a full description of
the target's features and capabilities.

To create a new thin pool configuration in the current stack call the
`thin_pool()` stacklib function:

```
thin_pool <name> <metadata_dev> <data_dev> <data_block_size> <low_water_mark> [feature_args*]
```

The resulting thin pool will be the same size as the given data device.

For example, to create a new `thin_pool` using two loop back devices, a block
size of 128, a low water mark of 64 and using the optional feature argument
`ignore_discards`:

```
thin_pool pool0 loop0 loop1 128 64 ignore_discards
```

Feature arguments are defined by the thin-pool target and are discussed in
detail in the [documentation][3]. The currently supported set of feateure
arguments is:

* `skip_block_zeroing`
* `ignore_discard`
* `no_discard_passdown`
* `read_only`
* `error_if_no_space`

#### thin

The thin target gives access to the thin provisioning facility provided by the
thin-pool. Each thin device is a separate block device address space that
consumes space from the pool as writes trigger block allocation.

To define a new thin device the `thin_dev()` function is used:

```
thin_dev <name> <pool_dev> <dev_id> <dev_size>[KMGPT]
```

The `pool_dev` argument is the name of a previously defined thin-pool. The
`dev_id` is a unique, non-negative integer identifier that identifies this
volume in the containing thin-pool. The `dev_size` specifies the apparent
size of the device.

For example, to create a new thin volume in pool `pool0`, with a device
identifier of `0` and an apparent size of 10GiB:

```
thin_dev thin0 pool0 0 10G
```

#### cache

The dm-cache target aims to improve the performance of a block device (e.g.
a spindle) by dynamically migrating some of its data to a faster, smaller
device (e.g. an SSD). Refer to the [target documentation][4] for a complete
description of the target's capabilities and features.

To define a dm-cache device the `cache_dev` stacklib function is used:

```
cache_dev <name> <metadata_dev> <cache_dev> <origin_dev> <block_size> <mode> <policy>
```

| Argument | Description |
| -------- | ----------- |
| name     | The name of the cache device |
| `metadata_dev` | A small device used to store cache metadata |
| `cache_dev` | The small, fast device used to store cached content |
| `origin_dev` | The large device whose content is to be cached |
| `block_size` | The size of cache data blocks in sectors, or `""` for default |
| `mode` | The cache mode, `writeback`, `writethrough`, or `passthrough`, or `""` for default |
| `policy` | The cache policy to use. See the [cache documentation][4] for current status |

For example to create a new cache device that caches data from SCSI disk `sda1`
using NVME devices `nvme0n1p1` (metadata) and `nvme0n1p2` (data) and using the
default block size, mode and cache policy:

```
cache_dev cache0 nvme0n1p1 nvme0n1p2 sda1
```

#### writecache

The dm-writecache target improves performance by caching writes directed to a
device using an SSD or persistent memory device. Refer to the kernel
[writecache documentation][4] for a complete description of the target's
capabilities and features.

To define a dm-writecache device the `writecache_dev` stacklib function is used:

```
writecache_dev <name> <type> <cache_dev> <origin_dev> <block_size> [<feature_arg>*]
```

| Argument | Description |
| -------- | ----------- |
| name     | The name of the writecache device |
| `cache_dev` | The small, fast device used to store cached writes |
| `origin_dev` | The large device whose content is to be cached |
| `block_size` | The size of cache data blocks in bytes, or `""` for default |
| `feature_arg` | Optional feature arguments that further control the cache behaviour |

The feature arguments are a list of space separated optional arguments that
further customise cache behaviour. Some feature arguments are boolean, enabling
or disabling a particular feature, while others accept a value. Features that
accept an argument are written as `feature_arg=value`, for example
`start_sector=64`.

The current set of writecache feature arguments is:

| Argument | Value | Description |
| -------- | ----- | ----------- |
| `start_sector=` | sectors | The data offset from the start of the cache device |
| `high_watermark=` | #blocks | Start writeback when the number of used blocks reaches this value |
| `low_watermark=` | #blocks | Stop writeback when the number of used blocks drops below this value |
| `writeback_jobs=` | #jobs | Limit the number of in-flight jobs when performing writeback |
| `autocommit_blocks=` | #blocks | when the application writes this amount of blocks without issuing the FLUSH request, the blocks are automatically committed |
| `autocommit_time=` | #msecs | The data is automatically committed if this time passes with no FLUSH request |
| `fua` | None | Use the FUA flag when writing back data to persistent memory |
| `nofua` | None | Do not set the FUA flag when writing back data to persistent memory |
| `cleaner` | None | See the [writecache documentation][4] |
| `max_age=` | #msecs | Maximum age of a block in milliseconds |
| `metadata_only` | None | Only metadata is promoted to the cache |
| `pause_writeback=` | #msecs | Pause writeback if write IO was redirected to the volume in the last #msecs |

For example to create a new writcache device that caches data written to SCSI
disk `sda1` using NVME device `nvme0n1p1` and with a 4KiB block size, zero
offset, and a high watermark value of 60:

```
writecache_dev cache0 s nvme0n1p1 sda1 4096 start_sector=0 high_watermark=60
```

NOTE: currently only the SSD caching type (`s`) is supported. Persistent memory
backed caches using type `p` will be supported in a future update.

 [1]: https://github.com/torvalds/linux/tree/master/Documentation/admin-guide/device-mapper
 [2]: https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/device-mapper/linear.rst
 [3]: https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/device-mapper/thin-provisioning.rst
 [4]: https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/device-mapper/cache.rst
 [5]: https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/device-mapper/writecache.rst

