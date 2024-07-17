#!/bin/bash

# 错误信息（需获取最新30行日志进行判断）
ERROR_STRING_MORE=(
  "cosmos/cosmos-sdk@v0.50.3/baseapp/baseapp.go:991"
  )
# 错误信息（需获取最新3行日志进行判断）
ERROR_STRING_LESS=(
  "Failed to Init VRF"
  "Failed to Transact Verify pod"
  "insufficient fees"
  )

# 监控间隔时间
INTERVALS_TIME=30
# 定时重启stationd时间，这里是指循环次数，10次就是30*20=600秒
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
  # 定时重启stationd，并回退1次
  if [ $for_count -ge $RESTART_INTERVALS_TIME ]; then
    echo "定时重启并回退 stationd 服务..."
    systemctl stop stationd
    $HOME/tracks/build/tracks rollback
    systemctl restart stationd
    for_count=0
  fi

  # 需获取最新30行日志进行判断
  TAIL_LINES=$(tail -n 30 "$LOG_FILE")
  for ERROR_STRING in "${ERROR_STRING_MORE[@]}"; do
    if echo "$TAIL_LINES" | grep -q "$ERROR_STRING"; then
      echo "检测到错误信息 '$ERROR_STRING'，重启 stationd 服务..."
      systemctl stop stationd
      $HOME/tracks/build/tracks rollback
      $HOME/tracks/build/tracks rollback
      $HOME/tracks/build/tracks rollback
      systemctl restart stationd
      for_count=0
    fi
  done

  # 需获取最新3行日志进行判断
  TAIL_LINES=$(tail -n 30 "$LOG_FILE")
  for ERROR_STRING in "${ERROR_STRING_LESS[@]}"; do
    if echo "$TAIL_LINES" | grep -q "$ERROR_STRING"; then
      echo "检测到错误信息 '$ERROR_STRING'，重启 stationd 服务..."
      systemctl stop stationd
      $HOME/tracks/build/tracks rollback
      systemctl restart stationd
      for_count=0
    fi
  done

  # 清空LOG_FILE
  file_size=$(stat -c %s "$LOG_FILE")
  if [ "$file_size" -gt "$LOG_FILE_MAX" ]; then
    echo > "$LOG_FILE"
  fi

  sleep $INTERVALS_TIME
  ((for_count++))
done
