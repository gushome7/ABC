// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0 <0.9.0;
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/*
 * @title: Signature Checker
 * @author: Gustavo Hernandez Baratta for The Pan de Azucar Bay Company LLC
 * @email: ghernandez@pandeazucarbay.com
 */

library Signature { 

    function check(bytes memory _rawMsg, bytes32 _msgHash, bytes memory _signature, address _validSigner) public pure {
        bytes32 __msgHash=ECDSA.toEthSignedMessageHash(_rawMsg);
        require(_msgHash==__msgHash, "Invalid Signature: malformed hash");
        require(ECDSA.recover(_msgHash,_signature)==_validSigner,"Invalid Signature: invalid signed");        
    }

}