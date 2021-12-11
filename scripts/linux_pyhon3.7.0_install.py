#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys

if os.getuid()==0:
    pass
else:
    print "当前用户不是root用户,请登录root用户执行脚本"
    sys.exit(1)

py_v='3.7.0'

def os_cmd(cmd,message):
    res = os.system(cmd)
    if res != 0:
        print(message)
        sys.exit(1)

def py_get():
    url = 'https://www.python.org/ftp/python/'+py_v+'/Python-'+py_v+'.tgz'
    cmd = 'wget '+url
    message='下载源码包失败，请检查网络'
    os_cmd(cmd, message)

cmd='python'+py_v[0]+' -V'
res = os.system(cmd)
if res == 0:
    sys.exit(1)

mesg='是否安装python版本'+py_v+'？(y/n)'
version = raw_input(mesg)
py_file ='Python-'+py_v+'.tgz'
if version == 'y' or version == 'Y':
    if not os.path.exists(py_file):
        py_get()
else:
    print '退出程序'
    sys.exit(1)

package_name = 'Python-'+py_v+''
cmd='rm -fr '+package_name+''
if os.path.exists("package_name"):
    os.system(cmd)

cmd = 'tar xf '+package_name+'.tgz'
message='解压源码包失败，请重新运行这个脚本'
os_cmd(cmd,message)

cmd='yum -y install bzip2 bzip2-devel openssl openssl-devel openssl-static openssl-devel libffi libffi-devel gdbm tk tk-devel gdbm-devel sqlite sqlite-devel xz lzma xz-devel ncurses ncurses-devel zlib* gcc readline readline-devel'
message='安装依赖失败，请检查依赖！'
os_cmd(cmd,message)

cmd = 'cd '+package_name+' && ./configure --prefix=/usr/local/python --with-ssl --enable-optimizations --enable-shared CFLAGS=-fPIC && make && make install'
message='编译python源码失败，请检查是否缺少依赖库'
os_cmd(cmd,message)

if not os.path.exists('/usr/bin/python3'):
    file='libpython'+py_v[0:3]+'m.so.1.0'
    cmd ='ln -s /usr/local/python/bin/python3 /usr/bin/python3 && ln -s /usr/local/python/bin/pip3 /usr/bin/pip3 && ln -s /usr/local/python/lib/'+file+' /usr/lib64/'
    message='软连接失败，请查看！'
    os_cmd(cmd,message)