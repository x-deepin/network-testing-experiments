**描述**: 网络自动化测试工具集合

## 依赖

**prepare-network**
- awk
- sed
- network-manager

**check-network**
- awk
- bc
- gnuplot
- ip
- iperf3
- lshw
- sed
- ethtool
- wireless-tools

## 使用说明

### prepare-network

用于为网络测试准备环境, 例如连接有线, 无线及清空网络配置文件, 例如:
```
$ ./prepare-network.sh connect-wireless myssid mypassword
$ ./prepare-network.sh clear-wireless-connections
```

查看完整说明:
```
prepare-network.sh <command> [args...] [-h]
Options:
    -h, --help, show this message
Command list:
    clear-connections
    clear-wired-connections
    clear-wireless-connections
    connect-wired: TODO
    connect-wireless: <SSID> <password>
```

### check-network

需指定iperf3服务端地址, 要检测的网卡类型(wired/wireless)以及检测时长(单位:秒),

例如下面的命令会检测本地所有的无线网卡是否正常工作(需提前连接到正确热
点), 每个网卡会检测一个小时, 并会分别生成gnuplot绘制的网络时速曲线图,
如果期间出现网络断开以及网速不正常的情况, 脚本能够识别并返回错误
```
$ ./check-network.sh -s 192.168.1.1 -c wireless -t 3600
```

也可以单独指定要测试的网卡设备
```
$ ./check-network.sh -s 192.168.1.1 -i "pci@8086:4237" -t 3600
```

由于iperf3不支持多线程, 如果要支持多客户端, 需要运行多个iperf3服务
器进程, 客户端无需做配置, check-network.sh会自动选择可用的端口进行连接:
```
$ for p in {5201..5220}; do iperf3 -s -p ${p} & done
```

查看完整说明:
```
$ ./check-network.sh -h
check-network.sh [-s <server>] [-c <category> | -i <deviceid>] [-n <devicenum>] [-t <time>] [-h]
Options:
    -s, --server, iperf3 server
    -c, --category, only run test for the target network device category,
                    could be wired or wireless (default: <not specified>)
    -i, --deviceid, only run test for the target network device which own
                    the same ID, the ID format looks like pci@8086:4237 or usb@148f:5370
    -n, --devicenum, the prefer network device number in local to test,
                    -1 means do not check the device number at all (default: -1)
    -t, --time, the seconds to run for iperf3 client (default: 3600)
    -h, --help, show this message
```

## License

GNU General Public License Version 3
