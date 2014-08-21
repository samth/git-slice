# For slicing git repositories

### Sample use:

```
$ mkdir tmp-data
$ cd my-repo
$ racket -l git-slice subdir tmp-data
# Providing an absolute path below is important.
$ git --filter-branch --prune-empty --index-filter 'racket -l git-slice/prune /path/to/tmp-data'
```

The `filter-branch` command will take a long time. It can be sped up
by using a ramdisk, see [here][1] for Linux instructions to set one up,
and then add `-d /tmp/ramdisk/scratch` as an additional argument.

 [1]: http://www.linuxscrew.com/2010/03/24/fastest-way-to-create-ramdisk-in-ubuntulinux/
