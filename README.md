# Stacker - manage device-mapper stacks for testing

Stacker provides a command line tool and a scripting dialect for defining and
interacting with stacks of device-mapper devices.

## The stkr command

  # stkr --help
  Usage: stkr <command> [OPTION] <stack> [STACK_OPTIONS]
  Version: 001

  Execute and interact with stacker scripts for building test device stacks.


## Stack script

Stack script is a shell script dialect for defining stacks of devices. Stacks
may incorporate physical devices from the system as well as arbitrary
combinations of device-mapper target layers.

Devices and layers in a stacker stack are defined by calling shell functions
from the stacklib library. The arguments to the functions control device naming
and characteristics and allow stacks to be repeatably defined, started, stopped
and modified.

## Defining system devices used for tests

System devices (for e.g. Linux loop back devices, SCSI, or Virtio disks) must
be declared in a script before being used to define further layers. The
following functions declare and configure a named device of the corresponding
type:

  loop_dev <name> <size>
  sd_dev <name> <min_size>
  vd_dev <name> <min_size>
  nvme_dev <name> <min_size>

For example, to create a Linux loop back device of size 1GiB and bound to
device loop0:

  loop_dev loop0 1G

To define a SCSI disk sda of at least 10GiB with three partitions:

  sd_dev sda 10G --gpt 500M 4500M 5G


