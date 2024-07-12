#!/bin/bash

# 监控的错误信息
ERROR_STRING_1="cosmos/cosmos-sdk@v0.50.3/baseapp/baseapp.go:991"
ERROR_STRING_2="Failed to Init VRF"

# 监控间隔时间
INTERVALS_TIME=30
# 定时重启stationd时间，这里是指循环次数，10次就是30*10=300秒
RESTART_INTERVALS_TIME=20
# 日志文件
LOG_FILE="$HOME/airchainLogfile.log"
# 日志文件最大10 MB
LOG_FILE_MAX=10485760  

echo "开始监控 stationd 日志..."

# 实时输出日志到指定文件，并且在后台运行
journalctl -u stationd -f -o cat > "$LOG_FILE" &

# 循环检查日志文件中是否包含错误字符串
for_count=0
while true; do
  # 定时重启stationd，并回退3次
  if [ $for_count -ge $RESTART_INTERVALS_TIME ]; then
    echo "定时重启并回退 stationd 服务..."
    systemctl stop stationd
    $HOME/tracks/build/tracks rollback
    $HOME/tracks/build/tracks rollback
    $HOME/tracks/build/tracks rollback
    systemctl restart stationd
    for_count=0
  fi

  # 仅读取日志文件的最新3行来检测第一个错误字符串
  TAIL_LINES_3=$(tail -n 3 "$LOG_FILE")
  if echo "$TAIL_LINES_3" | grep -q "$ERROR_STRING_1"; then
    echo "检测到错误信息 '$ERROR_STRING_1'，重启 stationd 服务..."
    systemctl stop stationd
    $HOME/tracks/build/tracks rollback
    $HOME/tracks/build/tracks rollback
    $HOME/tracks/build/tracks rollback
    systemctl restart stationd
    for_count=0
  fi

  # 仅读取日志文件的最新100行来检测第二个错误字符串
  TAIL_LINES_100=$(tail -n 100 "$LOG_FILE")
  if echo "$TAIL_LINES_100" | grep -q "$ERROR_STRING_2"; then
    echo "检测到错误信息 '$ERROR_STRING_2'，重启 stationd 服务..."
    systemctl stop stationd
    $HOME/tracks/build/tracks rollback
    $HOME/tracks/build/tracks rollback
    $HOME/tracks/build/tracks rollback
    systemctl restart stationd
    for_count=0
  fi

  # 清空LOG_FILE
  file_size=$(stat -c %s "$LOG_FILE")
  if [ "$file_size" -gt "$LOG_FILE_MAX" ]; then
    echo > "$LOG_FILE"
  fi

  sleep $INTERVALS_TIME
  ((for_count++))
done
