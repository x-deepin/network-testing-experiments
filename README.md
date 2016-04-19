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

需指定iperf3服务端地址, 要检测网卡类型(有线/无线)以及检测时长(单位:秒),

例如下面的命令会检测本地所有的无线网卡是否正常工作(需提前连接到正确热
点), 每个网卡会检测一个小时, 并会分别生成gnuplot绘制的网络时速曲线图
```
./check-network.sh -s 192.168.1.1 -c wireless -t 3600
```

查看完整说明:
```
./check-network.sh -h
```

## License

GNU General Public License Version 3
