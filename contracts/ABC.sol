// SPDX-License-Identifier: MIT
/*
 * @title: Asteroid Belt Club NFT Smart Contract
 * @author: Gustavo Hernandez Baratta  (The Pan de Azucar Bay Company LLC)
 * @dev Smart contract for the creation and management of the NFTs corresponding
 * to the first property claim on the asteroids of the Asteroid Belt.
 
 * email: ghernandez@pandeazucarbay.com
 *
 * TODO: Definir fecha Belters Day.
 * TODO: Implementar ERC2981
 */

pragma solidity ^0.8.1;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/common/ERC2981.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";


import "./utils/Random.sol";
import "./utils/Datetime.sol";
import "./utils/PaymentSplitter.sol";

contract ABC is ERC2981, ERC721Enumerable, Ownable {
  using Strings for uint256;

  /* ABC Collection parameters and stored data */    
  string public baseURI; 
  string constant baseExtension = ".json";
  string constant _name='Asteroid Belt Club';
  string constant _symbol='ABC';
  uint256 public costRandom = 0.05 ether;
  uint256 public costSelected = 1 ether;
  uint256 public maxSupply = 605011;
  uint256 public maxToSale = 550000;
  uint256 public totalSales = 0;
  uint256 public geoPoliticalGenerated = 0;
  bool private geoPolitical =false;
  bool public paused = false;


  /* Kickstart parameters and stored data */
  uint256[] private kickStartTarget = [50 ether,100 ether,200 ether,500 ether];
  uint256[] private kickStartBoost=[800,400,300,200];  
  uint256 constant kickStartMin = 0.05 ether;
  mapping(address => uint256) public kickStarters; //Balances for kickstarters
  uint256 public kickStartCollected=0; //Collected thru kikStart Campaign
  uint256 public kickStartSpent=0; //Cost of Tokens minted using kickStart funds. (MAX: 1500)

  /* Belters Day parameters and stored*/
  uint256 public beltersDayRemaining=10000;
  mapping(uint256 => uint256) public beltersDayAssigned;
  uint256[] public beltersDay;
  mapping(address => bool) public belters;
  uint8 constant beltersDayMonth=4;
  uint8 constant beltersDayDay=12;
  uint16 constant beltersDayStartingYear=2022;
  uint256 constant beltersDayStartingAmount=4000;
  uint256 constant beltersDayFactor=2;
  address payable public abcVault;
  address public abcPayment;


 
  

  constructor( string memory _initBaseURI) ERC721(_name, _symbol) {
  
    abcVault = payable(new ABCVault(_msgSender()));
    address[] memory _payees=new address[](2);
    uint256[] memory _shares=new uint256[](2);
    _payees[0]=abcVault;
    _payees[1]=_msgSender();
    _shares[0]=70;
    _shares[1]=30;
    abcPayment = address(new ABCPayments(_payees,_shares));
    setBaseURI(_initBaseURI);  
    _assignBeltersDay(); //Belters Day Assignment.
    mint(abcVault,1); //Ceres will remain in ABC property forever. Minted and self transfered
    //Mint 20 random asteroids to start secondary market at marketplaces and transfer to owner()
    uint tokenId=Random.generate(2,maxSupply); 
    for(uint256 i = tokenId; i < tokenId+20; i++) {
      mint(owner(), i);
    }
  }


  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC2981, ERC721Enumerable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /* @dev: Fallback para recibir pagos directos al contrato.
   * Los royalties por transferencias subsiguientes tendrian que generar pagos que lleguen aca.
   * TODO: Emitir evento pago recibido.
   */
  receive() external payable  {      
  }


  /* @dev: Determina el Boost que se le aplicaran a los pagos kickstart de acuerdo al colectado
   * Informa el boost actual y la cantidad maxima permitida en un pago kickstart para obtener el beneficio
   */

  function kickStartReward() public view returns (uint256[] memory) {
    uint256[] memory boost = new uint256[](2);
    
    for(uint i=0;i<kickStartTarget.length;i++) {
      if(kickStartCollected < kickStartTarget[i]) {
          boost[0]=(kickStartBoost[i]/100);
          boost[1]=kickStartTarget[i]-kickStartCollected;
          break;
      }
    }
    return(boost);
  }


  /* @dev: Recibe pagos kickstart y emite NFT de cortesia
   * De acuerdo al whitepaper, hasta alcanzar kickStartTarget se aceptan pagos llamando a esta funcion, con un minimo de
   * kickStartMin. La funcion registra el sender y le asigna el pago efectuado.
   * 
   * TODO: Remover emision de cortesia.
   * TODO: Emitir evento pago recibido.
   */
  function kickstart() public payable {
    require(!paused, "Minting paused. Try again later");
    uint256[] memory boost= kickStartReward();
    
    require(boost[0] > 0, 'KickStart ended. Thanks!');
    require(boost[1] >=msg.value, string(abi.encodePacked('Please send no more than ', boost[1].toString())));
    require(msg.value >= kickStartMin, string(abi.encodePacked('Must send at least ', kickStartMin.toString())));

    kickStarters[_msgSender()]=kickStarters[_msgSender()]+(msg.value*boost[0]);
    kickStartCollected=kickStartCollected+msg.value;

    totalSales=totalSales + msg.value;
    //uint tokenId=Random.generate(2,maxSupply); 
    //_safeMint(_msgSender(),tokenId);    
  }

  /* @dev: Mintea el token especificado en tokenId, o selecciona uno en forma random
  * La coleccion no tendra mas que maxSupply elementos. maxSupply es la cantidad de asteroides numerados por el IAU
  * Aunque maxSupply se vaya actualizando en el tiempo, no afectara la cantidad de elementos de la coleccion en la medida que
  * no se mintearan mas que maxToSale para ser vendidos. El resto de los asteroides podran ser minteados para ser transferidos en el marco
  * de acuerdos o convenios (reserva geopolitica), lo que será decidido por los miembros del ABC.
  * El costo del minteo sera costRandom cuando no se especifique tokenId, o costSelected cuando se elija uno para mintear
  * 
  *
  * TODO: return overpaid call.
  * TODO: whitelist discount
  * TODO: Emit mint event.
  */
  function mint(address _to, uint256 tokenId) public payable {
    uint256 supply = totalSupply();
    uint256 cost = costRandom;
    require(!paused, "Minting paused. Try again later");
    require(supply < maxSupply, "Currently no NFT left to mint");
    require(supply - geoPoliticalGenerated < maxToSale, "Currently no NFT left to mint");
    
    if(tokenId >0) {
      require(!_exists(tokenId), "Token already minted ");
      cost = costSelected;
    }
    else {
      tokenId=_getRandomTokenId();    
    }
    if(_msgSender() != owner()) {
        if(msg.value==0 && kickStarters[_msgSender()]>=cost) {
          kickStarters[_msgSender()]=kickStarters[_msgSender()]-cost;
          kickStartSpent=kickStartSpent+cost;
        }
        else {
          require(msg.value == cost,string(abi.encodePacked('To do this mint you must send ', cost.toString())));
        }
    }
    totalSales=totalSales+msg.value;
    require(!_exists(tokenId), "Token already minted ");
    _safeMint(_to,tokenId);
    
  }

    /* @dev: Claim a BeltersDay free token to mint.
    * Los NFT pueden ser reclamados a partir de las 00:00 GMT de cada año, hasta la cantidad máxima especificada para ese
    * año al momento de publicar el contrato. Cuando se agota la cantidad debe esperarse hasta el año próximo.
    * Solo un NFT puede ser minteado con esta función por cada dirección.
    * El msg.sender debe ser el mismo que el destinatario del NFT (_to parameter)
    * TODO: Emit mint event.
    */
    function claim() public {
      require(!paused, "Minting paused. Try again later");
      uint256 currentBeltersDay;

      for(uint8 i; i<beltersDay.length;i++) {
        if(beltersDay[i] <=block.timestamp) {
          if(beltersDayAssigned[beltersDay[i]]>0) {
            currentBeltersDay=beltersDay[i];
            break;
          }
        }
        else {
          break;
        }
      }
      
      require(currentBeltersDay >0,"Claim cannot be processed right now. Wait for the next Belters Day");
      require(!belters[_msgSender()], "Only one NFT could be claimed thru belters day free claim");

      uint256 tokenId=_getRandomTokenId();
      require(!_exists(tokenId), string(abi.encodePacked("Token already minted ", Strings.toString(tokenId))));
      _safeMint(_msgSender(),tokenId);
      beltersDayAssigned[currentBeltersDay]--;
      belters[_msgSender()]=true;
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

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
      require( _exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

      string memory currentBaseURI = _baseURI();
      return bytes(currentBaseURI).length > 0
          ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension))
          : "";
    }

    //only owner
    function setRandomCost(uint256 _newCost) public onlyOwner {
      costRandom = _newCost;
    }

    function setSelectedCost(uint256 _newCost) public onlyOwner {
      costSelected = _newCost;
    }  

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
      baseURI = _newBaseURI;
    }

    function pause(bool _state) public onlyOwner {
      paused = _state;
    }


    function toggleGeopolitical(bool _state) public onlyOwner {
      geoPolitical = _state;
    }  

    function withdraw() public payable onlyOwner {
      address payable _to=payable(abcPayment);
      uint256 minAmount=10000000000000000;
      uint256 available=address(this).balance-minAmount;
      require(available >0,"Insuficient funds");
      _to.transfer(available);
      //Address.sendValue(address(abcPayment),address(this).balance);
      //require(Address(abcVault).send(address(this).balance));
    }

    function transferABCVaultOwnership(address _newOwner) public onlyOwner {
      ABCVault _vault = ABCVault(abcVault);
      _vault.transferOwnership(_newOwner);
    }

    // internal
    function _baseURI() internal view virtual override returns (string memory) {
      return baseURI;
    }

    function _getRandomTokenId() private view returns (uint256) {
      uint8 direction=1;
      uint256 tokenId=Random.generate(2,maxToSale);
      while(_exists(tokenId)) {
        if(tokenId == maxSupply) {
          direction=0;          
        }
        else if(tokenId ==2) {
          direction=1;
        }
        if(direction==1) {
          tokenId++;
        }
        else {
          tokenId--;
        }        
      } 
      return tokenId;
    }


    /* @dev: Create Belters Day information
    * Set the dates for the next 21 Belters Days and assign the number of NFTs that will be minted for free, according to the white paper.
    * First Year (beltersDayStartingYear) will mint for free beltersDayStartingAmount, which is reduced by dividing it by the beltersDayFactor.
    * Finally 100 free NFTs are added, to complete the total of 10.000 initials.
    * @author: Gustavo Hernandez Baratta for The Pan de Azucar Bay LLC
    * @version: 0.1A
    */

  function _assignBeltersDay() private {
    uint toAssign=beltersDayStartingAmount;
    uint16 year=beltersDayStartingYear;
    uint bd;
    for(uint16 i; i<20;i++) {
      bd=DateTime.toTimestamp(year,beltersDayMonth,beltersDayDay);
      beltersDay.push(bd);
      beltersDayAssigned[bd]=toAssign+100;
      beltersDayRemaining=beltersDayRemaining-(toAssign+100);
      toAssign=toAssign/beltersDayFactor;
      year=year+1;
    }
    bd=DateTime.toTimestamp(year,beltersDayMonth,beltersDayDay);
    beltersDay.push(bd);
    beltersDayAssigned[bd]=beltersDayRemaining;
    beltersDayRemaining=0;
  }
}


contract ABCVault is IERC721Receiver, Ownable {
  address public abcStarter;  

  constructor(address _abcStarter) {
    abcStarter = _abcStarter;
  }

  /* @dev: Vault debe poder recibir los pagos que envie splitter
   * TODO: Evento que notifique la recepción de pagos
   */
  receive() external payable {

  }
  
  function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
    return this.onERC721Received.selector;
  }

  function withdraw(address payable _to, uint256 _amount) public payable onlyOwner {
    require(_amount > address(this).balance, "Not enough funds to transfer that amount");
    
    (bool os, ) = _to.call{value: _amount}("");
    require(os);
  }

}

contract ABCPayments is  PaymentSplitter {

  constructor(address[] memory _payees, uint256[] memory _shares) PaymentSplitter(_payees,_shares) {

  }
}