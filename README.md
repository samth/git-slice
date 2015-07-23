# For slicing git repositories

### Warning!

This performs permanent modification to your git repository! Be careful.


### Installation

```
raco pkg install git-slice
```


### Sample use:

```
$ cd my-repo
$ racket -l git-slice subdir
```

This destructively updates `my-repo` to only include `subdir`.

It performs multiple steps, which can be split out as follows:

```
$ mkdir /path/to/tmp-data
$ cd my-repo
$ racket -l git-slice/compute subdir /path/to/tmp-data
$ racket -l git-slice/filter /path/to/tmp-data
$ racket -l git-slice/chop /path/to/tmp-data
```

The `git-slice/filter` and `git-slice/chop` steps can take a long
time. They can be sped up by using a ramdisk: see [here][1] for Linux
instructions to set one up, and then add `-d /tmp/ramdisk/scratch` as
an additional argument. This is also supported for the `git-slice`
command itself. The provided path must not yet exist.

`git-slice` can be provided a second argument for a temporary
directory to use to store metadata files. If not provided, a temporary
directory is created. This directory is _not_ removed after slicing.

The `--dry-run` command can be provided to any command to see what it
would do without doing any permanent damage.

 [1]: http://www.linuxscrew.com/2010/03/24/fastest-way-to-create-ramdisk-in-ubuntulinux/
