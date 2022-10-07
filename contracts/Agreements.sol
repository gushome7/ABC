// SPDX-License-Identifier: MIT
/*
 * @title: Asteroid Belt Club NFT Strategic Agreements
 * @author: Gustavo Hernandez Baratta  (The Pan de Azucar Bay Company LLC)
 * Strategic agreements allow defining an amount in ETH that can be used to make property claims on asteroids, 
 * above the 550 thousand claims cap, although minted NFTs will not initially grant membership rights in the CLUB.
 *
 * Logic of the creation, approval and use of strategic agreements:
 * a) An agreement proposal can be made only from the DAO. This proposal must specify the wallet of the beneficiary, 
 * the amount in ETH that will be credited, the address of the contract that can activate it (the voting contract) 
 * and the amount in ETH that will be required for a minted NFT to acquire full rights in the CLUB.
 * Proposal.
 * To create an agreement, createAgreement() must be called from the DAO address. Initially the DAO address is not 
 * a valid address, so no agreement can be created. This function adds to the map _agreements a new agreement structure 
 * containing the agreement information, linked to the address of the wallet beneficiary of the agreement.
 *
 * b) The voting contract defines the rules governing the vote (majorities, deadlines, etc.) 
 * and if they are met, the activation is triggered. The activateAgreement() function activates a previously created agreement 
 * and can only be called from the address that was defined in the _activator parameter when creating the agreement.
 *
 * c) Finally, the beneficiary makes use of the assigned balance.
 * A safety delay of 63600 blocks is included between each of the steps. updateAgreementBalance() is called each time the 
 * balance of an agreement is used as the method of payment of the claim cost. The token is also incorporated into the NFT 
 * agreementTokens variable minted with those funds by calling the updateTokensMinted() function.
 * In case of emergency, the agreement can be paused/resumed by the owner by calling pauseAgreement()
 *
 * agreementMinted stores the number of claims made with agreement funds and agreementUsed the total amount of agreement funds already used. 
 * 
 * email: ghernandez@pandeazucarbay.com
 */

pragma solidity ^0.8.14;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";

abstract contract Agreements is Ownable {

    /* agreement structure */ 
    struct agreement {
        uint256 id; //sequence
        string name; //identifying name
        string description; //breaf description
        uint256 credits; //amount in ETH available to beneficiary
        uint256 used; //amount used from credit
        bool active; //active flag
        bool paused; //emergency pause
        address activator; //voting contract address
        uint256 validblock; //block from which the agreement can be approved // block from which the agreement remains in force
        uint256 befull; //amount in ETH that give full CLUB membership (0 could'n)
    }

    mapping(address => agreement) private _agreements; //map beneficiary address to agreement data
    mapping(uint256 => address) public agreementTokens; //register each token minted from agreement
    address[] private _idagreements; //array of beneficiary addresses

    uint256 public agreementMinted=0; //total of claims
    uint256 public agreementUsed=0; //total of balance used
    //uint256 public constant agreementRestrictionLimit=10; //10% of total (maxSupply) && 10% of total sales
    //uint256 public constant agreementRestrictionExpires=500000; //10% of sales restriction 
    uint256 public minToBeFull=0.1 ether;

    uint256 public constant blocksDelay=6; //safety pause between instances

    /* Events */
    event AgreementUsed(address agreement, uint256 amount, uint256 tokens);
    event AgreementAproved(uint256 id, uint256 sinceBlock);
    event NewAgreementProposed(uint256 id, string name, string description, uint256 credit, address activator, address beneficiary, uint256 blocksDelay);
    event AgreementPaused(address agreement, bool state);


    constructor() {
        _idagreements.push(address(0)); //To get all real agreement ids over 0 index
    }

    /* @dev: Emergency pause/restore an active agreement. Only Owner can call it. 
     * Emit an AgreementPaused event with new state */
    
    function pauseAgreement(address _address, bool _state) public onlyOwner {
        require(_agreements[_address].id > 0 
         && _agreements[_address].active==true ,"Agreement not found or not active");
        _agreements[_address].paused = _state;
        emit AgreementPaused(_address, _state);
    }



    /* @dev: Return an array with all beneficiary agreements */
    function getList() public view returns(address[] memory) {
        return(_idagreements);
    }

    /* @dev: Return agreement data for given beneficiary address */
    function getAgreement(address _address) public view returns(agreement memory) {
        return(_agreements[_address]);
    }

    /* @dev: return the current available balance for a given beneficiary address */ 

    function getAgreementBalance(address _address) public view returns(uint256) {
        if(_agreements[_address].paused==false && _agreements[_address].active && block.number > _agreements[_address].validblock ) {
            return _agreements[_address].credits - _agreements[_address].used;
        }
        return(0);
    }

    /* @dev: updates Agreement Balance. Called from ABC contract when minting
     * msgSender() must be owner of an agreement
     * @params:
     * _amount: cost of the minting
     * _tokens: quantity of tokens minted
     * Execution stopped if not found an agreement for msg.sender address, if agreement was paused, 
     * if not active, or with less credit amount than required.
     * Updates agreement.used credit, agreementUsed with _amount and agreementMinted with _tokens
     * Emit an AgreementUsed event
     */

    function updateAgreementBalance(uint256 _amount, uint256 _tokens) internal {
        require(_agreements[_msgSender()].id >0 
         && _agreements[_msgSender()].paused==false 
         && _agreements[_msgSender()].active 
         && block.number > _agreements[_msgSender()].validblock , "Agreement not found or not ready");

        require(_agreements[_msgSender()].credits-_agreements[_msgSender()].used >= _amount,"Not enough available credit");
        _agreements[_msgSender()].used=_agreements[_msgSender()].used+_amount;
        agreementUsed=agreementUsed+_amount;
        agreementMinted=agreementMinted+_tokens;
        emit AgreementUsed(_msgSender(),_amount, _tokens);
    }

    /* @dev: Adds the id of the minted token to the agreementTokens list, which is used to determine if the token has CLUB membership rights.*/
    function updateTokensMinted(uint256 _tokenId) internal {
        agreementTokens[_tokenId]=_msgSender();
    }

    /* @dev Creates a new agreement with _address as beneficiary, and delegates to _activator the power to activate it.
     * @params:
     * name: identification of the agreement
     * description: a brief description
     * credits: amount to be assigned
     * activator: address authorized to activate agreement
     * address: if active, from what address can mint using credit.
     * befull: amount the NFT holder must pay to become a full member of the ABC. zero closes the possibility. must be at least minToBeFull
     * The agreement cannot be activated before the block set in ValidBlock.
     * This gives the community a time frame to react in case of a spuriously created agreement.
     * Execution is stopped if a previously defined agreement is found for that beneficiary
     * Emit a NewAgreementProposed event
     * Returns a structure with the information of the newly created agreement
     */

    function createAgreement(string memory _name, string memory _description, uint256 _credits, address _activator, address _address, uint256 _befull) public onlyOwner returns(agreement memory) {
        require(_agreements[_address].id == 0 ,"Already exists an agreement owned by that address");
        require(_befull==0 || _befull >=minToBeFull, "If want to grant DAO rights payment must be at least minToBeFull");
        agreement memory _agreement;
        _agreement.id=_idagreements.length;
        _agreement.name=_name;
        _agreement.description=_description;
        _agreement.credits=_credits;
        _agreement.active=false;
        _agreement.paused=false;
        _agreement.activator=_activator;
        _agreement.validblock=block.number+blocksDelay;
        _agreement.befull=_befull;
        _idagreements.push(_address);
        _agreements[_address]=_agreement;
        emit NewAgreementProposed(_agreement.id, _name, _description, _credits, _activator, _address, _agreement.validblock);      
        return _agreement;  
    }

    /* @dev: This function must be called by the DAO contract where the agreement is voted on.
     * No agreement is effective until the function is executed. 
     * The voting contract must include a call to this function once the successful result of the vote is verified. 
     * The agreement has a delay of blocksDelay before it becomes valid. This gives the community a time frame to
     * react in case of a spuriously activated agreement.
     * Execution is stopped if _id is not a valid agreement, if caller is not the activator, if activation occurs before validblock 
     * or if already active.
     * A new validblock is set delaying it in blocksDelay
     * Emit an AgreementAproved event.
     */
    function activateAgreement(uint256 _id) public {
        require(_idagreements[_id] != address(0), "Agreement not found");
        address _agreement=_idagreements[_id];
        require(_agreements[_agreement].activator == _msgSender(),"Only activator can activate agreement");
        require(block.number > _agreements[_agreement].validblock,"Wait for valid block until activate");
        require(_agreements[_agreement].active==false,"Agreement already active");
        _agreements[_agreement].active=true;
        _agreements[_agreement].validblock=block.number+blocksDelay;

        emit AgreementAproved(_id, _agreements[_agreement].validblock);
    }

  function setMinToBeFull(uint256 _newValue) public onlyOwner {
    require(_newValue > minToBeFull, "New value must be greather than current");
    minToBeFull=_newValue;
  }     

}    