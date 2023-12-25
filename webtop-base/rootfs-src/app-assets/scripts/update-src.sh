#!/bin/bash

export LC_ALL=zh_CN.UTF-8

# 检查是否有jq命令
if ! command -v jq &> /dev/null
then
  echo "❌ 请先安装jq命令！参考：https://command-not-found.com/jq"
  exit 1
fi

FILE_INITIALIZED=".mdcx_initialized"

# 应用版本
appVersion=0

# 详细日志
verbose=1

# 默认强制更新
force=1

# 源码存放目录
appPath="/app"

if [[ ! -d "$appPath" ]]; then
   echo "❌ 应用源码不存在！"
  exit 1
fi


while [[ $# -gt 0 ]]
do
  key="$1"
  case $key in
    --restart)
      restart="$2"
      shift
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    --dry)
      dry=1
      shift
      ;;
    --verbose)
      verbose=1
      shift
      ;;
    -h|--help)
      help=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done


if [ -n "$help" ]; then
  echo "脚本功能：更新自部署的应用源码"
  echo ""
  echo "示例-检查并更新:    $0"
  echo ""
  echo "参数说明："
  echo "--restart                 更新后重启容器，默认true。可选参数值: 1, 0; true, false"
  echo "--force                   强制更新。默认情况下当已发布版本较新于本地版本时才会更新。"
  echo "--dry                     只检查，不更新"
  echo "-h, --help                显示帮助信息"
  exit 0
fi

compareVersion () {
  if [[ $1 == $2 ]]
  then
    return 0
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  # fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
  do
    ver1[i]=0
  done
  for ((i=0; i<${#ver1[@]}; i++))
  do
    if [[ -z ${ver2[i]} ]]
    then
      # fill empty fields in ver2 with zeros
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]}))
    then
      return 1
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]}))
    then
      return 2
    fi
  done
  return 0
}

appPath=$(echo "$appPath" | sed 's:/*$::')


if [[ -f "$appPath/setup.py" ]]; then
  # 'CFBundleShortVersionString': "20230201",
  appVersion=$(cat $appPath/setup.py | grep -oi 'CFBundleShortVersionString.: "[a-z0-9]\+' | grep -oi '[a-z0-9]\+$')
  echo "ℹ️ 从 $appPath/setup.py 检测到应用版本为 $appVersion"
else
  echo "⚠️ 应用源码目录下没有setup.py文件！"
  appVersion=0
fi

_url="https://api.github.com/repos/sqzw-x/mdcx/releases/latest"
_content=$(curl -s "$_url")

# TODO github workflow里竟然会有比较大的概率获取失败
if [[ -z "$_content" ]]; then
  echo "❌ 请求 $_url 失败！"
  exit 1
fi

# tag名称，作为版本号
tagName=$(printf '%s' $_content | jq -r ".tag_name")
archiveVersion=$(echo $tagName | sed 's/v//g')

# 源码压缩包(tar格式)链接
archiveUrl=$(printf '%s' $_content | jq -r ".tarball_url")

if [[ -z "$archiveUrl" ]]; then
  echo "❌ 从请求结果获取源码压缩包文件下载链接失败！"
  echo "🔘 请求链接：$_url"
  exit 1
fi

if [[ -n "$verbose" ]]; then
  echo "ℹ️ TAG名称: $tagName"
  echo "🔗 下载链接: $archiveUrl"
fi
echo "ℹ️ 已发布版本: $archiveVersion"


compareVersion $archiveVersion $appVersion
case $? in
  0) op='=';;
  1) op='>';;
  2) op='<';;
esac

shouldUpdate=
if [[ $op == '>' ]]; then
  echo " 已发布的最新版本 较新于 本地版本"
  shouldUpdate=1
fi

if [[ -n "$force" ]]; then
  echo "ℹ️ 强制更新"
  shouldUpdate=1
fi

if [[ -n "$shouldUpdate" ]]; then

  if [[ -n "$dry" ]]; then
    exit 0
  fi

  archivePath="$archiveVersion.tar.gz"

  if [[ -n "$verbose" ]]; then
    curl -o $archivePath $archiveUrl -L
  else
    curl -so $archivePath $archiveUrl -L
  fi

  echo "✅ 下载成功"
  echo "⏳ 开始解压..."

  # 解压新的源码到app目录
  tar -zxvf $archivePath -C $appPath --strip-components 1
  # 删除压缩包
  rm -f $archivePath
  echo "✅ 源码已覆盖到 $appPath"

  echo "ℹ️ 删除标记文件 $appPath/$FILE_INITIALIZED"
  rm -f "$appPath/$FILE_INITIALIZED"

  echo "✅ 源码已更新成功！版本：$archiveVersion"
  
else
  if [[ $op == '<' ]]; then
    echo "ℹ️ 本地版本 较新于 已发布的最新版本"
  else
    echo "ℹ️ 本地版本 已是最新版本"
  fi
fi

echo "ℹ️ 按下任意键关闭窗口。"