// SPDX-License-Identifier: MIT
/*
 * @title: Asteroid Belt Club NFT Smart Contract
 * @author: Gustavo Hernandez Baratta  (The Pan de Azucar Bay Company LLC)
 * @dev Smart contract for the creation and management of the NFTs corresponding
 * to the first property claim on the asteroids of the Asteroid Belt.
 
 * email: ghernandez@pandeazucarbay.com
 *
 */

pragma solidity ^0.8.14;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/common/ERC2981.sol";


import "./Agreements.sol";
import "./Kickstarter.sol";
import "./utils/Utils.sol";



contract ABC is ERC2981, ERC721Enumerable, Agreements, Kickstarter {
  using Strings for uint256;
  

  /* ABC Collection parameters and stored data */    
  string public baseURI; 
  string public constant baseExtension = ".json";
  string public constant _name='Asteroid Belt Club';
  string public constant _symbol='ABC';
  

  /* Asteroid Naming Services*/
  mapping(uint256 => string) private _ansModifiedURI; //Asteroid Naming Services Modifier;
  address private _ansAddress=address(0); //Pending to be defined using setAnsAddress()

 /* Asteroid Belt Club Web Signature */
  address private _signatureWallet=address(0); //Pending to be defined using setSignatureWallet()
  mapping(string => bool) private _usedUniqids; //On random minting, a random selection could be used only once
  
  uint256 public maxSupply = 605011; //Initially, the asteroids numbered by the IAU as of December 31, 2021 are contemplated,
                                     //then others will be incorporated according to the schedule established in the Whitepaper.

  uint256 public  maxToSale = 550000; //Max membership.
  uint256 public totalSales = 0; //Total incomes
  uint256 public constant maxMinting=10; //Max token minting in one call to mint() or random() functions.
  bool public paused = false; //Emergency pause

  /* ABC Starter Minting Privileges passed to kickstarter*/
  uint256 public constant ownerCanMintMax=1000 ether; //Buying power granted to Igniter (see Whitepaper)
  uint8 public constant ownerInitialMinting=10; //10 random claims created to start markets like Opensea
  
  /* ABC Vault and Payment Splitter address filled at deployment */
  address payable public abcVault;
  address public abcPayment;


  /* ABC referer program */
  uint256 public referrersPaid = 0; //Total commissions generated with the referral program
  uint256 public referrersWidthrawn = 0; //Withdrawn commissiones
  uint96 private constant referrerFee = 500; //5% 
  uint96 private constant referrerFeeDenominator=10000;
  mapping(address => uint256) private _referrerBalance; //Referral Program Balances

  /* ABC Belter's Day */
  uint16 public beltersDayMinted =0; //Minted counter
  uint16 public constant beltersDayMax=10000;  //Max to mint

  /* Events */
  event PaymentReceived(address from, uint256 amount);
  event StateChanged(bool newState);
  event Withdrawn(address sender, uint256 amount);
  event NewMaxSupply(uint256 oldMaxSupply, uint256 newMaxSupply);
  event URIChanged(uint256 indexed tokenId, string newURI);
  event RightsUpgraded(uint256 indexed tokenId);
  event ReferrerPaid(address referer, uint256 amount);
  event ReferrerWidthraw(address referer, uint256 amount );
  event ReferrerCanceled(address referer, uint256 amount );

  
  constructor(address _vault, address _splitter) ERC721(_name, _symbol) Kickstarter(ownerCanMintMax) {
    //ABC Vault is where the CLUB will store its assets
    abcVault = payable(_vault); 
    //Payment splitter receive payments and split them between ABC Vault and Igniter
    abcPayment = _splitter;
    _setDefaultRoyalty(abcPayment, 1000); //Royalties must be paid directly to abcPayment.  
    _initialMint();
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC2981, ERC721Enumerable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /* @dev: Direct payments to the contract not covered by a specific function 
   * Emit a paymentReceived Event*/
  receive() external payable  {      
    emit PaymentReceived(_msgSender(), msg.value);

  }
  /* @dev: Mints one or more NFTs up to the maximum specified in maxMinting.
   * The function call is signed, so it can only be called from the CLUB web site.
   * @params:
   * _to the owner of the minted tokens
   * _referrer, address of referrer or address(0)
   * _tokenIds, array with token to be minted
   * _cost, total cost of minting _tokenIds.
   * _msgHash, obtained from concatenating _to, _referrer, ids, _cost
   * _signature, signature of the transaction
   * The execution is interrupted if: the contract is paused, if it was not specified which tokenIds want to be minted; 
   * if _cost parameter is 0.
   * If it is intended to mint more than maxMinting in the function call; If all NFTs representing claims on the 
   * total numbered asteroids already incorporated (maxSupply) have been minted; If it is not minting by strategic agreement 
   * but the maxToSale limit was reached; If the amount transferred in the call is greater than zero but different from _cost; 
   * If the amount is zero but there are no funds in either agreements or kickStarter covering the cost;  
   * Or if simultaneously with the call the asteroid was already claimed.
   * 
   */
  function mint(address _to, address _referrer, uint256[] memory _tokenIds, uint256 _cost,  bytes32 _msgHash, bytes memory _signature) external payable {

    uint256 __realMaxToSale = maxToSale - (beltersDayMax-beltersDayMinted); //Belter's Day raffles must be reserved
    bool __agreement=false;

    _checkPaused();
    require(_tokenIds.length >0, "Specify at least one tokenId");
    require(_cost >0, "Direct mint for free not allowed");
    require(_tokenIds.length <= maxMinting,string(abi.encodePacked("Mint no more that 10 per call")));
    require(totalSupply() + _tokenIds.length < maxSupply, "Currently no NFT left to mint");

    if(getAgreementBalance(_msgSender()) < _cost || msg.value > 0 ) {
      require((totalSupply() + _tokenIds.length - agreementMinted) <= __realMaxToSale, "Currently no NFT left to mint");
    }

    require(msg.value==0 || msg.value==_cost, string(abi.encodePacked("Amount invalid ",_cost.toString())));

    
    string memory __implodedIds=Utils.implodeIds(_tokenIds);
    bytes memory __rawMsg = abi.encodePacked(Strings.toHexString(uint256(uint160(_to)), 20),Strings.toHexString(uint256(uint160(_referrer)), 20),__implodedIds,_cost.toString());
    _checkSignature(__rawMsg, _msgHash, _signature);
 
    /*Chequeo de los fondos con los que se hace el minteo */
    if(msg.value==0 && getKickStartBalance(_msgSender()) >= _cost) {
      updateKickStartBalance(_cost,_tokenIds.length);
    }
    else if(msg.value==0 && getAgreementBalance(_msgSender())>=_cost) {

      require(maxToSale/10 >= agreementMinted + _tokenIds.length, "Agreement threshold reached. Try later "  );
      require(totalSales/10 >= agreementUsed + _cost || totalSupply() > 500000, "Agreement threshold reached. Try later "  );
      updateAgreementBalance(_cost,_tokenIds.length);
      __agreement=true;
    }
    else {
      require(msg.value == _cost,string(abi.encodePacked("Must send ", _cost.toString())));
    }

    if(msg.value >0) {
      _registerTotal(msg.value);
      if(_referrer != address(0)){
        _referrerPay(_referrer,msg.value);
      }
    }
    _mint(_to,_tokenIds.length,__agreement, _tokenIds,false);

  }

  /* @dev: It randomly mints up to n tokens specified in amount using the tokens specified in tokenIds as a base.   
   * The msgHash is the hash of the message obtained by concatenating _to, implode _tokenIds, _amount, _cost, 
   * _uniqid and _expiration _signature is the signature of the msgHash signed with the private key of _signatureWallet.
   * @params:
   * _to: Beneficiary address
   * _referrer: address of the referrer or address(0)
   * _amount: quantity of nft to be minted
   * _tokenIds: randomly generated ids. One or more of them will also be chosen at random.
   * _cost: the total cost of the claim. 
   * _uniqid: a unique identifier that prevents the randomly generated list from being used more than once.
   * _expiration: timestamp after which the signature that validates the parameters of the function call expires and prevents manipulation of the random choice.
   * _msgHash: obtained from concatenating _to, _referrer, _amount, _cost, _uniqid and _expiration
   * _signature: signature of the transaction
   * The execution is interrupted if: contract is paused; random tokenlist is invalid; _amount > maxMinting; maxSupply reached; 
   * cost == 0 (only possible when claim is from Belter's Day winner) but beltersDayMax was previously reached
   * cost == 0 (only possible when claim is from Belter's Day winner) but _amount greather than 1;
   * if it is not minting by strategic agreement but the maxToSale limit was reached;
   * if msg.value >0 but is not equal to _cost
   * if Signature already used, or expired.
   * If something was wrong and the randomly choosen token was already minted
   * 
   */
  function random(address _to, address _referrer, uint256 _amount, uint256[] memory _tokenIds, uint256 _cost, string memory _uniqid, uint32 _expiration, bytes32 _msgHash, bytes memory _signature) external payable {
    bool __agreement=false;
    uint256 __realMaxToSale = maxToSale - (beltersDayMax-beltersDayMinted); //Belter's Day raffles must be reserved

    _checkPaused();
    require(_tokenIds.length==200, "Invalid tokenlist");
    require(_amount >0 && _amount <= maxMinting,string(abi.encodePacked("Max mint 10 per call")));
    require(totalSupply() + _amount < maxSupply, "No NFT left to mint");

    if(beltersDayMax-beltersDayMinted==0) {
      require(_cost >0, "Belters Day total reached");
    }

    if(_cost==0) {
      //Only Belter's Day winner can mint for free but only one. 
      require(_amount==1,"Only one to mint if it for free");
      beltersDayMinted++;
    }

    if((_cost >0 && getAgreementBalance(_msgSender()) < _cost) || msg.value > 0 ) {
      require((totalSupply() + _amount - agreementMinted) <= __realMaxToSale, "Currently no NFT left to mint");
    }
    require(msg.value==0 || msg.value==_cost, string(abi.encodePacked("Transfer ",_cost.toString())));

    /* Signature Checking */
    require(_usedUniqids[_uniqid]==false, "Signature already used");
    require(_expiration > block.timestamp, "Signature expired");
    string memory __implodedIds=_implodeIds(_tokenIds);
    bytes memory __rawMsg = abi.encodePacked(Strings.toHexString(uint256(uint160(_to)), 20),Strings.toHexString(uint256(uint160(_referrer)), 20),__implodedIds,_amount.toString(), _cost.toString(),_uniqid,Strings.toString(_expiration));
    _checkSignature(__rawMsg, _msgHash, _signature);
    _usedUniqids[_uniqid]=true;

    /* kickstartBalance or agreementBalance or msg.value source */
    if(msg.value==0 && getKickStartBalance(_msgSender()) >= _cost) {
      updateKickStartBalance(_cost,_amount);
    }
    else if(msg.value==0 && getAgreementBalance(_msgSender())>=_cost) {

      require(totalSales/10 >= agreementUsed + _cost || totalSupply() > 500000, "Agreement threshold reached. Try later "  );      
      require(maxToSale/10 >= agreementMinted + _amount, "Agreement threshold reached. Try later "  );
   
      updateAgreementBalance(_cost,_amount);
      __agreement=true;
    }
    else {
      require(msg.value == _cost,string(abi.encodePacked("To do this mint you must send ", _cost.toString())));
    }
  
    if(msg.value >0) {
      _registerTotal(msg.value);
      if(_referrer != address(0)){
        _referrerPay(_referrer,msg.value);
      }      
    }
    
    _mint(_to,_amount,__agreement, _tokenIds,true);
  }

  /* @dev: internal function called to mint direct or random */
  function _mint(address _to, uint256 _amount, bool _agreement, uint256[] memory _tokenIds, bool _random) private {
    uint256 __tokenId=0;
    for(uint256 i=0; i<_amount; i++) {
      if(_random){
      __tokenId=_getRandomTokenFromList(__tokenId, _tokenIds);
      }
      else {
        __tokenId=_tokenIds[i];
        require(!_exists(__tokenId), "Token already minted ");      
      }
      if(_agreement) {
        updateTokensMinted(__tokenId);
      }
      _safeMint(_to,__tokenId);     
    }
  }

 
  /* Developed using Hashlips (https://github.com/HashLips) and another sources as examples. */
  function walletOfOwner(address _owner) public view returns (uint256[] memory) {
    uint256 ownerTokenCount = balanceOf(_owner);
    uint256[] memory tokenIds = new uint256[](ownerTokenCount);
    for (uint256 i; i < ownerTokenCount; i++) {
      tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
    }
    return tokenIds;
  }

  /* @dev: Returns the URI of the token. If the asteroid was renamed by the Asteroid Naming Service 
   * then the URI returned will be the one corresponding to the modified manifest.
   * Developed using Hashlips (https://github.com/HashLips) and another sources as examples. 
   */
  function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
    require( _exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
    string memory currentBaseURI = _baseURI();
    if(bytes(_ansModifiedURI[tokenId]).length >0) {
      return _ansModifiedURI[tokenId];
    }
    else {
      return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension))
        : "";
    }
  }

  /* @dev: Checks if the NFT _tokenId has full rights in the DAO. */
  function hasDaoRights(uint256 tokenId) public view returns(bool) {
    require(_exists(tokenId), "Token not minted");
    if(agreementTokens[tokenId] != address(0)) return(false);
    return(true);
  }


  /* @dev: If it possible by agreement, and msg.value equals to agreement.befull * _votes _tokenId convert owner to a full member of the CLUB 
   */

  function giveMeDaoRights(uint256 _tokenId, uint256 _votes, string memory _uniqid, uint32 _expiration, bytes32 _msgHash, bytes memory _signature) public payable {        
    require(_exists(_tokenId), "Token not minted");
    require(agreementTokens[_tokenId] != address(0), "Token already have full rights");
    agreement memory _agreement=getAgreement(agreementTokens[_tokenId]);
    require(_agreement.befull>0, "Agreement don't allow improve token rights");

    require(_usedUniqids[_uniqid]==false, "Signature already used");
    require(_expiration > block.timestamp, "Signature expired");

    bytes memory __rawMsg = abi.encodePacked(_tokenId.toString(),_votes.toString(),_uniqid,Strings.toString(_expiration));
    _checkSignature(__rawMsg, _msgHash, _signature);
     _usedUniqids[_uniqid]=true;
    uint256 __cost=_agreement.befull*_votes;
    require(msg.value==__cost,string(abi.encodePacked("You must send ", __cost.toString()," to get full rights")));
    delete agreementTokens[_tokenId];
    emit RightsUpgraded(_tokenId);
  }



  /* @dev: Transfer funds to the Payment Splitter
   * The function remains public for anyone to initiate transfers, which prevents funds 
   * from being held hostage in the contract, in case of discrepancies between the final 
   * beneficiaries of the funds. The function remains public so that anyone can initiate transfers, 
   * which prevents funds from being held hostage in the contract, in case of discrepancies between 
   * the final beneficiaries of the funds.
   *
   * Since PaymentSplitter is invariant after the contract is launched, and the funds cannot be sent 
   * to any other address, it is safe for the function to remain public.
   *
   * Subtract from the transferable balance the outstanding amounts to be paid to the referrers.
   * 
   */
  function withdraw() public {
    address payable __to=payable(abcPayment);      
    uint256 __available=(address(this).balance-_referrersPending());
    require(__available >0,"Insuficient funds");
    __to.transfer(__available);
    emit Withdrawn(_msgSender(),__available);
  }

  /* @dev: Returns the referral balance of the queried _referrer address */
  function referrerBalance(address _referrer) public view returns(uint256){
    return _referrerBalance[_referrer];
  }

  /* If the msgSender has a balance, 
   * calling the function initiates the withdrawal to your wallet of the available balance generated with the referral program.
   * if referrer didn't whidthrawn after 1 year of it's  first payment or last widthraw we can revert payment or last cancel Payment
   */
  function referrerWidthraw(address _referrer) public {
    uint256 __available=_referrerBalance[_referrer];
    require(__available >0, "Insuficient funds");
    _referrerBalance[_referrer]=0;
    referrersWidthrawn=referrersWidthrawn+__available;
    if(_msgSender()==_signatureWallet) {
      emit ReferrerCanceled(_referrer,__available);
    }
    else {
      payable(_referrer).transfer(__available);
      emit ReferrerWidthraw(_referrer,__available);
    }

  }

  /* @dev: Overwrite the token URI to reflect changes made from the Asteroid Naming Service (ANS). 
   * Until the service is available this function cannot be used. The function cannot be used more 
   * than once per token. ANS will not call this function if the asteroid was named by the IAU.
   */
  function ansSetNewURI(uint256 _tokenId, address _owner, string memory _newURI) public {
    require(ownerOf(_tokenId)==_owner, "Not the owner");
    require(_msgSender() == _ansAddress, "Only Asteroid Naming Services can call that function");
    require(_exists(_tokenId), "Token not yet minted");
    require(bytes(_newURI).length >0, "Please set a new URI");
    require(bytes(_ansModifiedURI[_tokenId]).length==0, "Token already named");
    _ansModifiedURI[_tokenId]=_newURI;
    emit URIChanged(_tokenId, _newURI);
  }





  /* @dev: Set the base URI   */
  function setBaseURI(string memory _newBaseURI) public onlyOwner {      
    baseURI = _newBaseURI;
  }

  /* @dev: Pause and restart minting functions */
  function pause(bool _state) public onlyOwner {
    paused = _state;
    emit StateChanged(_state);
  }

  function _checkPaused() internal view  override {
    require (!paused , "Contract paused");
  }

  /* @dev: Update maxSupply and maxToSale
   * maxSupply represents the highest number of asteroids numbered by the IAU. Periodically ABC Starter 
   * will update the maxSupply, and generate the files available to be claimed. In case the maximum amount 
   * to be offered to the market has been reached, they can only be claimed through strategic agreements.
   * After initial offer maxToSale will never be more than 9/10 of maxSupply.
   */
  function setMaxSupply(uint256 _newMaxSupply) public onlyOwner {
    require(_newMaxSupply > maxSupply, "New max supply must be greather than current");
    uint256 __oldMaxSupply=maxSupply;
    maxSupply=_newMaxSupply;
    maxToSale=maxSupply*90/100;
    emit NewMaxSupply(__oldMaxSupply, maxSupply);
  }
 

  /* @dev: Allows to configure the address that signs the messages in mint, random and kickstart.*/
  function setSignatureWallet(address _newWallet) public onlyOwner {
    require(_newWallet != address(0), "Set Valid Address");
    _signatureWallet=_newWallet;
  }

  /* @dev: To be used to configure the ANS wallet address. */
  function setAnsAddress(address _newAddress) public onlyOwner {
    _ansAddress=_newAddress;
  }

  // internal
  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
  }

  /* @dev: Calculates the total amount due to referrers */
  function _referrersPending() private view returns (uint256) {
    return referrersPaid-referrersWidthrawn;
  }

  function _checkSignature(bytes memory _raw, bytes32 _msgHash, bytes memory _signature) internal view override {
    Utils.SignatureCheck(_raw, _msgHash, _signature, _signatureWallet);
  }


  /* @dev: Register a new fund entry by mint, random or kickstarter */
  function _registerTotal(uint256 amount) internal override {
    totalSales=totalSales+amount;
    emit PaymentReceived(_msgSender(), amount);
  }

  /* @dev: Adds the commission generated by the referral program to the referrer's account*/
  function _referrerPay(address _referrer, uint256 _amount) internal override {
    referrersPaid=referrersPaid+((_amount*referrerFee)/referrerFeeDenominator);
    _referrerBalance[_referrer]=_referrerBalance[_referrer]+((_amount*referrerFee)/referrerFeeDenominator);
    emit ReferrerPaid(_referrer, ((_amount*referrerFee)/referrerFeeDenominator));
  }


  /* @dev: generate CERES token and transfer it to vault. Mint ownerInitialMinting NFTs and transfer it to Igniter */
  function _initialMint() private {
    uint256 __tokenId=0;
    _safeMint(abcVault,1);
    for(uint16 i=0; i<ownerInitialMinting; i++){
      __tokenId=_getRandomTokenId(__tokenId);
      _safeMint(_msgSender(),__tokenId);     
    }      
  }

  /* @dev: return array elements imploded in a string */
  function _implodeIds(uint256[] memory _ids) private pure returns (string memory) {
    bytes memory output;

    for (uint256 i = 0; i < _ids.length; i++) {
      output = abi.encodePacked(output, Strings.toString(_ids[i]));
    }
    return string(output);      
  }

  /* @dev: get a randomly chosen token Id from list. Used in random mint mint */
  function _getRandomTokenFromList(uint256 _seed, uint256[] memory _ids) private view returns (uint256) {
    uint256 __tokenId=_ids[Utils.RandomGenerate(0,_ids.length -1,_seed)];
    uint16 __iterations=0;
    while(_exists(__tokenId)) {
      __tokenId=_ids[Utils.RandomGenerate(0,_ids.length -1,__tokenId)];
      __iterations++;
      require(__iterations < 10, "An error occurs. Please retry");         
    }
    return(__tokenId);

  }
  /* @dev: get a randomly chosen token Id from total. Used in initial mint */
  function _getRandomTokenId(uint256 _seed) private view returns (uint256) {
    uint256 __tokenId=Utils.RandomGenerate(2,maxToSale,_seed);
    uint16 __iterations=0;
    while(_exists(__tokenId)) {
      __tokenId=Utils.RandomGenerate(2,maxToSale,__tokenId);
      __iterations++;
      require(__iterations < 10, "An error occurs. Please retry");
    } 
    return __tokenId;
  }
}
