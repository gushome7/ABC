// SPDX-License-Identifier: MIT
/*
 * @title: Asteroid Belt Club NFT KickStarter Program Implementation
 * @author: Gustavo Hernandez Baratta  (The Pan de Azucar Bay Company LLC)
 * @dev: Abstract Smart Contract that implements the KickStarter program.
 * The Kickstarter program aims to collect 500 ETH from early enthusiasts of the project. 
 * To do so, it grants a benefit consisting of multiplying the spending power of the funds deposited, according to a decreasing table.
 * Thus, the first 50 ETH deposited will have a spending power multiplied by 8, the next 50 ETH one multiplied by 4, 
 * the next 100 ETH one multiplied by 3 and the last 200 one multiplied by 2. 
 * The private variables kickStartTargets and kickStartBoost define this scale and the function kickStartThreshold() can be called 
 * to obtain the current reward level and the remaining amount in ETH of the current threshold. A minimum of 0.05 ETH is required as a deposit.
 * 
 * The balance of the accounts is stored in the kickStarters variable. 
 * The function getKickStartBalance() can be called at any time to obtain the available balance for a given address.
 * Multiple deposits can be made from a single ETH wallet. Funds are deposited by calling the kickstart function, 
 * which can only be called from the ABC website, as the transaction is signed by the CLUB.
 * 
 * The public variables kickStartCollected, kickStartSpent and kickStartMinted can be called to obtain information about the progress of the program.
 * kickStartCollected returns the total amount of funds collected by the program, kickStartSpent returns the total amount of collected 
 * funds already used and kickStartMinted returns the amount of claims made using the deposited funds.
 * 
 * When the contract is deployed, 1000 ETH are allocated to the Igniter, the owner of the contract. 
 * These are the assets he will have available to carry out the kickoff of the project, including rewarding his collaborators. 
 * Three public variables can be queried to determine the expenditure of these funds: ownerSpent, which stores the amount spent, 
 * ownerMinted, which stores the number of claims made, and ownerTransfered, which stores the total transferred by Ingiter to third parties.
 * 
 * @email: ghernandez@pandeazucarbay.com
 */

pragma solidity ^0.8.14;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/Context.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/utils/Strings.sol";
import "./utils/Signature.sol";

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
    uint256 public ownerTransfered=0; //Amount transfered to others by owner
    address private _owner=address(0);
    address private _signatureWallet=address(0);
    bool private paused;


    /* @dev: Event fired when Kickstart Balance was transferred */
    event KickstartBalanceTransfered(address from, address to,  uint256 amount);


    constructor(uint256 _credit) {
      kickStarters[msg.sender]=_credit;
      _owner=msg.sender;
    }

    /* @dev: returns current reward multiplier and the remaining to reach current threshold */
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

    /* @dev: return the current kickStarter Program balance for the given _address */
    function getKickStartBalance(address _address) public view returns(uint256) {
        return(kickStarters[_address]);
    }
 
    /* @dev: Called internally when the claim was made using kickstarter balance */
    function updateKickStartBalance(uint256 _cost,uint256 _minted) internal {
        require(kickStarters[msg.sender] >= _cost, "Not enough balance");
        kickStarters[msg.sender]=kickStarters[msg.sender]-_cost;
        if(msg.sender != _owner) {
            kickStartSpent=kickStartSpent+_cost;
            kickStartMinted=kickStartMinted+_minted;
        }
        else {
            ownerSpent=ownerSpent+_cost;
            ownerMinted=ownerMinted+_minted;
        }
    }
   
    /* @dev: Creates or increases the balance of an account with the amount resulting from multiplying the original amount deposited 
     * by the reward corresponding to the current program threshold. The deposit must be greater than or equal to the minimum amount 
     * determined in the kickStartMin variable, but equal to or less than the amount remaining to complete the current threshold.
     *
     * This function can only be called from the website, because it is signed.
     * If the _referer parameter is a valid ETH address, the referrers account will be credited with the corresponding commission.
     * The execution is stopped if: The threshold of 500 ETH was reached and kickStartThreshold() returned 0 as deposit reward; 
     * If more than the amount remaining to complete the current threshold is sent; If less than the minimum set in kickStartMin was sent; 
     * If the block timestamp is greater than the _expiration parameter; If the _msgHash parameter is invalid; 
     * Or if the signer is invalid (the signer's address does not match the one stored in the _signatureWallet variable.
     * As a result, in the array variable kickStarters, the msg.sender is assigned (or incremented by, if it already exists) 
     * the msg.value multiplied by the reward, and the kickStartCollected variable is updated with the amount entered. 
     * The _registerTotal function is also invoked to increment the total amount collected by the CLUB with the amount entered.
     */
    function kickstart(address _referer, uint32 _expiration, bytes32 _msgHash, bytes memory _signature) public payable {
        uint256[] memory boost= kickStartThreshold();
        require(!paused, "Contract paused");
        require(boost[0] > 0, "KickStart ended. Thanks!");
        require(boost[1] >=msg.value, string(abi.encodePacked("Please send no more than ", boost[1].toString())));
        require(msg.value >= kickStartMin, string(abi.encodePacked("Must send at least ", kickStartMin.toString())));
        require(_expiration > block.timestamp, "Signature expired");

        bytes memory __rawMsg = abi.encodePacked(Strings.toHexString(uint256(uint160(_referer)), 20),Strings.toString(_expiration));
        Signature.check(__rawMsg, _msgHash, _signature, _signatureWallet);

        kickStarters[msg.sender]=kickStarters[msg.sender]+(msg.value*boost[0]);
        kickStartCollected=kickStartCollected+msg.value;
        _registerTotal(msg.value);
        if(_referer != address(0)){
            _referrerPay(_referer,msg.value);
        }        
    }

    /* @dev: The holder of funds deposited in the kickStarter program can transfer them to a third party by invoking this function. 
     * The execution of the function is interrupted: If the parameter _to is not a valid address; OR if msg.sender does not have 
     * in its account an amount equal to or greater than the amount to be transferred. 
     * As a result, the amount transferred is subtracted from msg.sender's balance and credited to the recipient.
     *
     * If msg.sender is Igniter (the owner of the contract) the ownerTransferred variable is updated. 
     * Finally, it fires an event notifying the transfer. 
     */

    function kickStartTransfer(address _to, uint256 _amount  ) public {
        require(_to != address(0), "Please transfer your balance to a real address!");
        require(kickStarters[msg.sender] >=_amount, "You must have at least the amount in your kickstart balance");
        kickStarters[msg.sender] = kickStarters[msg.sender] - _amount;
        kickStarters[_to]=kickStarters[_to] + _amount;
       if(msg.sender == _owner) {
            ownerTransfered=ownerTransfered+ _amount;
        }        
        emit KickstartBalanceTransfered(msg.sender, _to, _amount);
    }

    /* @dev: called from main contract when owner change signature wallet */
    function _kickSignature(address _newSignatureWallet) internal {
        _signatureWallet=_newSignatureWallet;
    }

    function _kickStartPause(bool _status) internal {
        paused=_status;
    }

    function _registerTotal(uint256 value) internal virtual {}
    function _referrerPay(address referer, uint256 amount) internal virtual {}

}    