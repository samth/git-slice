# For slicing git repositories

### Sample use:

```
$ mkdir /path/to/tmp-data
$ cd my-repo
# Providing an absolute /path/to/tmp-data below is important.
$ racket -l git-slice subdir /path/to/tmp-data
$ racket -l git-slice/filter /path/to/tmp-data
$ racket -l git-slice/chop /path/to/tmp-data
```

The `git-slice/filter` step will take a long time. It can be sped up
by using a ramdisk, see [here][1] for Linux instructions to set one up,
and then add `-d /tmp/ramdisk/scratch` as an additional argument.

 [1]: http://www.linuxscrew.com/2010/03/24/fastest-way-to-create-ramdisk-in-ubuntulinux/
