// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.9;

import "./@openzeppelin/contracts/security/Pausable.sol";
import "./@openzeppelin/contracts/access/Ownable.sol";
import "./@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

interface Token {
    function transferFrom(address sender,address recipient,uint256 amount) external returns (bool);
}

interface iCollection {
    function mintNFT(address _to,uint256 _tokenId,string calldata _tokenURI) external;
    function tokensOfOwner(address _owner) external view returns (uint256[] memory);
}

contract Opener is Pausable, Ownable {
    Token private _lepaToken;
    address private _feeAddress;
    uint256 public collCount;
    event OpenMagicBox(address indexed to, uint256 amount);
    event NewCollectionAdded(string name, iCollection addr);
    event FeeAddressChanged(address indexed to);

    struct OFCollection {
        iCollection cAddr;
        string name;
        uint256 maxCount;
        uint256 currCount;
    }

    mapping(uint256 => OFCollection) public ofc;
    mapping(uint256 => bool) usedNonces;

    constructor(Token tokenAddress, address feeAddress) {
        require(
            address(tokenAddress) != address(0),
            "tokenAddress cannot be address 0"
        );
        require(feeAddress != address(0), "feeAddress cannot be address 0");
        _lepaToken = tokenAddress;
        _feeAddress = feeAddress;
    }

    function setFeeAddress(address feeAddress) external onlyOwner {
        _feeAddress = feeAddress;
        emit FeeAddressChanged(feeAddress);
    }

    function setOFC(
        uint256 _colNum,
        iCollection _colAddr,
        string calldata _name,
        uint256 _cnt
    ) external onlyOwner {
        ofc[_colNum].cAddr = _colAddr;
        ofc[_colNum].name = _name;
        ofc[_colNum].maxCount = _cnt;
        collCount++;
        emit NewCollectionAdded(_name, _colAddr);
    }

    function toEthSignedMessageHash(bytes32 hash) public pure returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function verify(address _signer,
        address _to,
        uint256[] calldata _type,
        uint256[] calldata _ids,
        string[] calldata _uris,
        uint256 _lepa,
        uint256 _nonce,
        bytes calldata signature
    ) public view returns (bool) {
        
        bytes32 ethMessageHash = toEthSignedMessageHash(keccak256(abi.encode(_to, _type, _ids, _uris, _lepa, _nonce)));
        return SignatureChecker.isValidSignatureNow(_signer,ethMessageHash,signature);
    }

    function openMagicBox(
        address _to,
        uint256[] calldata _type,
        uint256[] calldata _ids,
        string[] calldata _uris,
        uint256 _lepa,
        uint256 _nonce,
        bytes calldata signature
    ) external whenNotPaused {
        require(_type.length == _ids.length, "invalid arguments");
        require(!usedNonces[_nonce], "already used");
        require(
            verify(owner(), _to, _type, _ids, _uris, _lepa, _nonce, signature),
            "invalid request"
        );

        usedNonces[_nonce] = true;

        if (_lepa > 0)
            require(_lepaToken.transferFrom(_msgSender(), _feeAddress, _lepa),"Token transfer failed!");

        for (uint256 i = 0; i < _type.length; i++) {
            require(ofc[_type[i]].currCount < ofc[_type[i]].maxCount,"limit reached");
            ofc[_type[i]].cAddr.mintNFT(_to, _ids[i], _uris[i]);
            ofc[_type[i]].currCount++;
        }

        emit OpenMagicBox(_to, _ids.length);
    }

    function getTokensOfOwner(uint256 bcindex, address _user) external view returns (uint256[] memory)
    {
        require(bcindex < collCount, "invalid index");
        return ofc[bcindex].cAddr.tokensOfOwner(_user);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
