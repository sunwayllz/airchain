from web3 import Web3
from eth_account import Account
import json
from concurrent.futures import ProcessPoolExecutor
import random

# 批量生成eth钱包配置
eth_account_file_name = "./airchainSendAccount.json"
eth_account_max = 1000
ethAccountList = [] # [{"address":"", "key":""}, {"address":"", "key":""}]

# 转币配置
# 自定义的 RPC URL
rpc_url = "http://127.0.0.1:8545"
# 自定义的链 ID
chain_id = 1234
# 主钱包地址（发水给各个钱包）
faucet_account_address = ""
# 主钱包key
faucet_account_key = "_FaucetAccountKey_"

# 进程池配置
process_pool_max_worker = 2

# 使用私钥获取钱包地址
def getAccountAddress():
    global faucet_account_address
    faucet_account_address = Account.from_key(faucet_account_key).address

# 读取json文件中的钱包地址
def loadEthAccount(filePath):
    global ethAccountList
    try:
        with open(filePath, 'r') as file:
            ethAccountList = json.load(file)
    except Exception as e:
        print(str(e))

# 保存钱包地址到json文件中
def saveEthAccount(filePath):
    with open(filePath, 'w') as file:
        json.dump(ethAccountList, file)

# 生成eth钱包方法
def generateEthAccount():
    Account.enable_unaudited_hdwallet_features()
    account, mnemonic = Account.create_with_mnemonic()
    return account.address, account.key.hex()[2:]

# 获取钱包余额
def getEthAccountBalance(address):
    web3 = Web3(Web3.HTTPProvider(rpc_url))
    return web3.eth.get_balance(address)

# 转币
# sAddress 发送者钱包地址
# sKey 发送者钱包的私钥
# rAddress 接收者钱包地址
# amount 转账金额，例子：1000000000000000000，1个币
def ethTransaction(sAddress, sKey, rAddress, amount):
    web3 = Web3(Web3.HTTPProvider(rpc_url))
    # 构建交易对象
    t = {
        "to": rAddress,
        "value": amount,
        "gas": 21000,  # 设置默认的 gas 数量
        "gasPrice": web3.to_wei(50, "gwei"),  # 设置默认的 gas 价格
        "nonce": web3.eth.get_transaction_count(sAddress),
        "chainId": chain_id,
    }
    try:
        # 签名交易
        signed_txn = web3.eth.account.sign_transaction(t, sKey)
        # 发送交易
        tx_hash = web3.eth.send_raw_transaction(signed_txn.rawTransaction)
        # 等待交易确认
        tx_receipt = web3.eth.wait_for_transaction_receipt(tx_hash)
        # 返回交易结果
        return tx_receipt.status, tx_receipt.transactionHash.hex()
    except Exception as e:
        print(str(e))
        return -1, ""

# worker
# 随机选择一个钱包进行转币
def worker(index, minBalance, minAmount, maxAmount):
    print("worker-"+str(index)+"启动")
    while True:
        try:
            ethAccount = random.choice(ethAccountList)
            amount = random.randint(minAmount, maxAmount)
            # 判断当前获取到钱包余额，不够就从主钱包转过去
            if getEthAccountBalance(ethAccount["address"]) < amount:
                ethTransaction(faucet_account_address, faucet_account_key, ethAccount["address"], minBalance)
            # 随机选择一个接受钱包进行转币
            rAddress = random.choice(ethAccountList)["address"]
            print(ethAccount["address"]+" -> "+rAddress+" [worker-"+str(index)+"]")
            ethTransaction(ethAccount["address"], ethAccount["key"], rAddress, amount)
        except Exception as e:
            print(str(e))

def main():
    # 使用私钥获取钱包地址
    getAccountAddress()
    # 读取json文件中钱包信息
    loadEthAccount(eth_account_file_name)
    # 如钱包数量不满足要求，就创建钱包
    if len(ethAccountList) < eth_account_max:
        print("生成钱包，需生成 "+str(eth_account_max-len(ethAccountList))+" 个")
        while len(ethAccountList) < eth_account_max:
            address, key = generateEthAccount()
            ethAccountList.append({"address": address, "key": key})
        # 保存钱包信息到文件
        saveEthAccount(eth_account_file_name)
        print("生成完成")
    print("一共 "+str(len(ethAccountList))+" 个钱包")
    
    # 判断每个钱包中的余额，不够就从主钱包转过去
    # 最少余额
    minBalance = 20 * 1000000000000000000
    index = 0
    for ethAccount in ethAccountList:
        index = index+1
        balance = getEthAccountBalance(ethAccount["address"])
        if balance < minBalance:
            print("【"+str(index)+"】向 "+ethAccount["address"]+" 转 "+str(minBalance-balance))
            ethTransaction(faucet_account_address, faucet_account_key, ethAccount["address"], minBalance-balance)
    
    # 使用进程池
    with ProcessPoolExecutor(max_workers=process_pool_max_worker) as executor:
        for i in range(1, process_pool_max_worker+1):
            executor.submit(worker, i, minBalance, 0.1 * 1000000000000000000, 1000000000000000000)


if __name__ == "__main__":
    main()
