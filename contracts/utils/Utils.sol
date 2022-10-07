// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0 <0.9.0;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/Strings.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
/*
 * @title: Misc Utils
 * @author: Gustavo Hernandez Baratta for The Pan de Azucar Bay Company LLC
 * @dev: provide usefull stuffs
 * email: ghernandez@pandeazucarbay.com
 */

library Utils { 

  using Strings for uint256;  
  
  /* @dev: return array elements imploded in a string */
  function implodeIds(uint256[] memory _ids) public pure returns (string memory) {
    bytes memory output;

    for (uint256 i = 0; i < _ids.length; i++) {
      output = abi.encodePacked(output, Strings.toString(_ids[i]));
    }
    return string(output);      
  }


  function SignatureCheck(bytes memory _rawMsg, bytes32 _msgHash, bytes memory _signature, address _validSigner) public pure {
    bytes32 __msgHash=ECDSA.toEthSignedMessageHash(_rawMsg);
    require(_msgHash==__msgHash, "Invalid Signature: malformed hash");
    require(ECDSA.recover(_msgHash,_signature)==_validSigner,"Invalid Signature: invalid signed");        
  }

/*
 * @title: Random Number generator
 * @author: Gustavo Hernandez Baratta for The Pan de Azucar Bay Company LLC
 * @dev Provides a simple way to get a random value between 0 and the defined maximum. 
 * @notice It should be studied in which cases it can be used since it can be hacked, as explained in the 
 * ollowing article: 
 * https://coredevs.medium.com/safe-practice-of-tron-solidity-smart-contracts-implement-random-numbers-in-the-contracts-9c7ad8f6f9b0
 * email: ghernandez@pandeazucarbay.com
 */
  function RandomGenerate(uint256 _minRange, uint256 _maxRange, uint256 _seed) public view returns(uint256) {
    require(_maxRange >0, 'Value must be greather than zero');
    require(_maxRange > _minRange, 'Max value must be greather than min value');
    uint256 seed = uint256(keccak256(abi.encodePacked(
        block.timestamp + block.difficulty +
        ((uint256(keccak256(abi.encodePacked(block.coinbase)))) / (block.timestamp)) +
        block.gaslimit+
        ((uint256(keccak256(abi.encodePacked(msg.sender))) / (block.timestamp)) +
        block.number
    )+_seed)));
    uint256 generated = seed - ((seed / _maxRange) * _maxRange);
    if(generated < _minRange) {
        generated = generated + _minRange;
    }
    if(generated > _maxRange) {
        generated = _maxRange;
    }
    return generated;
  }

}