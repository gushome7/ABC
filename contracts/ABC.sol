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

import "./Agreements.sol";
import "./Kickstarter.sol";
import "./utils/Random.sol";
import "./utils/Datetime.sol";
import "./utils/PaymentSplitter.sol";

contract ABC is ERC2981, ERC721Enumerable, Agreements, Kickstarter {
  using Strings for uint256;

  /* ABC Collection parameters and stored data */    
  string public baseURI; 
  string public constant baseExtension = ".json";
  string public constant _name='Asteroid Belt Club';
  string public constant _symbol='ABC';
  
  uint256 public costRandom = 0.05 ether;
  uint256 public costSelected = 1 ether;
  uint256 public maxSupply = 605011;
  uint256 public maxToSale = 550000;
  uint256 public totalSales = 0; //
  uint256 public constant maxMinting=200; //Cantidad maxima de tokens a mintear en una llamada a mint()
  bool public paused = false;

  /* ABC Starter Minting Privileges passed to kickstarter*/
  uint256 public constant ownerCanMintMax=499 ether; //500 ether - 1 ether for 20 random minted on constructor
  
  /* Belters Day parameters and stored*/
  mapping(uint256 => uint256) public beltersDayAssigned;
  uint256[] public beltersDay;
  mapping(address => bool) public belters;

  /* ABC Vault and Payment Splitter address filled at deployment */
  address payable public abcVault;
  address public abcPayment;


  constructor( string memory _initBaseURI) ERC721(_name, _symbol) Kickstarter(ownerCanMintMax) {
    abcVault = payable(new ABCVault());
    address[] memory _payees=new address[](2);
    uint256[] memory _shares=new uint256[](2);
    _payees[0]=abcVault;
    _payees[1]=_msgSender();
    _shares[0]=70;
    _shares[1]=30;
    abcPayment = address(new ABCPayments(_payees,_shares));
    setBaseURI(_initBaseURI);  
    _assignBeltersDay(); //Belters Day Assignment.
    mint(abcVault,1,1); //Ceres will remain in ABC property forever. Minted and self transfered
    //Mint 20 random asteroids to start secondary market at marketplaces and transfer to owner()
    mint(owner(), 0, 20);
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



  /* @dev: Recibe pagos kickstart y emite NFT de cortesia
   * De acuerdo al whitepaper, hasta alcanzar kickStartTarget se aceptan pagos llamando a esta funcion, con un minimo de
   * kickStartMin. La funcion registra el sender y le asigna el pago efectuado.
   * 
   * TODO: Emitir evento pago recibido.
   */


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
  function mint(address _to, uint256 tokenId, uint256 _toMint) public payable {
    uint256 supply = totalSupply();
    uint256 cost = costRandom;
    bool agreement=false;
    require(!paused, "Minting paused. Try again later");
    require(_toMint <= maxMinting,string(abi.encodePacked("Please mint no more that ",maxMinting.toString()," per call")));
    require(supply+_toMint < maxSupply, "Currently no NFT left to mint");
    require((supply+_toMint - agreementMinted) < maxToSale, "Currently no NFT left to mint");
    if(_toMint==0) {
      _toMint=1;
    }

    if(tokenId >0) {
      require(_toMint==1, "If specify tokenId you can mint only one NFT");
      require(!_exists(tokenId), "Token already minted ");
      cost = costSelected;
      _toMint=1;
    }
    cost=cost*_toMint;
    
    if(msg.value==0 && getKickStartBalance(_msgSender()) >= cost) {
      updateKickStartBalance(cost,_toMint);
    }
    else if(msg.value==0 && getAgreementBalance(_msgSender())>=cost) {
      updateAgreementBalance(cost,_toMint);
      agreement=true;
    }
    else {
      require(msg.value == cost,string(abi.encodePacked("To do this mint you must send ", cost.toString())));
    }
    
    totalSales=totalSales+msg.value;
    if(tokenId==0) {
      for(uint256 i=0; i<_toMint; i++) {
        tokenId=Random.generate(2,maxSupply,tokenId);
        if(agreement) {
          updateTokensMinted(tokenId);
        }
        _safeMint(_to,tokenId);
      }
    }
    else {
      if(agreement) {
        updateTokensMinted(tokenId);
      }
      _safeMint(_to,tokenId);      
    }   
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

      uint256 tokenId=_getRandomTokenId(0);
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

    function hasDaoRights(uint256 tokenId) public view returns(bool) {
      require(_exists(tokenId), "Token not minted");
      if(agreementTokens[tokenId] != address(0)) {
        return(false);
      }
      else {
        return(true);
      }
    }

  /* @dev: Transfiere fondos hacia el Payment Splitter
   * La funcion permanece publica para que cualquiera pueda iniciar las transferencias, lo que evita que los fondos permanezcan 
   * rehenes en el contrato, en caso de existir discrepancias entre los beneficiarios finales de los fondos.
   * En virtud que PaymentSplitter es invariable luego del lanzamiento del contrato, y que los fondos no pueden ser enviados a ninguna
   * otra dirección, es seguro que la funcion quede publica.
   * 
   */

    function withdraw() public {
      address payable __to=payable(abcPayment);      
      uint256 __available=address(this).balance;
      require(__available >0,"Insuficient funds");
      __to.transfer(__available);
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
 


    function transferABCVaultOwnership(address _newOwner) public onlyOwner {
      ABCVault _vault = ABCVault(abcVault);
      _vault.transferOwnership(_newOwner);
    }

    // internal
    function _baseURI() internal view virtual override returns (string memory) {
      return baseURI;
    }

    function _getRandomTokenId(uint256 _seed) private view returns (uint256) {
      uint256 tokenId=Random.generate(2,maxToSale,_seed);
      while(_exists(tokenId)) {
        tokenId=Random.generate(2,maxToSale,tokenId);
      } 
      return tokenId;
    }


    /* @dev: Create Belters Day information
    * Set the dates for the next 20 Belters Days and assign the number of NFTs that will be minted for free, according to the white paper.
    * Belters Day July 7th.
    */

  function _assignBeltersDay() private {
    beltersDay.push(1656633600); // year: 2022
    beltersDay.push(1688169600); // year: 2023
    beltersDay.push(1719792000); // year: 2024
    beltersDay.push(1751328000); // year: 2025
    beltersDay.push(1782864000); // year: 2026
    beltersDay.push(1814400000); // year: 2027
    beltersDay.push(1846022400); // year: 2028
    beltersDay.push(1877558400); // year: 2029
    beltersDay.push(1909094400); // year: 2030
    beltersDay.push(1940630400); // year: 2031
    beltersDay.push(1972252800); // year: 2032
    beltersDay.push(2003788800); // year: 2033
    beltersDay.push(2035324800); // year: 2034
    beltersDay.push(2066860800); // year: 2035
    beltersDay.push(2098483200); // year: 2036
    beltersDay.push(2130019200); // year: 2037
    beltersDay.push(2161555200); // year: 2038
    beltersDay.push(2193091200); // year: 2039
    beltersDay.push(2224713600); // year: 2040
    beltersDay.push(2256249600); // year: 2041
    beltersDayAssigned[1656633600]=4100;
    beltersDayAssigned[1688169600]=2100;
    beltersDayAssigned[1719792000]=1100;
    beltersDayAssigned[1751328000]=600;
    beltersDayAssigned[1782864000]=350;
    beltersDayAssigned[1814400000]=225;
    beltersDayAssigned[1846022400]=162;
    beltersDayAssigned[1877558400]=131;
    beltersDayAssigned[1909094400]=115;
    beltersDayAssigned[1940630400]=107;
    beltersDayAssigned[1972252800]=103;
    beltersDayAssigned[2003788800]=101;
    beltersDayAssigned[2035324800]=101;
    beltersDayAssigned[2066860800]=101;
    beltersDayAssigned[2098483200]=101;
    beltersDayAssigned[2130019200]=101;
    beltersDayAssigned[2161555200]=101;
    beltersDayAssigned[2193091200]=101;
    beltersDayAssigned[2224713600]=100;
    beltersDayAssigned[2256249600]=100;
  }
}
/*
 * @title: Asteroid Belt Club Vault Smart Contract
 * @author: Gustavo Hernandez Baratta  (The Pan de Azucar Bay Company LLC)
 * @dev: Tiene por objeto acumular los ingresos derivados del registro de reclamos de propiedad sobre los asteroides
 * y sus posteriores transferencias, asi como cualquier otro ingreso que en el futuro se obtenga y que pase a formar 
 * parte de los activos que el Club acumulara para perseguir los objetivos comunitarios.
 * 
 * Aunque inicialmente la propiedad del contrato estará en manos del contrato ABC, esta previsto que se transfiera a la DAO
 * una vez que se hayan implementado las funciones que permitan gestionar esta boveda en forma autonoma. Para ello, la funcion 
 * transferABCVaultOwnership ha sido implementada para ser ejecutada por el ABC Starter (el owner del contrato original) y desarrollador
 * del proyecto.
 *
 * El contrato puede recibir fondos, pero solo puede transferirlos a terceros mediante un mecanismo de tres pasos, uno, en el que se registra
 * un pago pendiente de aprobacion (funcion addPayment), un segundo que aprueba el pago (funcion aprovePayment) y finalmente uno que lo 
 * ejecuta (funcion pay). addPayment solo puede ser ejecutado por onlyOwner, por lo que mientras no sea transferida la propiedad de la boveda
 * a una direccion capaz de ejecutarla, ningun pago podra ser iniciado. Adicionalmente, entre cada una de las instancias se establece un retardo
 * de 63600 bloques (aproximadamente 10 dias), establecido para alertar a la comunidad sobre una potencial transferencia indebida de fondos.
 *
 * Adicionalmente, la boveda recibira la propiedad del token correspondiente al reclamo de propiedad del asteroide 1 (A801 AA - Ceres), 
 * pero no tiene ninguna funcion que le permita transferirlo a un tercero.  
 */
contract ABCVault is IERC721Receiver, Ownable {

  struct payment {
    string description;
    address to;
    uint256 amount;
    bool aproved;
    address activator;
    uint256 validblock;
    bool paid;     
  }  
  mapping(uint256=>payment) public paymentlist;
  uint256 _paymentCounter;
  uint256 public constant blocksDelay=63600;

  event PaymentReceived(address indexed from, uint256 amount, uint256 balance);
  event PaymentAdded(address indexed sender, address indexed to, address indexed activator, uint256 amount, string description, uint256 id, uint256 delayedto);
  event PaymentAproved(uint256 id, address aprover, uint256 currentBlock, uint256 delayed);
  event Paid(uint256 id, address executor, uint256 currentBlock, uint256 balance );


  receive() external payable {
    emit PaymentReceived(_msgSender(), msg.value, address(this).balance);
  }
  
  function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
    return this.onERC721Received.selector;
  }

  /* @dev: Permite agendar pago descripto en _description a _to, por un monto _amount, que deberan ser aprobados por _activator.
   * Solo el owner del contrato puede agendar un pago (inicialmente el contrato ABC, el que no tiene capacidad de llamar esta funcion).
   * El objetivo es que sea la DAO la que llame esta funcion y delegue a un contrato de votacion su aprobacion. 
   * La funcion devuelve un id de pago, que será el que deba especificarse en las funciones aprovePayment y pay
   */
  function addPayment(string memory _description, address _to, uint256 _amount, address _activator) public onlyOwner returns(uint256) {  
    require(_amount >0,"Amount must be greather than 0");
    require(_to != address(0), "Please specify a destination address");
    require(_activator != address(0), "Please specify an activator address");
    payment memory __payment;
    _paymentCounter++;
    __payment.description=_description;
    __payment.to=_to;
    __payment.amount=_amount;
    __payment.activator=_activator;
    __payment.validblock=block.number + blocksDelay;
    paymentlist[_paymentCounter]=__payment;
    emit PaymentAdded(_msgSender(),_to,_activator,_amount,_description,_paymentCounter,__payment.validblock);
    return _paymentCounter;
  }

  /* @dev: Funcion que le permite a la direccion especificada en _activator de la funcion addPayment aprobar el pago
   * El proposito es que el contrato inteligente donde se someta a votacion el pago ejecute esta función si la misma 
   * resulto afirmativa. Aunque cualquiera puede ejecutar la funcion, solo desde activator no dara error.
   */
  function aprovePayment(uint256 _id) public {
    require(paymentlist[_id].to != address(0),"Payment don't exist");
    require(paymentlist[_id].aproved==false,"Payment already aproved");    
    require(paymentlist[_id].activator==_msgSender(),"Yo cannot aprove this payment");
    require(paymentlist[_id].validblock < block.number,"Wait for a valid block to aprove payment");
    paymentlist[_id].validblock=block.number+blocksDelay;
    paymentlist[_id].aproved=true;
    emit PaymentAproved(_id,_msgSender(), block.number, paymentlist[_id].validblock);

  }

  /* @dev: Ejecuta el pago ingresado en addPayment y aprovado en aprovePayment.
   * Adicionalmente al retardo de blocksDelay desde el momento de la aprobacion, se requiere que el balance de la boveda
   * tenga fondos suficientes para la transferencia.
   */
  function pay(uint256 _id) public {
    require(paymentlist[_id].to != address(0),"Payment don't exist");
    require(paymentlist[_id].aproved==true,"Payment not yet aproved");
    require(paymentlist[_id].paid==false,"Payment already paid");    
    require(paymentlist[_id].validblock < block.number,"Wait for a valid block to send payment");
    require(paymentlist[_id].amount <= address(this).balance,"Not enough balance to process this payment");
    paymentlist[_id].paid=true;
    address payable __to=payable(paymentlist[_id].to);
    __to.transfer(paymentlist[_id].amount);
    emit Paid(_id, _msgSender(), block.number, address(this).balance);
  }
}


/* @title: ABCPayments
 * @dev: Contrato que recibe todos los pagos y divide los ingresos entre las wallets indicadas en el costructor, de 
 * acuerdo a los porcentajes derivados de todos los shares indicados.
 * 
 */

contract ABCPayments is  PaymentSplitter {

  constructor(address[] memory _payees, uint256[] memory _shares) PaymentSplitter(_payees,_shares) {

  }

}
