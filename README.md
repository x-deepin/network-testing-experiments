**描述**: 检测网卡驱动是否正常工作

## 依赖

- awk
- bc
- gnuplot
- ip
- iperf3
- lshw
- mktemp
- sed
- /sbin/ethtool
- /sbin/iwconfig

## 使用说明

需指定iperf3服务端地址, 要检测的网卡类型(wired/wireless)以及检测时长(单位:秒),

例如下面的命令会检测本地所有的无线网卡是否正常工作(需提前连接到正确热
点), 每个网卡会检测一个小时, 并会分别生成gnuplot绘制的网络时速曲线图,
如果期间出现网络断开以及网速不正常的情况, 脚本能够识别并返回错误
```
$ ./check-network.sh -s 192.168.1.1 -c wireless -t 3600
```

由于iperf3不支持多线程, 另外如果要支持多客户端, 需要运行多个iperf3服务
器进程, 客户端无需做配置, check-network.sh会自动选择可用的端口进行连接:
``` for i in $(seq 50); do
port=$(expr 5200 + "${i}") iperf3 -s -p ${port} & done
```

查看完整说明:
```
$ ./check-network.sh -h
check-network.sh [-s <server>] [-c <category>] [-t <time>] [-h]
Options:
    -s, --server, iperf3 server
    -c, --category, could be wired or wireless (default: wireless)
    -t, --time, the seconds to run for iperf3 client (default: 3600)
    -h, --help, show this message
```

## License

GNU General Public License Version 3
