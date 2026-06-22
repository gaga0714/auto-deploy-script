# 使用说明

## 安装到 /usr/local/bin

```sh
sudo bash scripts/install.sh
```

装完直接全局调用 `setup-site`(不用再 `bash scripts/setup-site.sh`)。

卸载:

```sh
sudo bash scripts/install.sh --uninstall
```

## 用法

可自定义端口，默认现有最大加一

```sh
sudo setup-site xxx（文件夹名称） --port xxx
```

自定义 root

```sh
sudo setup-site menu-play --root /var/www/menu-play
```

> 未安装时也可直接跑源码: `sudo bash scripts/setup-site.sh xxx`
