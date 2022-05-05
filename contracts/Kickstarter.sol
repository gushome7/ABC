// SPDX-License-Identifier: MIT
/*
 * @title: Asteroid Belt Club NFT Strategic Agreements
 * @author: Gustavo Hernandez Baratta  (The Pan de Azucar Bay Company LLC)
 * @dev Funciones que implementan el programa kickstart.
 * 
 
 * email: ghernandez@pandeazucarbay.com
 */

pragma solidity ^0.8.1;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/Context.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/Strings.sol";

abstract contract Kickstarter {
    using Strings for uint256;
    /* Kickstart parameters and stored data */
    uint256[4] private kickStartTargets = [50 ether,100 ether,200 ether,500 ether];
    uint256[4] private kickStartBoost=[800,400,300,200];  
    uint256 constant kickStartMin = 0.05 ether;
    mapping(address => uint256) public kickStarters; //Balances for kickstarters
    uint256 public kickStartCollected=0; //Collected thru kikStart Campaign
    uint256 public kickStartSpent=0; //Cost of Tokens minted using kickStart funds. (MAX: 1500)
    uint256 public kickStartMinted=0; //Tokens minted using kickstart balances
    uint256 public ownerSpent=0; //Cost of token minted by owner using constructor credit
    uint256 public ownerMinted=0; //Token minted by owner using constructor credit;
    address private _owner=address(0);

    constructor(uint256 _credit) {

      kickStarters[msg.sender]=_credit;
      _owner=msg.sender;
    }

    /* @dev: Calcula la recompensa y el umbral actual del programa kickstart de acuerdo al total colectado.
     */
    function kickStartThreshold() public view returns (uint256[] memory) {
        uint256[] memory boost = new uint256[](2);
        
        for(uint i=0;i<kickStartTargets.length;i++) {
        if(kickStartCollected < kickStartTargets[i]) {
            boost[0]=(kickStartBoost[i]/100);
            boost[1]=kickStartTargets[i]-kickStartCollected;
            break;
        }
        }
        return(boost);
    }

    /* @dev: Devuelve el balance actual de una direccion dada
     */
    function getKickStartBalance(address _address) public view returns(uint256) {
        return(kickStarters[_address]);
    }
 
    /* @dev: Actualiza el balance de una cuenta, y los contadores de total gastado y cantidad minteada
     */
    function updateKickStartBalance(uint256 _cost,uint256 _minted) internal {
        require(kickStarters[msg.sender] >= _cost, "Not enough balance");
        kickStarters[msg.sender]=kickStarters[msg.sender]-_cost;
        if(msg.sender != _owner) {
            kickStartSpent=kickStartSpent+_cost;
            kickStartMinted=kickStartMinted+_minted;
        }
        else {
            ownerSpent=ownerSpent+_cost;
            ownerMinted=ownerMinted=_minted;
        }
    }
   
    /* @dev: Crea o actualiza el balance de una cuenta del programa kickstart con la recomensa correspondiente
     * al umbral actual. El monto enviado debe ser mayor a kickStartMin, y menor o igual al monto restante del umbral actual.
     * 
     */
    function kickstart() public payable {
        uint256[] memory boost= kickStartThreshold();
        
        require(boost[0] > 0, "KickStart ended. Thanks!");
        require(boost[1] >=msg.value, string(abi.encodePacked("Please send no more than ", boost[1].toString())));
        require(msg.value >= kickStartMin, string(abi.encodePacked("Must send at least ", kickStartMin.toString())));

        kickStarters[msg.sender]=kickStarters[msg.sender]+(msg.value*boost[0]);
        kickStartCollected=kickStartCollected+msg.value;
        _registerTotal(msg.value);
  }

  function _registerTotal(uint256 value) internal virtual {}

}    