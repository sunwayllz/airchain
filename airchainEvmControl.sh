#!/bin/bash

# 安装所需的软件包
function install_dependencies() {
    dependencies=("build-essential" "git" "make" "jq" "curl" "clang" "pkg-config" "libssl-dev" "wget" "python3" "pip")
    for dep in "${dependencies[@]}"; do
        if dpkg-query -W "$dep" >/dev/null 2>&1; then
            echo "$dep 已安装，跳过安装步骤。"
        else
            echo "安装 $dep..."
            apt update
            apt install -y "$dep"
        fi
    done

    # 安装go
    if command -v go >/dev/null 2>&1; then
        echo "go 已安装，跳过安装步骤。"
    else
        echo "下载并安装 Go..."
        wget --no-cache -N -c https://golang.org/dl/go1.22.4.linux-amd64.tar.gz -O - | tar -xz -C /usr/local
        echo 'export GOROOT=/usr/local/go' >> ~/.bashrc
        echo 'export GOPATH=$HOME/go' >> ~/.bashrc
        echo 'export GO111MODULE=on' >> ~/.bashrc
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
        source ~/.bashrc
    fi
}

# 安装节点，领水前
function install_node_1() {
    # 下载文件
    git clone https://github.com/airchains-network/evm-station.git
    git clone https://github.com/airchains-network/tracks.git
    
    ################ 编译部署Evm-Station #####################

    cd $HOME/evm-station
    go mod tidy

    RANDOM_STR=$(tr -dc 'a-z' < /dev/urandom | head -c 8)
    CHAIN_ID="${RANDOM_STR}evm"
    MONIKER="${RANDOM_STR}testnet"

    sed -i "s/stationevm_1234-1/${CHAIN_ID}_1234-1/g" ./scripts/local-setup.sh
    sed -i "s/localtestnet/${MONIKER}/g" ./scripts/local-setup.sh

    # 编译Evm-Station
    # 会输出地址和助记词，建议保存输出的信息
    /bin/bash ./scripts/local-setup.sh

    # 获取钱包私钥，需保存
    /bin/bash ./scripts/local-keys.sh

    read -p "请保存相关信息，按 Enter 键继续..."

    sed -i.bak 's@address = "127.0.0.1:8545"@address = "0.0.0.0:8545"@' ~/.evmosd/config/app.toml

    cat > /etc/systemd/system/evmosd.service << EOF
[Unit]
Description=evmosd node
After=network-online.target
[Service]
User=root
WorkingDirectory=/root/.evmosd
ExecStart=$HOME/evm-station/build/station-evm start --metrics "" --log_level "info" --json-rpc.api eth,txpool,personal,net,debug,web3 --chain-id "$CHAIN_ID"
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable evmosd
    systemctl restart evmosd

    ################ 使用eigenlayer作为DA #####################

    cd $HOME
    wget --no-cache -N https://github.com/airchains-network/tracks/releases/download/v0.0.3/eigenlayer
    chmod +x eigenlayer
    mv eigenlayer /usr/local/bin/eigenlayer

    KEY_FILE="$HOME/.eigenlayer/operator_keys/wallet.ecdsa.key.json"
    if [ -f "$KEY_FILE" ]; then
        echo "文件 $KEY_FILE 已经存在，删除文件"
        rm -f "$KEY_FILE"
        echo "123" | eigenlayer operator keys create --key-type ecdsa --insecure wallet
    else
        echo "文件 $KEY_FILE 不存在，执行创建密钥操作"
        echo "123" | eigenlayer operator keys create --key-type ecdsa --insecure wallet
    fi

    read -p "请保存相关信息，按 Enter 键继续..."

    ################ 初始化Tracks服务 #####################

    rm -rf ~/.tracks
    cd $HOME/tracks
    # go mod tidy
    # 编辑tracks，可执行程序路径：$HOME/tracks/build/tracks
    make build

    read -p "请输入Public Key hex: " dakey
    # read -p "请输入节点名: " moniker
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    $HOME/tracks/build/tracks init --daRpc "disperser-holesky.eigenda.xyz" --daKey "$dakey" --daType "eigen" --moniker "$MONIKER" --stationRpc "http://$LOCAL_IP:8545" --stationAPI "http://$LOCAL_IP:8545" --stationType "evm"

    ################ 生成airchains钱包 #####################

    echo "你需要创建新地址吗？（Y/N/S）"
    echo "Y: 创建新地址"
    echo "N: 导入地址"
    echo "S: 跳过"
    read -r response
    response=$(echo "$response" | tr '[:lower:]' '[:upper:]')

    if [[ "$response" == "Y" ]]; then
        echo "正在创建新地址..."
        $HOME/tracks/build/tracks keys junction --accountName wallet --accountPath "$HOME/.tracks/junction-accounts/keys"
    elif [[ "$response" == "N" ]]; then
        echo "请输入你的助记词："
        read -r mnemonic
        echo "正在导入地址..."
        $HOME/tracks/build/tracks keys import --accountName wallet --accountPath "$HOME/.tracks/junction-accounts/keys" --mnemonic "$mnemonic"
    elif [[ "$response" == "S" ]]; then
        echo "已跳过创建或导入地址的步骤。"
    else
        echo "无效的输入，请输入“Y”、“N”或“S”。"
        exit 1
    fi

    cd $HOME

    echo "请保存airchains钱包地址和助记词，并领水后继续安装"
    exit 0
}

# 安装节点，领水后
function install_node_2() {
    read -p "是否已经领水完毕要继续执行？(yes/no): " choice
    if [[ "$choice" != "yes" ]]; then
        echo "请确认领水成功后继续安装，脚本已终止。"
        exit 0
    fi

    ################ 运行Prover组件 #####################

    cd $HOME/tracks
    $HOME/tracks/build/tracks prover v1EVM

    ################ 创建station #####################

    CONFIG_PATH="$HOME/.tracks/config/sequencer.toml"
    WALLET_PATH="$HOME/.tracks/junction-accounts/keys/wallet.wallet.json"

    if [ -f "$WALLET_PATH" ]; then
        echo "钱包文件存在，从钱包文件中提取地址..."
        AIR_ADDRESS=$(jq -r '.address' "$WALLET_PATH")
    else
        echo "钱包文件不存在，请输入钱包地址："
        read -r AIR_ADDRESS
        echo "你输入的钱包地址是: $AIR_ADDRESS"
    fi

    NODE_ID=$(grep 'node_id =' $CONFIG_PATH | awk -F'"' '{print $2}')
    # LOCAL_IP=$(hostname -I | awk '{print $1}')
    LOCAL_IP=$(curl -s4 ifconfig.me/ip)

    read -p "请输入RPC地址（默认：https://airchains-rpc.kubenode.xyz/）: " jsonRPC
    if [ -z "$jsonRPC" ]; then
        jsonRPC="https://airchains-rpc.kubenode.xyz/"
    fi

    create_station_cmd="$HOME/tracks/build/tracks create-station --accountName wallet --accountPath $HOME/.tracks/junction-accounts/keys --jsonRPC \"$jsonRPC/\" --info \"EVM Track\" --tracks \"$AIR_ADDRESS\" --bootstrapNode \"/ip4/$LOCAL_IP/tcp/2300/p2p/$NODE_ID\""

    echo "Running command:"
    echo "$create_station_cmd"
    eval "$create_station_cmd"

    read -p "请检查创建station是否成功，按 Enter 键继续..."

    ################ Tracks加入守护进程并启动 #####################

    cat /etc/systemd/system/stationd.service > /dev/null << EOF
[Unit]
Description=station track service
After=network-online.target
[Service]
User=$USER
WorkingDirectory=$HOME/tracks/
ExecStart=$HOME/tracks/build/tracks start
Restart=always
RestartSec=10
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable stationd
    systemctl restart stationd

    cd $HOME
}

# 运行脚本
function start_script() {
    restartSendAccount_python
    restartMonitor_shell
    # 监控并清空日志文件
    # 停止正在运行
    ps -ef | grep "clear_log.sh" | grep -v "grep" | awk -F' ' '{print $2}'| xargs kill
cat > clear_log.sh << 'EOF'
#!/bin/bash
LOG_FILES=("airchainSendAccount.py.out" "airchainMonitor.sh.out")
# 日志文件最大1MB
LOG_FILE_MAX=1048576
while true; do
    for LOG_FILE in "${LOG_FILES[@]}"; do
        if [ -e $LOG_FILE ]; then
            file_size=$(stat -c %s "$LOG_FILE")
            if [ "$file_size" -gt "$LOG_FILE_MAX" ]; then
              echo > "$LOG_FILE"
              echo "清空 $LOG_FILE"
            fi
        fi
    done
    sleep 60
done
EOF
    chmod +x clear_log.sh
    nohup ./clear_log.sh &
    sleep 1
    rm -rf clear_log.sh
}

# 重启python的转帐脚本，刷tx
function restartSendAccount_python() {
    py_file="airchainSendAccount.py"
    py_out_file="airchainSendAccount.py.out"
    # 停止正在运行
    ps -ef | grep "$py_file" | grep -v "grep" | awk -F' ' '{print $2}'| xargs kill
    # 清空日志
    echo > $py_out_file
    # 下载python脚本
    if [ ! -e $py_file ]; then
        wget --no-cache -N -O $py_file https://raw.githubusercontent.com/sunwayllz/airchain/main/airchainSendAccount.py
        pip install web3
        pip install eth_account
        # 获取evm私钥
        cd $HOME/evm-station/
        evm_pkey=$(/bin/bash ./scripts/local-keys.sh)
        cd $HOME
        # 替换脚本中的默认私钥
        sed -i "s/_FaucetAccountKey_/$evm_pkey/g" $py_file
    fi
    # 运行python的转帐脚本
    nohup python3 -u $py_file > $py_out_file 2>&1 &
    echo "已运行python转帐脚本"
}

# 重启定时重启回滚脚本
function restartMonitor_shell() {
    shell_file="airchainMonitor.sh"
    shell_out_file="airchainMonitor.sh.out"
    # 停止正在运行
    ps -ef | grep "$shell_file" | grep -v "grep" | awk -F' ' '{print $2}'| xargs kill
    ps -ef | grep "journalctl -u stationd" | grep -v "grep" | awk -F' ' '{print $2}'| xargs kill
    # 清空日志
    echo > $shell_out_file
    # 下载脚本
    if [ ! -e $shell_file ]; then
        wget --no-cache -N -O $shell_file https://raw.githubusercontent.com/sunwayllz/airchain/main/airchainMonitor.sh
        chmod +x $shell_file
    fi
    # 运行定时重启回滚脚本
    nohup ./$shell_file > $shell_out_file 2>&1 &
    echo "已运行定时重启回滚脚本"
}

# 查看脚本日志
function script_log() {
    py_out_file="airchainSendAccount.py.out"
    shell_out_file="airchainMonitor.sh.out"
    tail -f $py_out_file $shell_out_file
}

# 重启节点
function restart() {
    systemctl restart evmosd
    systemctl restart stationd
}

# 查看 evmos 状态
function evmos_log() {
    journalctl -u evmosd -f -o cat
}

# 查看 stationd 状态
function stationd_log() {
    journalctl -u stationd -f -o cat
}

# 查看evm私钥、air地址及助记词
function private_key() {
    echo "【evm私钥】"
    cd $HOME/evm-station/
    /bin/bash ./scripts/local-keys.sh
    cd $HOME
    echo "【air地址】"
    cat $HOME/.tracks/junction-accounts/keys/wallet.wallet.json | jq -r '.address'
    echo "【air助记词】"
    cat $HOME/.tracks/junction-accounts/keys/wallet.wallet.json | jq -r '.mnemonic'
}

# 查看项目积分
function check_points() {
    address=$(cat $HOME/.tracks/junction-accounts/keys/wallet.wallet.json | jq -r '.address')
    # 获取积分
    response=$(curl -s -X POST 'https://points.airchains.io/api/rewards-table' \
      -H 'content-type: application/json' \
      --data-raw "{\"address\":\"$address\"}")

    # 提取 total_stations 和 total_points
    total_stations=$(echo "$response" | jq -r '.data.total_stations')
    total_points=$(echo "$response" | jq -r '.data.total_points')

    # 提取所有stationId
    station_ids=$(echo "$response" | jq -r '.data.stations[].station_id')

    # 提起所有station的积分状态
    eligibles=$(echo "$response" | jq -r '.data.stations[].eligible')

    # 获取每个station的Pod
    latestPods=()
    for station_id in $station_ids; do
      response=$(curl -s -X POST 'https://testnet.airchains.io/api/stations/single-station/details' \
      -H 'content-type: application/json' \
      --data-raw "{\"stationID\":\"$station_id\"}")
      latestPod=$(echo "$response" | jq -r '.data.latestPod')
      latestPods+=("station_id: $station_id , latest_pod: $latestPod")
    done

    # 读取上次的结果
    fileName="airchainCheckPoints.history"
    history=$(cat $fileName)

    # 保存本次的结果
    echo "获取时间: $(date +"%Y-%m-%d %H:%M:%S")" > $fileName
    echo "total_stations: $total_stations , total_points: $total_points" >> $fileName
    for latestPod in "${latestPods[@]}"; do
      echo $latestPod >> $fileName
    done
    for eligible in $eligibles; do
      echo "eligible: $eligible" >> $fileName
    done

    # 输出结果
    printf "%s\n" "$history"
    echo "======================================================================="
    cat $fileName
}

# 更换RPC
function change_rpc() {
    CONFIG_PATH="$HOME/.tracks/config/sequencer.toml"
    old_rpc_url=$(grep 'JunctionRPC' "$CONFIG_PATH" | sed -n 's/.*JunctionRPC = "\([^"]*\)".*/\1/p')
    echo "旧的RPC地址: $old_rpc_url"
    read -p "请输入新的RPC地址: " new_rpc_url
    if [ ! -z "$new_rpc_url" ]; then
        sed -i "s|JunctionRPC = \"$old_rpc_url\"|JunctionRPC = \"$new_rpc_url\"|" $CONFIG_PATH
        echo "已替换，正在重启节点"
        restart
    fi
}

# 彻底删除节点
function delete_node() {
    cd $HOME

    systemctl stop evmosd
    systemctl stop stationd
    systemctl disable evmosd
    systemctl disable stationd
    rm -rf /etc/systemd/system/evmosd.service
    rm -rf /etc/systemd/system/stationd.service

    rm -rf evm-station
    rm -rf .evmosd
    rm -rf tracks
    rm -rf .tracks
    rm -rf /usr/local/bin/eigenlayer
    rm -rf .eigenlayer

    ps -ef | grep "clear_log.sh" | grep -v "grep" | awk -F' ' '{print $2}'| xargs kill
    rm -rf clear_log.sh
    ps -ef | grep "airchainSendAccount.py" | grep -v "grep" | awk -F' ' '{print $2}'| xargs kill
    rm -rf airchainSendAccount.py
    rm -rf airchainSendAccount.py.out
    rm -rf airchainSendAccount.json
    ps -ef | grep "airchainMonitor.sh" | grep -v "grep" | awk -F' ' '{print $2}'| xargs kill
    ps -ef | grep "journalctl -u stationd" | grep -v "grep" | awk -F' ' '{print $2}'| xargs kill
    rm -rf airchainMonitor.sh
    rm -rf airchainMonitor.sh.out
    rm -rf airchainLogfile.log
    rm -rf airchainCheckPoints.history

    journalctl --vacuum-time=1s
}

function main_menu() {
    while true; do
        clear
        echo "退出脚本，请按键盘ctrl c退出即可"
        echo "请选择要执行的操作:"
        echo "========== 安装节点 =========="
        echo "1. 步骤一"
        echo "2. 步骤二"
        echo ""
        echo "========== 辅佐脚本 =========="
        echo "3. 运行（重启）辅佐脚本"
        echo "4. 查看辅佐脚本日志"
        echo ""
        echo "========== 节点状态 =========="
        echo "5. 重启节点"
        echo "6. 查看 evmos 状态"
        echo "7. 查看 stationd 状态"
        echo ""
        echo "========== 其他功能 =========="
        echo "8. 查看evm私钥、air地址及助记词"
        echo "9. 查看项目积分"
        echo "10. 更换RPC"
        echo ""
        echo "========== 删除节点 =========="
        echo "100. 彻底删除节点"

        read -p "请输入选项（1-9）: " OPTION

        case $OPTION in
            1) install_node_1 ;;
            2) install_node_2 ;;
            3) start_script ;;
            4) script_log ;;
            5) restart ;;
            6) evmos_log ;;
            7) stationd_log ;;
            8) private_key ;;
            9) check_points ;;
            10) change_rpc ;;
            100) delete_node ;;
            *) echo "无效选项。" ;;
        esac
        echo "按任意键返回主菜单..."
        read -n 1
    done
}

install_dependencies
main_menu
