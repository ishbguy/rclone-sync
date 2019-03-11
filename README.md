# [rclone-sync](https://github.com/ishbguy/rclone-sync)

[![License][licsvg]][lic]

[licsvg]: https://img.shields.io/badge/license-MIT-green.svg
[lic]: https://github.com/ishbguy/rclone-sync/blob/master/LICENSE

A bidirectional sync tool using rclone and implemented in shell. The sync
algorithms reference from
[cjnaz/rclonesync-V2](https://github.com/cjnaz/rclonesync-V2). which is a good
choice in Python.

## Table of Contents

+ [:art: Features](#art-features)
+ [:straight_ruler: Prerequisite](#straight_ruler-prerequisite)
+ [:rocket: Installation](#rocket-installation)
+ [:memo: Configuration](#memo-configuration)
+ [:notebook: Usage](#notebook-usage)
+ [:hibiscus: Contributing](#hibiscus-contributing)
+ [:boy: Authors](#boy-authors)
+ [:scroll: License](#scroll-license)

## :art: Features

+ bidirectional sync

## :straight_ruler: Prerequisite

> + `bash`
> + `rclone`

## :rocket: Installation

```
$ git clone https://github.com/ishbguy/rclone-sync
$ cd rclone-sync
$ export PATH="$PATH:$(pwd)/bin"
```
or
```
$ curl -fLo /path/to/rclone-sync.sh \
        https://raw.githubusercontent.com/ishbguy/rclone-sync/master/bin/rclone-sync.sh
$ export PATH="$PATH:/path/to"
```

## :memo: Configuration

There is no configuration for rclone-sync, but you need to configure rclone if
you want to use your cloud service. For detail rclone configuration, you can
type `man rclone` in a shell or go to [rclone homepage](https://rclone.org/).

## :notebook: Usage

Simply run:
```
rclone-sync.sh path1 path2
```
Just looking what will happen (dry run):
```
rclone-sync.sh -d path1 path2
```
For help:
```
rclone-sync.sh -h
```

## :hibiscus: Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## :boy: Authors

+ [ishbguy](https://github.com/ishbguy)

## :scroll: License

Released under the terms of [MIT License](https://opensource.org/licenses/MIT).
