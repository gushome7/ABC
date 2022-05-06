// SPDX-License-Identifier: MIT
/*
 * @title: Asteroid Belt Club NFT Smart Contract
 * @author: Gustavo Hernandez Baratta  (The Pan de Azucar Bay Company LLC)
 * @dev Smart contract for the creation and management of the NFTs corresponding
 * to the first property claim on the asteroids of the Asteroid Belt.
 
 * email: ghernandez@pandeazucarbay.com
 *
 */

pragma solidity ^0.8.1;

import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/common/ERC2981.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/access/Ownable.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

import "./Agreements.sol";
import "./Kickstarter.sol";
import "./utils/Random.sol";
import "./utils/PaymentSplitter.sol";

contract ABC is ERC2981, ERC721Enumerable, Agreements, Kickstarter {
  using Strings for uint256;

  /* ABC Collection parameters and stored data */    
  string public baseURI; 
  string public constant baseExtension = ".json";
  string public constant _name='Asteroid Belt Club';
  string public constant _symbol='ABC';
  uint96 royaltyFee=1000; //10%

  /* Asteroid Naming Services*/
  mapping(uint256 => string) private _ansModifiedURI; //Asteroid Naming Services Modifier;
  address private _ansAddress;

  
  uint256 public costRandom = 0.05 ether;
  uint256 public costSelected = 1 ether;
  uint256 public maxSupply = 605011;
  uint256 public maxToSale = 550000;
  uint256 public totalSales = 0; //
  uint256 public constant maxMinting=200; //Cantidad maxima de tokens a mintear en una llamada a mint()
  bool public paused = false;

  /* ABC Starter Minting Privileges passed to kickstarter*/
  uint256 public constant ownerCanMintMax=999 ether; //1000 ether - 1 ether for 20 random minted on constructor
  
  /* Belters Day parameters and stored*/
  mapping(uint256 => uint256) public beltersDayAssigned;
  uint256[] public beltersDay;
  mapping(address => bool) public belters;

  /* ABC Vault and Payment Splitter address filled at deployment */
  address payable public abcVault;
  address public abcPayment;

  event PaymentReceived(address from, uint256 amount);
  event VaultOwnerShipTransfered(address newOwner);
  event StateChanged(bool newState);
  event NewCosts(uint256 oldSelected, uint256 oldRandom, uint256 newSelected, uint256 newRandom);
  event Withdrawn(address sender, uint256 amount);
  event NewMaxSupply(uint256 oldMaxSupply, uint256 newMaxSupply);
  event URIChanged(uint256 indexed tokenId, string newURI);
  event RightsUpgraded(uint256 indexed tokenId);

  constructor( string memory _initBaseURI) ERC721(_name, _symbol) Kickstarter(ownerCanMintMax) {
    _ansAddress=address(0);
    uint256[] memory _ceres=new uint256[](1);
    uint256[] memory _dumb=new uint256[](0);
    _ceres[0]=1;
    abcVault = payable(new ABCVault());
    address[] memory _payees=new address[](2);
    uint256[] memory _shares=new uint256[](2);
    _payees[0]=abcVault;
    _payees[1]=_msgSender();
    _shares[0]=70;
    _shares[1]=30;
    abcPayment = address(new ABCPayments(_payees,_shares));
    _setDefaultRoyalty(abcPayment, royaltyFee); //Royalties must be paid directly to abcPayment.
    setBaseURI(_initBaseURI);  
    _assignBeltersDay(); //Belters Day Assignment.
    mint(abcVault,_ceres,1); //Ceres will remain in ABC property forever. Minted and transfered to ABCVault    
    mint(owner(), _dumb, 20); //Mint 20 random asteroids to start secondary market at marketplaces and transfer to owner()
  }

  /* @dev: Este contrato se desarrollo de acuerdo a las reglas que definen el funcionamiento de la comunidad Asteroid Belt Club
   * El documento que las contiene esta disponible en la direccion que devuelve esta funcion
   */
  function manifest() public pure returns(string memory) {
    return "ipfs://ladireccionipfsdelmanifiesto.pdf";
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC2981, ERC721Enumerable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /* @dev: Fallback para recibir pagos directos al contrato.
   * TODO: Emitir evento pago recibido.
   */
  receive() external payable  {      
    emit PaymentReceived(_msgSender(), msg.value);

  }

  /* @dev: Mintea el o los tokens especificados en tokenIds, o selecciona en forma random hasta la cantidad establecida en _toMint.
   * _toMint no puede ser mayor a maxMinting. Cuando se especifican tokenIds _toMint se ajusta a la cantidad.
   * La coleccion no tendra mas que maxSupply elementos. maxSupply es la cantidad de asteroides numerados por el IAU
   * Aunque maxSupply se vaya actualizando en el tiempo, no afectara la cantidad de elementos de la coleccion en la medida que
   * no se mintearan mas que maxToSale para ser vendidos y este limite permanecera inalterado.
   * El resto de los asteroides podran ser minteados para ser transferidos en el marco
   * de acuerdos o convenios (reserva estrategica), lo que será decidido por los miembros del ABC.
   * El costo base del minteo sera costRandom cuando no se especifique tokenId, o costSelected cuando se elija uno para mintear
   */
  function mint(address _to, uint256[] memory _tokenIds, uint256 _toMint) public payable {
    uint256 __supply = totalSupply();
    uint256 __cost = costRandom;
    uint256 __tokenId=0;
    bool __agreement=false;
    require(!paused, "Minting paused. Try again later");
    
    require(__supply + _toMint < maxSupply, "Currently no NFT left to mint");
    require((__supply + _toMint - agreementMinted) < maxToSale, "Currently no NFT left to mint");

    if(_toMint==0) {
      _toMint=1;
    }

    if(_tokenIds.length >0) {
      __cost= costSelected;
      _toMint=_tokenIds.length;
    }
    __cost=__cost * _toMint;
    require(_toMint <= maxMinting,string(abi.encodePacked("Please mint no more that ",maxMinting.toString()," per call")));
    if(msg.value==0 && getKickStartBalance(_msgSender()) >= __cost) {
      updateKickStartBalance(__cost,_toMint);
    }
    else if(msg.value==0 && getAgreementBalance(_msgSender())>=__cost) {
      updateAgreementBalance(__cost,_toMint);
      __agreement=true;
    }
    else {
      require(msg.value == __cost,string(abi.encodePacked("To do this mint you must send ", __cost.toString())));
    }
    _registerTotal(msg.value);
    if(_tokenIds.length==0) {      
      for(uint256 i=0; i<_toMint; i++) {
        __tokenId=_getRandomTokenId(__tokenId);
        if(__agreement) {
          updateTokensMinted(__tokenId);
        }
        _safeMint(_to,__tokenId);
      }
    }
    else {
      for(uint256 i=0; i<_tokenIds.length; i++) {
        __tokenId=_tokenIds[i];      
        require(!_exists(__tokenId), "Token already minted ");
        if(__agreement) {
          updateTokensMinted(__tokenId);
        }
      _safeMint(_to,__tokenId);      
      }
    }   
  }

    /* @dev: Claim a BeltersDay free token to mint.
    * Los NFT pueden ser reclamados a partir de las 00:00 GMT del dia beltersday, hasta la cantidad máxima especificada para ese
    * año al momento de publicar el contrato. Cuando se agota la cantidad debe esperarse hasta el año próximo.
    * Solo un NFT puede ser minteado con esta función por cada dirección.
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
      beltersDayAssigned[currentBeltersDay]--;
      belters[_msgSender()]=true;
      _safeMint(_msgSender(),tokenId);
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

    /* @dev: Devuelve la URI del token. Si el asteroide fue renombrado por el Asteroid Naming Service
     * entonces la URI devuelta sera la correspondiente al manifiesto modificado, aunque podrá
     * accederse al manifiesto anterior.
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

    /* @dev: Chequea si el NFT id tiene derechos totales en la DAO.
     * Solo los NFT minteados con las funciones mint y claim tendran derechos totales en la DAO del Club.
     * Los emitidos en virtud de acuerdos, tendran derechos restringidos, de acuerdo a lo establecido en el
     * WhitePaper
     */
    function hasDaoRights(uint256 tokenId) public view returns(bool) {
      require(_exists(tokenId), "Token not minted");
      if(agreementTokens[tokenId] != address(0)) {
        return(false);
      }
      else {
        return(true);
      }
    }

    /* @dev: Si los tokens emitidos por un acuerdo pueden obtener derechos totales, esta funcion la que
     * los otorga si el pago recibido es el estipulado en el acuerdo.
     */
    function giveMeDaoRights(uint256 _tokenId) public payable {        
        require(_exists(_tokenId), "Token not minted");
        require(agreementTokens[_tokenId] != address(0), "Token have full rights");
        agreement memory _agreement=getAgreement(agreementTokens[_tokenId]);
        require(_agreement.befull>0, "Agreement don't allow improve token rights");
        require(msg.value==_agreement.befull,string(abi.encodePacked("You must send ", _agreement.befull.toString()," to get full rights")));
        delete agreementTokens[_tokenId];
        emit RightsUpgraded(_tokenId);
    }


  /* @dev: Transfiere fondos hacia el Payment Splitter
   * La funcion permanece publica para que cualquiera pueda iniciar las transferencias, lo que evita que los fondos permanezcan 
   * rehenes en el contrato, en caso de existir discrepancias entre los beneficiarios finales de los fondos.
   * En virtud que PaymentSplitter es invariable luego del lanzamiento del contrato, y que los fondos no pueden ser enviados a ninguna
   * otra dirección, es seguro que la funcion quede publica.
   */
    function withdraw() public {
      address payable __to=payable(abcPayment);      
      uint256 __available=address(this).balance;
      require(__available >0,"Insuficient funds");
      __to.transfer(__available);
      emit Withdrawn(_msgSender(),__available);
    }

    /* @dev: Sobreescribe la URI del token para que refleje los cambios efectuados desde el Asteroid Naming Service (ANS)
     * Hasta que el servicio este disponible esta funcion no podra ser utilizada.
     * La funcion no podra ser utilizada mas de una vez por token. ANS no llamara a esta funcion si el asteroide fue nombrado
     * por la IAU.
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

    /* @dev: Permite establecer nuevos precios para el minteo random y por ID. 
     * La funcion esta restringida al owner del contrato. 
     * Se establece el requisito de que el nuevo precio deba ser mayor al actual, como forma de proteger
     * los intereses de los titulares de ejemplares ya minteados, los que tienen la garantia de que otros no podran 
     * acceder a condiciones mejores a las que el tuvo.
     */
    function setCosts(uint256 _newSelected, uint256 _newRandom) public onlyOwner {
      require(_newSelected > costSelected, "New cost must be greather than current");
      require(_newRandom > costRandom, "New cost must be greather than current");
      uint256 __oldSelected=costSelected;
      uint256 __oldRandom=costRandom;
      costSelected = _newSelected;
      costRandom = _newRandom;
      emit NewCosts(__oldSelected, __oldRandom, costSelected, costRandom);
    }


    /* @dev: Permite reconfigurar la uri base del contrato. Las modificaciones al directorio IPFS donde se alojan los
     * manifiestos requiere el llamado a esta funcion. Todas las URI anteriores seguiran vigentes para los manifiestos 
     * previamente consultados. La funcion es requerida para actualizar la cantidad de asteroides reconocidos y el minteo
     * de sus NFT.
     */
    function setBaseURI(string memory _newBaseURI) public onlyOwner {      
      baseURI = _newBaseURI;
    }

    /* @dev: Pausa/restituye las funciones mint, claim y kickstart
     */
    function pause(bool _state) public onlyOwner {
      paused = _state;
      emit StateChanged(_state);
    }

    /* @dev: Actualiza maxSupply.
     * maxSupply representa el numero mas alto de asteroide numerado por la IAU. Periodicamente ABC Starter actualizara la 
     * cantidad maxima, y generara los archivos disponibles para que puedan ser minteados. En caso que la cantidad maxima para
     * ser ofrecidos al mercado haya sido alcanzada, solo podran ser minteados mediante acuerdos estrategicos.
     */
    function setMaxSupply(uint256 _newMaxSupply) public onlyOwner {
      require(_newMaxSupply > maxSupply, "New max supply must be greather than current");
      uint256 __oldMaxSupply=maxSupply;
      maxSupply=_newMaxSupply;
      emit NewMaxSupply(__oldMaxSupply, maxSupply);
    }
 

    /* @dev: Transfiere la propiedad de la boveda del ABC. El objeto de la funcion es que sea ejecutada por ABC Starter
     * una vez que el smart contract de la DAO sea puesto en funcionamiento y tenga los mecanismos para gestionar la disposicion
     * de los fondos almacenados.
     */
    function transferABCVaultOwnership(address _newOwner) public onlyOwner {
      ABCVault _vault = ABCVault(abcVault);
      _vault.transferOwnership(_newOwner);
      emit VaultOwnerShipTransfered(_newOwner);
    }

    /* @dev: Una vez que el contrato de Asteroid Naming Services quede activo se configurara su direccion para que
     * pueda setear el nombre
     */
    function setAnsAddress(address _newAddress) public onlyOwner {
      _ansAddress=_newAddress;
    }

    // internal
    function _baseURI() internal view virtual override returns (string memory) {
      return baseURI;
    }

    /* @dev: Incrementa totalSales con amount. Implementa el hook de kickstarter.
    */
    function _registerTotal(uint256 amount) internal override {
      totalSales=totalSales+amount;
    }

    function _getRandomTokenId(uint256 _seed) private view returns (uint256) {
      uint256 tokenId=Random.generate(2,maxToSale,_seed);
      uint16 iterations=0;
      while(_exists(tokenId)) {
        tokenId=Random.generate(2,maxToSale,tokenId);
        iterations++;
        require(iterations < 200, "Please retry");
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
    require(bytes(_description).length >0, "Please add a description");
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
   * tenga fondos suficientes para la transferencia. La funcion puede ser ejecutada desde cualquier direccion, ya que los pagos
   * deben haber sido previamente ingresados y aprobados, y no puede ser alterado el destino de los mismos.
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
 * @dev: Contrato que recibe todos los fondos y divide los ingresos entre las wallets indicadas en el constructor, de 
 * acuerdo a los porcentajes derivados de todos los shares indicados.
 * Implementa el contrato PaymentSplitter, de OpenZeppelin
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/finance/PaymentSplitter.sol
 */

contract ABCPayments is  PaymentSplitter {

  constructor(address[] memory _payees, uint256[] memory _shares) PaymentSplitter(_payees,_shares) {

  }

}
