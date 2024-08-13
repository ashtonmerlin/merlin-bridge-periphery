// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CustomizedBridge {
    using SafeERC20 for IERC20;
    OfficialBridge immutable public officialBridge;
    address immutable public feeReceiver;
    address immutable public bridgeToken;
    address immutable public signer;
    mapping (uint256 => bool) public nonceUsed;

    event BridgeOut(address bridgeUser, address bridgeToken, uint256 bridgeAmount, uint256 bridgeFee);

    error InvalidNonce();
    error InvalidSignature();
    error InvalidBridgeFee(uint256 provided, uint256 required);
    error SendBridgeFeeFailed();

    constructor(address _officialBridge, address _tokenAddress, address _signer) {
        officialBridge = OfficialBridge(_officialBridge);
        feeReceiver = officialBridge.feeAddress();
        bridgeToken = _tokenAddress;
        signer = _signer;
    }

    function bridgeOut(uint256 nonce, uint256 bridgeAmount, string memory destBtcAddr, bool shouldPay, bytes calldata signature) external payable {
        if (nonceUsed[nonce]) revert InvalidNonce();

        address bridgeUser = msg.sender;
        if (!isValidSignature(nonce, bridgeUser, shouldPay, signature)) revert InvalidSignature();

        IERC20(bridgeToken).safeTransferFrom(bridgeUser, address(this), bridgeAmount);

        uint256 bridgeFee = 0;
        if (shouldPay) {
            bridgeFee = officialBridge.getBridgeFee(bridgeUser, bridgeToken);
            if (msg.value != bridgeFee) revert InvalidBridgeFee(msg.value, bridgeFee);
            (bool success,) = feeReceiver.call{value: bridgeFee}("");
            if (!success) {
                revert SendBridgeFeeFailed();
            }
        }
        officialBridge.burnERC20Token{value: 0}(bridgeToken, bridgeAmount, destBtcAddr);
        
        emit BridgeOut(bridgeUser, bridgeToken, bridgeAmount, bridgeFee);
    }

    function isValidSignature(uint256 nonce, address bridgeUser, bool shouldPay, bytes calldata _signature) internal view returns(bool) {
        bytes memory data = abi.encode(nonce, bridgeUser, shouldPay);
        bytes32 hash = keccak256(data);
        address recoveredAddress = ECDSA.recover(hash, _signature);
        return (recoveredAddress == signer);
    }
}

interface OfficialBridge {
    function feeAddress() external view returns (address);
    function getBridgeFee(address bridgeUser, address bridgeToken) external view returns(uint256);
    function burnERC20Token(address bridgeToken, uint256 bridgeAmount, string memory destBtcAddr) external payable;
}
