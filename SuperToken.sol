// SPDX-License-Identifier: MIT 
pragma solidity >=0.8.7 <0.9.0;

interface IMigrationContract {
    function migrate(address addr, uint256 nas) external returns (bool success);
}

contract SafeMath {
    function safeAdd(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 z = x + y;
        require(z >= x && z >= y, "SafeMath: addition overflow");
        return z;
    }

    function safeSubtract(uint256 x, uint256 y) internal pure returns (uint256) {
        require(x >= y, "SafeMath: subtraction overflow");
        uint256 z = x - y;
        return z;
    }

    function safeMult(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x == 0) {
            return 0;
        }
        uint256 z = x * y;
        require(z / x == y, "SafeMath: multiplication overflow");
        return z;
    }
}

/*  ERC 20 token */
abstract contract Token {
    uint256 public totalSupply;
    function balanceOf(address _owner) public view virtual returns (uint256 balance);
    function transfer(address _to, uint256 _value) public virtual returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) public virtual returns (bool success);
    function approve(address _spender, uint256 _value) public virtual returns (bool success);
    function allowance(address _owner, address _spender) public view virtual returns (uint256 remaining);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract StandardToken is Token {
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;

    function transfer(address _to, uint256 _value) public override returns (bool success) {
        if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            emit Transfer(msg.sender, _to, _value);
            return true;
        } else {
            return false;
        }
    }

    function transferFrom(address _from, address _to, uint256 _value) public override returns (bool success) {
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            emit Transfer(_from, _to, _value);
            return true;
        } else {
            return false;
        }
    }

    function balanceOf(address _owner) public view override returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) public override returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view override returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }
}

// 发行一种代币
contract SuperToken is StandardToken, SafeMath {
    string public constant name = "Super";
    string public constant symbol = "SCoin";
    uint256 public constant decimals = 18;
    string public version = "1.0";

    address public ethFundDeposit;              // ETH存放地址
    address public newContractAddr;             // token更新地址

    bool public isFunding;                      // 控制是否募资状态
    uint256 public fundingStartBlock;
    uint256 public fundingStopBlock;

    uint256 public currentSupply;               // 正在售卖中的tokens数量
    uint256 public tokenRaised = 0;             // 总的售卖数量token
    uint256 public tokenMigrated = 0;           // 总的已经交易的 token
    uint256 public tokenExchangeRate = 625;     // 625 BILIBILI 兑换 1 ETH

    event AllocateToken(address indexed _to, uint256 _value);       // 分配的私有交易token;
    event IssueToken(address indexed _to, uint256 _value);          // 公开发行售卖的token;
    event IncreaseSupply(uint256 _value);
    event DecreaseSupply(uint256 _value);
    event Migrate(address indexed _to, uint256 _value);

    function formatDecimals(uint256 _value) internal pure returns (uint256) {
        return _value * 10 ** decimals;
    }

    constructor(address _ethFundDeposit, uint256 _currentSupply) {
        ethFundDeposit = _ethFundDeposit;

        isFunding = false;
        fundingStartBlock = 0;
        fundingStopBlock = 0;

        currentSupply = formatDecimals(_currentSupply);
        totalSupply = formatDecimals(10000000);
        balances[msg.sender] = totalSupply;
        require(currentSupply <= totalSupply, "Current supply exceeds total supply");
    }

    modifier isOwner() {
        require(msg.sender == ethFundDeposit, "Caller is not the owner");
        _;
    }

    //设置token汇率
    function setTokenExchangeRate(uint256 _tokenExchangeRate) external isOwner {
        require(_tokenExchangeRate != 0, "Exchange rate cannot be zero");
        require(_tokenExchangeRate != tokenExchangeRate, "New exchange rate must be different");
        tokenExchangeRate = _tokenExchangeRate;
    }

    //超发token
    function increaseSupply(uint256 _value) external isOwner {
        uint256 value = formatDecimals(_value);
        require(value + currentSupply <= totalSupply, "Increased supply exceeds total supply");
        currentSupply = safeAdd(currentSupply, value);
        emit IncreaseSupply(value);
    }

    //减少token
    function decreaseSupply(uint256 _value) external isOwner {
        uint256 value = formatDecimals(_value);
        require(value + tokenRaised <= currentSupply, "Decreased supply exceeds raised tokens");
        currentSupply = safeSubtract(currentSupply, value);
        emit DecreaseSupply(value);
    }

    //启动募集
    function startFunding(uint256 _fundingStartBlock, uint256 _fundingStopBlock) external isOwner {
        require(!isFunding, "Funding is already active");
        require(_fundingStartBlock < _fundingStopBlock, "Start block must be before stop block");
        require(block.number < _fundingStartBlock, "Start block must be in the future");

        fundingStartBlock = _fundingStartBlock;
        fundingStopBlock = _fundingStopBlock;
        isFunding = true;
    }

    //关闭募集
    function stopFunding() external isOwner {
        require(isFunding, "Funding is not active");
        isFunding = false;
    }

    //切换一个新地址接受token
    function setMigrateContract(address _newContractAddr) external isOwner {
        require(_newContractAddr != newContractAddr, "New contract address must be different");
        newContractAddr = _newContractAddr;
    }

    //修改所有者地址
    function changeOwner(address _newFundDeposit) external isOwner {
        require(_newFundDeposit != address(0), "New owner address cannot be zero");
        ethFundDeposit = _newFundDeposit;
    }

    //转移token到新合约
    function migrate() external {
        require(!isFunding, "Cannot migrate during funding");
        require(newContractAddr != address(0), "New contract address is not set");

        uint256 tokens = balances[msg.sender];
        require(tokens > 0, "No tokens to migrate");

        balances[msg.sender] = 0;
        tokenMigrated = safeAdd(tokenMigrated, tokens);

        IMigrationContract newContract = IMigrationContract(newContractAddr);
        require(newContract.migrate(msg.sender, tokens), "Migration failed");

        emit Migrate(msg.sender, tokens);
    }

    //转账ETH到指定地址
    function transferETH() external isOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH balance to transfer");
        (bool success, ) = ethFundDeposit.call{value: balance}("");
        require(success, "ETH transfer failed");
    }

    //转移token
    function allocateToken(address _addr, uint256 _eth) external isOwner {
        require(_eth != 0, "ETH amount must be greater than zero");
        require(_addr != address(0), "Address must not be zero");

        uint256 tokens = safeMult(formatDecimals(_eth), tokenExchangeRate);
        require(tokens + tokenRaised <= currentSupply, "Exceeds current supply");

        tokenRaised = safeAdd(tokenRaised, tokens);
        balances[_addr] += tokens;

        emit AllocateToken(_addr, tokens);
    }

    //用户转账ETH后，转账token给用户
    receive() external payable {
        require(isFunding, "Funding is not active");
        require(msg.value > 0, "ETH value must be greater than zero");
        require(block.number >= fundingStartBlock, "Funding has not started");
        require(block.number <= fundingStopBlock, "Funding has ended");

        uint256 tokens = safeMult(msg.value, tokenExchangeRate);
        require(tokens + tokenRaised <= currentSupply, "Exceeds current supply");

        tokenRaised = safeAdd(tokenRaised, tokens);
        balances[msg.sender] += tokens;

        emit IssueToken(msg.sender, tokens);
    }
}
