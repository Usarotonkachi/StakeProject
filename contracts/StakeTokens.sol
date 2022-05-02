// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract StakeTokens is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using Counters for Counters.Counter;

    IERC20 goldz = IERC20(0x7bE647634A942e73F8492d15Ae492D867Ce5245c);

    struct StakedContract {
        bool active;
        IERC721 instance;
    }

    mapping(address => mapping(address => EnumerableSet.UintSet)) addressToStakedTokensSet; // хранит id токенов данного контракта у данного юзера (contract address => owner => tokenId)
    mapping(address => mapping(uint256 => address)) contractTokenIdToOwner; // Хранит владельцев данного id токена данного контракта (contract address => tokenId => owner)
    mapping(address => mapping(uint256 => uint256)) contractTokenIdToStakedTimestamp; // хранит таймстампы всех токенов (contract address => tokenId => timestamp)
    mapping(address => StakedContract) public contracts; // хранит инфу о адресах токенов erc721 для стейкинга (active or not active)

    mapping(address => address[]) ownerContractAddresses; // хранит все контракты erc721 данного юзера (owner => contractAddresses)

    string private secretKey = "i like solidity";

    function setSecretKey(string memory _newKey) external onlyOwner {
        secretKey = _newKey;
    }

    EnumerableSet.AddressSet activeContracts;
    address _signerAddress;

    event Stake(uint256 tokenId, address contractAddress, address owner);
    event Unstake(uint256 tokenId, address contractAddress, address owner);
    event Withdraw(address owner, uint256 amount);

    modifier ifContractExists(address contractAddress) {
        require(
            activeContracts.contains(contractAddress),
            "contract does not exists"
        );
        _;
    }

    IERC20 private immutable _token;

    uint256 private baseRate = 10;
    address private signer = owner();

    function setBaseRate(uint256 newBaseRate) external onlyOwner {
        baseRate = newBaseRate;
    }

    constructor(address token_) {
        require(token_ != address(0x0));
        _token = IERC20(token_);
    }

    function countRewards(address owner) internal view returns (uint256) {
        uint256 reward = 0;
        for (uint256 i = 0; i < ownerContractAddresses[owner].length; i++) {
            uint256[] memory tokens = EnumerableSet.values(
                addressToStakedTokensSet[ownerContractAddresses[owner][i]][
                    owner
                ]
            );
            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 timestamp = contractTokenIdToStakedTimestamp[
                    ownerContractAddresses[owner][i]
                ][tokens[j]];
                uint256 timeCount = block.timestamp - timestamp;

                uint256 week = timeCount / 60; // для проверки берем минуту и секунду
                uint256 day = timeCount;

                //uint week = timeCount / 60 / 60 / 24 / 7;
                //uint day = timeCount / 60 / 60 / 24;
                if (week == 0 || week == 1) {
                    reward += baseRate * day;
                } else {
                    if (week / 2 > 5) {
                        reward += baseRate * 5 * day;
                    } else {
                        reward += baseRate * (week / 2) * day;
                    }
                }
            }
        }
        return reward;
    }

    function availableReward(address user) external view returns (uint256) {
        return countRewards(user);
    }

    modifier isSigner() {
        require(msg.sender == signer, "It's not a signer");
        _;
    }

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    function stake(address contractAddress, uint256[] memory tokenIds)
        external
    {
        StakedContract storage _contract = contracts[contractAddress];
        require(_contract.active, "token contract is not active");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // Assign token to his owner - Запоминает владельца токена
            contractTokenIdToOwner[contractAddress][tokenId] = msg.sender;

            // Transfer token to this smart contract - трансфер токена на этот контракт
            _contract.instance.safeTransferFrom(
                msg.sender,
                address(this),
                tokenId
            );

            // Add this token to user staked tokens - добавить этот токен в список стейкнутых токенов юзера
            addressToStakedTokensSet[contractAddress][msg.sender].add(tokenId);

            // Добавляет адрес контракта в список всех контрактов данного юзера
            ownerContractAddresses[msg.sender].push(contractAddress);

            // Save stake timestamp - сохранить таймстамп
            contractTokenIdToStakedTimestamp[contractAddress][tokenId] = block
                .timestamp;

            emit Stake(tokenId, contractAddress, msg.sender);
        }
    }

    function unstake(address contractAddress, uint256[] memory tokenIds)
        external
        ifContractExists(contractAddress)
    {
        StakedContract storage _contract = contracts[contractAddress];

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(
                addressToStakedTokensSet[contractAddress][msg.sender].contains(
                    tokenId
                ),
                "token is not staked"
            );

            // Remove owner of this token - удалить владельца токена этого адреса
            delete contractTokenIdToOwner[contractAddress][tokenId];

            // Transfer token to his owner - трансфер владельцу
            _contract.instance.safeTransferFrom(
                address(this),
                msg.sender,
                tokenId
            );

            // Remove this token from user staked tokens - удаляет токен из пула стейкнутых токенов данного контракта у данного юзера
            addressToStakedTokensSet[contractAddress][msg.sender].remove(
                tokenId
            );

            // Remove stake timestamp - удаляет таймстамп
            delete contractTokenIdToStakedTimestamp[contractAddress][tokenId];

            emit Unstake(tokenId, contractAddress, msg.sender);
        }
    }

    function stakedTokensOfOwner(address contractAddress, address owner)
        external
        view
        ifContractExists(contractAddress)
        returns (uint256[] memory)
    {
        EnumerableSet.UintSet storage userTokens = addressToStakedTokensSet[
            contractAddress
        ][owner];

        uint256[] memory tokenIds = new uint256[](userTokens.length());

        for (uint256 i = 0; i < userTokens.length(); i++) {
            tokenIds[i] = userTokens.at(i);
        }

        return tokenIds;
    }

    function stakedTokenTimestamp(address contractAddress, uint256 tokenId)
        external
        view
        ifContractExists(contractAddress)
        returns (uint256)
    {
        return contractTokenIdToStakedTimestamp[contractAddress][tokenId];
    }

    //Добавление адреса
    function addContract(address contractAddress) public onlyOwner {
        contracts[contractAddress].active = true;
        contracts[contractAddress].instance = IERC721(contractAddress);
        activeContracts.add(contractAddress);
    }

    // изменяет состояние контракта (активирует или деактивирует)
    function updateContract(address contractAddress, bool active)
        public
        onlyOwner
        ifContractExists(contractAddress)
    {
        require(
            activeContracts.contains(contractAddress),
            "contract not added"
        );
        contracts[contractAddress].active = active;
    }

    // Проверка
    function verify(bytes memory _sig) public view returns (bool) {
        bytes32 messageHash = getMessageHash(secretKey);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

        return recover(ethSignedMessageHash, _sig) == signer;
    }

    function getMessageHash(string memory _message)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_message));
    }

    function getEthSignedMessageHash(bytes32 _messageHash)
        public
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }

    function recover(bytes32 _ethSignedMessageHash, bytes memory _sig)
        public
        pure
        returns (address)
    {
        (bytes32 r, bytes32 s, uint8 v) = _split(_sig);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function _split(bytes memory _sig)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(_sig.length == 65, "invalid signature name");

        assembly {
            r := mload(add(_sig, 32))
            s := mload(add(_sig, 64))
            v := byte(0, mload(add(_sig, 96)))
        }
    }

    //, bytes memory _sig
    function withdraw(address user) external onlyOwner {
        // decode and require
        //require(verify(_sig), "It's not a signer");

        uint256 reward = countRewards(user);
        _token.transfer(user, reward);
    }

    function onERC721Received(
        address operator,
        address,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        require(
            operator == address(this),
            "token must be staked over stake method"
        );
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function nowTimeStamp() public view returns (uint256) {
        return block.timestamp;
    }
}
