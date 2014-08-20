# For slicing git repositories

### Sample use:

```
$ mkdir tmp-data
$ cd my-repo
$ racket -l git-slice subdir tmp-data
$ git --filter-branch --prune-empty --index-filter 'racket -l git-slice/prune /path/to/tmp-data'
```
